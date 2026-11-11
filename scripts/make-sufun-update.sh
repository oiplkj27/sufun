#!/usr/bin/env bash
# Builds and signs "sufun-update-<VERSION>.sufun" from the built packages.
# Used by the release workflow; can also run locally for testing.
#
#   bash scripts/make-sufun-update.sh <packages-dir> <output-dir>
#
# Signing: the SUFUN signing subkey must already be imported into gpg
# (the workflow does that from the GitHub secret). Optional environment:
#   SUFUN_SIGNING_PASSPHRASE   passphrase of the key (empty = none)
#   GNUPGHOME                  gpg folder that holds the key
# Release notes: release-notes/<VERSION>.txt (Korean) and, optionally,
# release-notes/<VERSION>.min-from = the oldest version this update can be installed on.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGS="${1:?usage: make-sufun-update.sh <packages-dir> <output-dir>}"
OUT="${2:?usage: make-sufun-update.sh <packages-dir> <output-dir>}"
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION")"
NOTES="$HERE/release-notes/$VERSION.txt"
MINF="$HERE/release-notes/$VERSION.min-from"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"; PKGS="$(cd "$PKGS" && pwd)"
[[ -f $NOTES ]] || { echo "missing $NOTES (Korean release notes)" >&2; exit 1; }
MIN=""; [[ -f $MINF ]] && MIN="$(tr -d '[:space:]' < "$MINF")"

# Never ship build-only packages (marked "build-only" in packages/aur.txt)
mapfile -t BUILD_ONLY < <(awk '{sub(/#.*/,"")} $2=="build-only"{print $1}' "$HERE/packages/aur.txt")

sign() {  # detached binary signature, as pacman expects (<file>.sig)
  gpg --batch --yes --pinentry-mode loopback --passphrase "${SUFUN_SIGNING_PASSPHRASE:-}" \
      --detach-sign --output "$1.sig" "$1"
}

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/packages"
for p in "$PKGS"/*.pkg.tar.zst; do
  n="$(basename "$p")"
  [[ $n == *-debug-* ]] && continue
  for b in "${BUILD_ONLY[@]}"; do [[ $n == "$b"-[0-9]* ]] && continue 2; done
  cp "$p" "$STAGE/packages/"
  sign "$STAGE/packages/$n"
done
ls "$STAGE"/packages/sufun-base-"$VERSION"-*.pkg.tar.zst >/dev/null \
  || { echo "sufun-base-$VERSION package not found in $PKGS" >&2; exit 1; }

printf 'format=1\nversion=%s\nmin_from=%s\nbuilt=%s\n' "$VERSION" "$MIN" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STAGE/manifest"
cp "$NOTES" "$STAGE/notes.ko.txt"
# (written outside $STAGE first, so the list does not contain itself)
( cd "$STAGE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | xargs sha256sum ) > "$STAGE.sums"
mv "$STAGE.sums" "$STAGE/SHA256SUMS"
sign "$STAGE/SHA256SUMS"

F="$OUT/sufun-update-$VERSION.sufun"
# Plain tar (packages are already compressed). Fixed owner/order for reproducibility.
( cd "$STAGE" && tar --owner=0 --group=0 --numeric-owner --sort=name -cf "$F" \
    manifest notes.ko.txt SHA256SUMS SHA256SUMS.sig packages )
echo "$F"
