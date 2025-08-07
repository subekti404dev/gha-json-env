#!/bin/bash

set -euo pipefail

URL="$1"
STYLE="${2:-snake}"
TOKEN="${3:-}"

echo "📥 Fetching env.json from $URL"

if [ -n "$TOKEN" ]; then
  AUTH_HEADER="Authorization: Bearer $TOKEN"
  curl -sSL --fail -H "$AUTH_HEADER" "$URL" -o env.json || {
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
  def flatten($prefix):
    to_entries[] |
    if (.value | type) == "object" then
      (.value | flatten($prefix + format_key(.key) + separator()))
    elif (.value | type) == "array" then
      .value | to_entries[] |
      if (.value | type) == "object" then
        (.value | flatten($prefix + format_key(.key) + separator() + "\(.key)" + separator()))
      else
        "\($prefix)\(format_key(.key))_\(.key)=\(.value|tostring)"
      end
    else
      "\($prefix)\(format_key(.key))=\(.value|tostring)"
    end;

  def format_key(k):
    if $style == "camel" then
      (k | gsub("_"; " ") | split(" ") | .[0] + ([.[1:][] | ascii_upcase] | join("")))
    elif $style == "dot" then
      k
    else
      k
    end;

  def separator():
    if $style == "dot" then "." else "_" end;

  flatten("")
' env.json | while IFS= read -r line; do
  VAR_NAME="${line%%=*}"
  echo "Setting env: $VAR_NAME"
  echo "$line" >> "$GITHUB_ENV"
done

echo "✅ Done."
