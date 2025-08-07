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
  # Split a raw key segment on common separators to avoid duplicating names
  def split_seg(s):
    s | gsub("[\\.\\-]"; "_") | split("_") | map(select(length>0));

  # Convert array of tokens to desired case
  def to_snake(tokens):
    tokens | map(ascii_downcase) | join("_");

  def to_camel(tokens):
    if (tokens|length)==0 then ""
    else
      (tokens[0] | ascii_downcase) +
      (tokens[1:] | map( (.[0:1] | ascii_uppercase) + (.[1:] | ascii_lowercase) ) | join(""))
    end;

  def to_dot(tokens):
    tokens | map(ascii_downcase) | join(".");

  # Format a raw key segment into normalized token array
  def seg_tokens(s): split_seg(s) | map(ascii_downcase);

  # Join path array of raw segments according to style
  def join_path(path):
    # Flatten tokens from each raw segment to preserve hierarchy but avoid duplication like host_host
    if $style == "camel" then
      (path | map(seg_tokens(.)) | flatten | to_camel)
    elif $style == "dot" then
      (path | map(seg_tokens(.)) | flatten | to_dot)
    else
      (path | map(seg_tokens(.)) | flatten | to_snake)
    end;

  # Recursive walker producing KEY=VALUE strings
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
