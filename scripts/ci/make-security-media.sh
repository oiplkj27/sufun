#!/usr/bin/env bash
# Makes the test media for the update attack tests (sufun-selftest,
# update_attack_tests; see docs/security-audit.md):
#   bash scripts/ci/make-security-media.sh <sufun-packages.tar> <output.iso>
#
# It uses the REAL release tools on the packages of this build, but with a
# THROWAWAY key that is made here and thrown away with the CI machine:
#   scripts/sufun-key.sh create      -> test key (primary + signing subkey)
#   scripts/make-sufun-update.sh     -> sufun-update-<version>.sufun, signed with the
#                                       subkey only (exactly like the release workflow)
# On the media (label SUFUNSEC): the .sufun file, the test public key and the test
# secret key (the VM signs its own "attacker" and "newer version" files with it).
# The real SUFUN signing key is never used, needed or present here.
#
# Needs: gpg, tar, sha256sum, xorriso.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKGTAR="$(realpath "${1:?packages tar}")"; OUT="${2:?output iso}"
W="$(mktemp -d)"; trap 'gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$W"' EXIT

# A small copy of the repository (the key tool writes keys/sufun.asc into it)
mkdir -p "$W/repo" "$W/pkgs" "$W/media" "$W/key"
cp -r "$HERE/scripts" "$HERE/VERSION" "$HERE/release-notes" "$HERE/packages" "$W/repo/"
mkdir -p "$W/repo/keys"
tar -xf "$PKGTAR" -C "$W/pkgs"

# Name and e-mail questions answered with Enter (defaults); no passphrase (test only)
printf '\n\n' | SUFUN_KEY_NOPASS=1 bash "$W/repo/scripts/sufun-key.sh" create "$W/key" >/dev/null
[[ -s $W/repo/keys/sufun.asc && -s $W/key/sufun-signing-subkey-for-github.asc ]] || { echo "test key was not made" >&2; exit 1; }

# Sign like the release workflow: a keyring that holds ONLY the signing subkey
export GNUPGHOME="$W/gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
gpg --batch --quiet --import "$W/key/sufun-signing-subkey-for-github.asc"
gpg --batch --quiet --import "$W/repo/keys/sufun.asc"
SUFUN_SIGNING_PASSPHRASE='' bash "$W/repo/scripts/make-sufun-update.sh" "$W/pkgs" "$W/media" >/dev/null
ls "$W"/media/*.sufun >/dev/null

cp "$W/repo/keys/sufun.asc" "$W/media/test-public.asc"
cp "$W/key/sufun-primary-SECRET.asc" "$W/media/test-SECRET-throwaway.asc"
echo "Throwaway test key for the SUFUN CI security tests. Not the SUFUN release key." > "$W/media/README.txt"

if [[ $OUT == *.dir ]]; then          # local dry runs: a folder instead of an ISO
  rm -rf "$OUT"; cp -r "$W/media" "$OUT"
else
  xorriso -as mkisofs -quiet -V SUFUNSEC -J -R -o "$OUT" "$W/media"
fi
echo "security test media: $OUT ($(ls "$W/media" | tr '\n' ' '))"
