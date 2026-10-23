#!/usr/bin/env bash
set -euo pipefail
EXPERIMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=MYCustomFaceExperiment
case "${PLATFORM_NAME:-}" in
  watchsimulator) VARIANT=Simulator; EXPECTED=WATCHOSSIMULATOR ;;
  watchos) VARIANT=Device; EXPECTED=WATCHOS ;;
  *) echo "ERROR: Unsupported PLATFORM_NAME=${PLATFORM_NAME:-unset}" >&2; exit 1 ;;
esac
SOURCE="$EXPERIMENTS/Build/$VARIANT/$NAME.framework"
[[ -f "$SOURCE/$NAME" ]] || { echo "ERROR: Missing $SOURCE/$NAME" >&2; exit 1; }
xcrun vtool -show-build "$SOURCE/$NAME" | grep -q "platform $EXPECTED" || {
  echo "ERROR: Wrong platform in $SOURCE" >&2; exit 1;
}
DEST="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
mkdir -p "$DEST"
rm -rf "$DEST/$NAME.framework"
/usr/bin/ditto "$SOURCE" "$DEST/$NAME.framework"
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == YES ]]; then
  ID="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  if [[ -n "$ID" ]]; then
    /usr/bin/codesign --force --sign "$ID" "$DEST/$NAME.framework"
  fi
fi
echo "EMBED SUCCESS: $VARIANT"
