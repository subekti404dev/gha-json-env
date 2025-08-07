# Fetch & Flatten Remote ENV

A GitHub Action that downloads a remote JSON file (public or protected), flattens it into environment variables, and exports them to the GitHub Actions environment (GITHUB_ENV).

- Supports nested objects and arrays
- Three key styles:
  - snake (default): database_host
  - camel: databaseHost
  - dot: database.host
- Optional Bearer token for protected URLs


## Inputs

- url (required)
  - Public or protected URL pointing to a JSON file
  - Must start with http:// or https://

- style (optional)
  - Key style used when flattening
  - Allowed values: snake (default), camel, dot

- token (optional)
  - Bearer token to access protected endpoints
  - When omitted, no Authorization header is sent


## How It Works

1. Fetches JSON from the provided URL
2. Validates the JSON
3. Flattens nested keys into a single-level map
4. Writes KEY=VALUE lines to GITHUB_ENV so subsequent steps can use them via $VARIABLE_NAME


## Usage

Basic (public JSON):
```yaml
- name: Load ENV from JSON (public)
  uses: subekti404dev/gha-json-env@v1
  with:
    url: https://example.com/config/env.json
```

Protected JSON with Bearer token:
```yaml
- name: Load ENV from JSON (protected)
  uses: subekti404dev/gha-json-env@v1
  with:
    url: https://api.example.com/config/env.json
    token: ${{ secrets.CONFIG_BEARER_TOKEN }}
```

Choose key style (camel or dot):
```yaml
- name: Load ENV (camelCase keys)
  uses: subekti404dev/gha-json-env@v1
  with:
    url: https://example.com/config/env.json
    style: camel
```

Use flattened variables:
```yaml
- name: Print variables
  run: |
    echo "DB Host: $database_host"
    echo "DB Password: $database_password"
```

## Example

Given the JSON at your URL:
```json
{
  "database": {
    "host": "abc",
    "password": "1234"
  },
  "services": [
    { "name": "auth", "enabled": true },
    { "name": "api", "enabled": false }
  ]
}
```

Output variables:

- For style: snake (default)
  - database_host=abc
  - database_password=1234
  - services_0_name=auth
  - services_0_enabled=true
  - services_1_name=api
  - services_1_enabled=false

- For style: camel
  - databaseHost=abc
  - databasePassword=1234
  - services0Name=auth
  - services0Enabled=true
  - services1Name=api
  - services1Enabled=false

- For style: dot
  - database.host=abc
  - database.password=1234
  - services.0.name=auth
  - services.0.enabled=true
  - services.1.name=api
  - services.1.enabled=false


## Notes

- This action runs on Node 20 runtime and does not require external dependencies.
- If the JSON cannot be fetched or parsed, the action fails early with a clear error message.
- The token input is optional. When provided, requests include `Authorization: Bearer <token>` header.


## Full Workflow Example

```yaml
name: Example - Fetch & Flatten ENV

on:
  workflow_dispatch:

jobs:
  load-env:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Load ENV from JSON (protected, camelCase)
        uses: subekti404dev/gha-json-env@v1
        with:
          url: https://api.example.com/config/env.json
          token: ${{ secrets.CONFIG_BEARER_TOKEN }}
          style: camel

      - name: Use the variables
        run: |
          echo "databaseHost = $databaseHost"
          echo "First service name = $services0Name"
```

## Troubleshooting

- curl/malformed URL errors: Ensure the url input is non-empty and a valid http(s) URL.
- Invalid JSON: Confirm the URL returns valid JSON (status 200 with application/json).
- Missing variables in later steps: Verify the step using variables runs after this action and references the exact flattened key names based on your chosen style.

## License

MIT