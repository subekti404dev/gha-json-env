#!/bin/bash

set -e

echo "📥 Fetching env.json from $INPUT_URL"

# Prepare headers if token is given
AUTH_HEADER=""
if [[ -n "$INPUT_TOKEN" ]]; then
  AUTH_HEADER="Authorization: Bearer $INPUT_TOKEN"
fi

# Download and validate JSON
RESPONSE=$(curl -sSfL -H "$AUTH_HEADER" "$INPUT_URL") || {
  echo "❌ Failed to fetch JSON from $INPUT_URL"
  exit 1
}

echo "🔍 Validating JSON format"
echo "$RESPONSE" | jq empty || {
  echo "❌ Invalid JSON format"
  exit 1
}

echo "🔧 Flattening with style: $INPUT_STYLE"

# Use a temp file for jq to read
echo "$RESPONSE" > env.json

# jq script to flatten JSON with preserved parent path segments
jq -r --arg style "$INPUT_STYLE" '
  # Format a single segment according to style
  def fmt_seg(s):
    if $style == "camel" then
      # convert snake_or.dot to camelCase for segment
      (s
        | gsub("[\\.\\-_]"; " ")
        | split(" ")
        | if length == 0 then "" else
            (.[0] | ascii_downcase) +
            (.[1:] | map(ascii_downcase | ascii_upcase[0:0] as $x | .) | map( (.[0:1] | ascii_upcase) + .[1:] ) | join(""))
          end)
    elif $style == "dot" then
      s
    else
      # snake: normalize separators to underscore
      (s | gsub("[\\.\\-]"; "_"))
    end;

  # Join path segments according to style
  def join_path(path):
    if $style == "camel" then
      # first segment lowerCamel, subsequent start with Upper
      if (path|length) == 0 then ""
      else
        (path[0] | fmt_seg(.)) +
        ( (path[1:] | map(fmt_seg(.) | (.[0:1] | ascii_upcase) + .[1:]) | join("")) )
      end
    elif $style == "dot" then
      (path | map(fmt_seg(.)) | join("."))
    else
      (path | map(fmt_seg(.)) | join("_"))
    end;

  # Recursive walker producing [ "key" = "value" ] strings
  def walk(obj; path):
    if (obj | type) == "object" then
      obj
      | to_entries
      | map( walk(.value; path + [ .key ]) )
      | flatten
    elif (obj | type) == "array" then
      to_entries
      | map( walk(.value; path + [ (.key|tostring) ]) )
      | flatten
    else
      [ (join_path(path)) + "=" + (obj|tostring) ]
    end;

  walk(.; []) | .[]
' env.json | while IFS= read -r line; do
  VAR_NAME="${line%%=*}"
  echo "Setting env: $VAR_NAME"
  echo "$line" >> "$GITHUB_ENV"
done

echo "✅ Done."
