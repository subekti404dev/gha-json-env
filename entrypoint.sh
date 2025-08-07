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

# jq script to flatten JSON
jq -r --arg style "$INPUT_STYLE" '
  def format_key(k):
    if $style == "camel" then
      (k | gsub("_"; " ") | split(" ") | .[0] + ([.[1:][] | ascii_upcase] | join("")))
    elif $style == "dot" then
      k
    else
      k
    end;

  def separator:
    if $style == "dot" then "." else "_" end;

  def walk(obj; prefix):
    if (obj | type) == "object" then
      obj | to_entries | map(
        walk(.value; prefix + format_key(.key) + separator)
      ) | flatten
    elif (obj | type) == "array" then
      obj | to_entries | map(
        walk(.value; prefix + "\(.key)" + separator)
      ) | flatten
    else
      [prefix[:-1] + "=" + (obj|tostring)]
    end;

  walk(.; "") | .[]
' env.json | while IFS= read -r line; do
  VAR_NAME="${line%%=*}"
  echo "Setting env: $VAR_NAME"
  echo "$line" >> "$GITHUB_ENV"
done

echo "✅ Done."
