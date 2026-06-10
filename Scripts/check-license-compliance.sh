#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FORBIDDEN='(import[[:space:]]+(FirebaseAnalytics|GoogleAppMeasurement|GoogleAdsOnDeviceConversion))|("(FirebaseAnalytics|GoogleAppMeasurement|GoogleAdsOnDeviceConversion)")'

matches="$(git ls-files '*.swift' \
  | grep -v '^Scripts/check-license-compliance.sh$' \
  | xargs grep -nEH "$FORBIDDEN" 2>/dev/null || true)"

if [ -n "$matches" ]; then
  echo "❌ GPL-3.0 compliance violation: proprietary Google analytics SDK referenced." >&2
  echo "   FirebaseAnalytics links the closed-source GoogleAppMeasurement binary," >&2
  echo "   which is incompatible with the app's GPL-3.0 license. Remove the reference." >&2
  echo "" >&2
  echo "$matches" >&2
  exit 1
fi

echo "✅ License compliance: no proprietary Google analytics SDK is linked."
