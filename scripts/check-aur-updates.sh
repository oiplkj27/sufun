#!/usr/bin/env bash
# Compares our pinned copies of AUR packages (packages/pkgbuilds/*) with the
# current AUR versions and shows what changed, so you can review it BEFORE
# updating a pin. It only reads from the AUR; it never changes our files.
#
#   bash scripts/check-aur-updates.sh            check all vendored packages
#   bash scripts/check-aur-updates.sh bottles    check one package
#
# Works in Git Bash on Windows and on Linux (needs curl and diff).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUR=https://aur.archlinux.org
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

ver_of() {  # version string from a PKGBUILD file, e.g. 2:67.6-1
  bash -c 'source "$1" >/dev/null 2>&1; printf "%s%s-%s" "${epoch:+$epoch:}" "$pkgver" "$pkgrel"' _ "$1"
}

found_any=0
for dir in "$HERE"/packages/pkgbuilds/*/; do
  name=$(basename "$dir")
  [[ $# -gt 0 && " $* " != *" $name "* ]] && continue
  # Only packages copied from the AUR have this header line
  base=$(sed -n 's/^# Vendored from AUR \([^ ]*\) .*/\1/p' "$dir/PKGBUILD" | head -n1)
  [[ -n $base ]] || continue
  found_any=1
  ours=$(ver_of "$dir/PKGBUILD")
  json=$(curl -fsS "$AUR/rpc/v5/info?arg%5B%5D=$base") || { echo "!! $name: AUR not reachable"; continue; }
  theirs=$(sed -n 's/.*"Version":"\([^"]*\)".*/\1/p' <<< "$json")
  if [[ -z $theirs ]]; then
    printf '%-34s ours %-14s AUR: (package not found in the AUR any more!)\n' "$name" "$ours"
    continue
  fi
  if [[ $theirs == "$ours" ]]; then
    printf '%-34s ours %-14s AUR %-14s up to date\n' "$name" "$ours" "$theirs"
    continue
  fi
  printf '\e[1;33m%-34s ours %-14s AUR %-14s UPDATE AVAILABLE\e[0m\n' "$name" "$ours" "$theirs"
  # Download every file of the AUR package and compare with our copy.
  mkdir -p "$TMP/$name"
  if curl -fsSL "$AUR/cgit/aur.git/snapshot/$base.tar.gz" | tar -xz -C "$TMP/$name" 2>/dev/null; then
    echo "---- changes (- ours, + AUR). Lines starting with '# Vendored' / '# Review' / '# SUFUN' are our own notes."
    diff -ruN -x .SRCINFO -x .gitignore -x .nvchecker.toml "$dir" "$TMP/$name/$base" | sed 's/^/    /'
    echo "---- What to check before updating the pin:"
    echo "     * new source URLs: still the official upstream project?"
    echo "     * new commands in prepare()/build()/package(): downloads (curl, wget, pip, npm), 'curl | sh'?"
    echo "     * new .install file or post_install commands?"
    echo "     Then copy the new PKGBUILD over ours, keep our header lines, replace any SKIP checksum, rebuild."
  fi
  echo
done
(( found_any )) || echo "No vendored AUR packages found."
