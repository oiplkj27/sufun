#!/usr/bin/env bash
# Builds our own packages into a local pacman repository ("sufun-local"):
#   1. everything in packages/aur.txt, in that order, from OUR pinned copies in
#      packages/pkgbuilds/ (makepkg only: nothing is downloaded from the AUR)
#   2. sufun-keyring (our public signing key)
#   3. sufun-base (all SUFUN settings + the package list as dependencies)
#
# Usage (as root, on Arch): bash build-local-repo.sh /var/tmp/sufun-repo
# Optional: SUFUN_HOME_URL=https://github.com/you/sufun (else from $GITHUB_REPOSITORY)
#
# Note: makepkg -s installs build dependencies on the build machine. That is
# fine in the throwaway GitHub Actions container; on your own WSL Arch it leaves
# them installed there.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${1:?usage: build-local-repo.sh <repo-dir>}"
BUILDER=sufunbuild                   # makepkg refuses to run as root
BUILD_DIR=/var/tmp/sufun-build
DB="$REPO/sufun-local.db.tar.gz"
HOME_URL="${SUFUN_HOME_URL:-https://github.com/${GITHUB_REPOSITORY:-sufun-os/sufun}}"

log() { printf '\e[1;35m==> %s\e[0m\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }

pacman -S --needed --noconfirm base-devel
id "$BUILDER" &>/dev/null || useradd -m "$BUILDER"
echo "$BUILDER ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/90-sufunbuild
chmod 440 /etc/sudoers.d/90-sufunbuild
# Only while this script runs: on your own WSL Arch the build user must not keep
# password-less pacman (= root) afterwards (security audit B-2).
trap 'rm -f /etc/sudoers.d/90-sufunbuild' EXIT
rm -rf "$BUILD_DIR" "$REPO"
mkdir -p "$BUILD_DIR" "$REPO"
chown "$BUILDER:" "$BUILD_DIR"

# The local repo is added to this machine's pacman.conf, so a package built
# earlier can be installed as a dependency of a later one (makepkg -s).
tar -czf "$DB" -T /dev/null                      # empty database to start with
ln -sf sufun-local.db.tar.gz "$REPO/sufun-local.db"
if ! grep -q '^\[sufun-local\]' /etc/pacman.conf; then
  printf '\n[sufun-local]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$REPO" >> /etc/pacman.conf
fi
pacman -Sy --noconfirm

# These packages only copy files: their runtime dependencies (LibreOffice, or the
# whole desktop for sufun-base) are NOT needed to build them, so only their
# makedepends are installed and makepkg runs with -d (skip dependency install).
NODEPS=(libreoffice-extension-h2orestart sufun-keyring sufun-base)

build() {  # build <name> <source-dir> [extra files to copy in...]
  local name=$1 src=$2; shift 2
  log "Building $name"
  rm -rf "${BUILD_DIR:?}/${name:?}"
  cp -r "$src" "$BUILD_DIR/$name"
  local f; for f in "$@"; do [[ -e $f ]] && cp -r "$f" "$BUILD_DIR/$name/"; done
  chown -R "$BUILDER:" "$BUILD_DIR/$name"
  local mode=-s                       # -s: install dependencies first
  if [[ " ${NODEPS[*]} " == *" $name "* ]]; then
    local mk
    mk=$(cd "$BUILD_DIR/$name" && bash -c 'source ./PKGBUILD >/dev/null; echo "${makedepends[*]}"')
    [[ -n $mk ]] && pacman -S --needed --noconfirm $mk
    mode=-d
  fi
  # --cleanbuild: fresh src/. Checksums are always verified.
  sudo -u "$BUILDER" -H bash -c "cd '$BUILD_DIR/$name' && makepkg $mode --cleanbuild --noconfirm"
  find "$BUILD_DIR/$name" -maxdepth 1 -name '*.pkg.tar.zst' ! -name '*-debug-*' -exec cp {} "$REPO/" \;
  repo-add -q -R "$DB" "$BUILD_DIR/$name"/*.pkg.tar.zst
  pacman -Sy --noconfirm >/dev/null
}

# 1. packages/aur.txt, in order ("<name>" or "<name> build-only")
while read -r name _; do
  [[ -f $HERE/packages/pkgbuilds/$name/PKGBUILD ]] || { echo "no PKGBUILD for $name in packages/pkgbuilds/" >&2; exit 1; }
  build "$name" "$HERE/packages/pkgbuilds/$name"
done < <(awk '{sub(/#.*/,"")} NF {print $1, $2}' "$HERE/packages/aur.txt")

# 2. keyring (public key + revocation list; both may be missing in test builds)
build sufun-keyring "$HERE/sufun-keyring" "$HERE/VERSION" "$HERE/keys/sufun.asc" "$HERE/keys/sufun-revoked"

# 3. sufun-base
echo "$HOME_URL" > "$BUILD_DIR/HOME_URL"
build sufun-base "$HERE/sufun-base" "$HERE/VERSION" "$BUILD_DIR/HOME_URL" \
  "$HERE/packages/desktop.txt" "$HERE/packages/aur.txt"

log "Local repo $REPO:"
ls -1 "$REPO"
