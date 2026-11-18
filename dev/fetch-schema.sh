#!/usr/bin/env bash
# Refreshes the API specs the generated types come from: the @anvilco/types
# dependency in dev/package.json, bumped to the latest published version
# (https://www.npmjs.com/package/@anvilco/types), or the one given.
#
# The package ships the Anvil GraphQL schema (`@anvilco/types/schema.graphql`)
# and the OpenAPI spec (`@anvilco/types/openapi.json`), both regenerated from
# production after every deploy. The other clients generate from the same
# copy, so every client describes the same API build.
#
# Needs no API key. Then run `npm run generate` in dev/ to regenerate
# lib/anvil/types/generated.
#
# Usage: dev/fetch-schema.sh [@anvilco/types version]   (defaults to latest)
set -euo pipefail

PACKAGE="@anvilco/types"
VERSION="${1:-latest}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLED="$ROOT/dev/node_modules/$PACKAGE"

(cd "$ROOT/dev" && npm install --save-exact --no-audit --no-fund "$PACKAGE@$VERSION" >/dev/null)
RESOLVED="$(node -p "JSON.parse(require('fs').readFileSync('$INSTALLED/package.json','utf8')).version")"
echo "dev/package.json depends on $PACKAGE@$RESOLVED, which ships the GraphQL schema and the OpenAPI spec"
echo "Now run: cd dev && npm run generate"
