#!/usr/bin/env bash
#
# One-time local bootstrap for a fresh checkout. Scaffolds the gitignored secret
# files from their committed templates and generates CIKeys.generated.swift so
# the project compiles. Safe to re-run; it never overwrites existing files.
#
#     ./Scripts/setup-secrets.sh
#
# After running, open polkadot-app/env-vars.sh and the GoogleService-Info plists
# and fill in real values. See docs/PUBLISHING.md for details.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$ROOT_DIR/polkadot-app"
GS_DIR="$APP_DIR/GoogleService"

scaffold() {
    local template="$1" target="$2"
    if [ -f "$target" ]; then
        echo "✓ $target already exists — leaving untouched"
    elif [ -f "$template" ]; then
        cp "$template" "$target"
        echo "→ created $target from $(basename "$template")"
    else
        echo "⚠ template missing: $template" >&2
    fi
}

scaffold "$ROOT_DIR/.mcp.json.template" "$ROOT_DIR/.mcp.json"
scaffold "$APP_DIR/env-vars.sh.template" "$APP_DIR/env-vars.sh"
scaffold "$GS_DIR/GoogleService-Info-Dev.plist.template" "$GS_DIR/GoogleService-Info-Dev.plist"
scaffold "$GS_DIR/GoogleService-Info-Release.plist.template" "$GS_DIR/GoogleService-Info-Release.plist"
scaffold "$GS_DIR/GoogleService-Info-Dev.plist.template" "$APP_DIR/GoogleService-Info.plist"

echo ""
echo "Generating CIKeys.generated.swift..."
"$SCRIPT_DIR/inject-keys.sh"

echo ""
echo "Done. Next:"
echo "  1. Edit polkadot-app/env-vars.sh with real secrets."
echo "  2. Replace the GoogleService-Info plists with files from your Firebase project."
echo "  3. Set your Sentry org/project in .mcp.json (optional; for the Sentry MCP server)."
echo "  4. See docs/PUBLISHING.md before distributing a build."
