#!/bin/bash

set -euo pipefail

URL="$1"
STYLE="${2:-snake}"
TOKEN="${3:-}"

echo "📥 Fetching env.json from $URL"

if [ -n "$TOKEN" ]; then
  curl -sSL --fail -H "Authorization: Bearer $TOKEN" "$URL" -o env.json || {
    echo "❌ Failed to download protected JSON"
    exit 1
  }
else
  curl -sSL --fail "$URL" -o env.json || {
    echo "❌ Failed to download JSON"
    exit 1
  }
fi

echo "🔍 Validating JSON format"
jq empty env.json 2>/dev/null || {
  echo "❌ Invalid JSON format"
  exit 1
}

echo "🔧 Flattening with style: $STYLE"

jq -r --arg style "$STYLE" '
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

  walk(.; "")
' env.json | while IFS= read -r line; do
  VAR_NAME="${line%%=*}"
  echo "Setting env: $VAR_NAME"
  echo "$line" >> "$GITHUB_ENV"
done

echo "✅ Done."
