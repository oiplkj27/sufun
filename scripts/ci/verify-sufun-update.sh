#!/usr/bin/env bash
# Checks a finished .sufun update file the way sufun-update will check it on a
# Surface, but with the PUBLIC key from the repository (keys/sufun.asc):
#   bash scripts/ci/verify-sufun-update.sh <file.sufun> <public-key.asc> [expected-version]
# Used by the release workflow right after signing (a release that the installed
# systems would refuse is stopped before it is published) and by the CI test media.
# Needs: gpg/gpgv, tar, sha256sum. No private key.
set -euo pipefail
F="$(realpath "${1:?update file}")"; PUB="$(realpath "${2:?public key}")"; WANT="${3:-}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
die() { echo "verify-sufun-update: $*" >&2; exit 1; }

# The same two files the sufun-keyring package installs for sufun-update
mkdir -m 700 "$W/gnupg" 2>/dev/null || { mkdir -p "$W/gnupg"; chmod 700 "$W/gnupg"; }
gpg --homedir "$W/gnupg" --batch --dearmor < "$PUB" > "$W/sufun-release.gpg"
gpg --homedir "$W/gnupg" --batch --with-colons --show-keys "$PUB" \
  | awk -F: '$1=="pub"{w=1} $1=="fpr" && w {print $10; w=0}' > "$W/trusted"
[[ -s $W/trusted ]] || die "no key in $PUB"

good_sig() {  # good_sig <sig> <data>: good, not expired/revoked, by a primary key in keys/sufun.asc
  local st prim
  st=$(gpgv --homedir "$W/gnupg" --status-fd 1 --keyring "$W/sufun-release.gpg" "$1" "$2" 2>/dev/null) || return 1
  grep -q '^\[GNUPG:\] GOODSIG ' <<< "$st" || return 1
  grep -qE '^\[GNUPG:\] (REVKEYSIG|EXPKEYSIG|KEYREVOKED|KEYEXPIRED|EXPSIG) ' <<< "$st" && return 1
  prim=$(awk '$2=="VALIDSIG"{print $NF}' <<< "$st")
  [[ -n $prim ]] && grep -qx "$prim" "$W/trusted"
}

mkdir "$W/x"
tar --force-local -xf "$F" -C "$W/x"
cd "$W/x"
for f in manifest notes.ko.txt SHA256SUMS SHA256SUMS.sig; do [[ -f $f ]] || die "$f is missing"; done
good_sig SHA256SUMS.sig SHA256SUMS || die "SHA256SUMS is not signed by the key in $(basename "$PUB")"
sha256sum --strict --quiet -c SHA256SUMS || die "checksums do not match"
[[ $(awk '{sub(/^\*/,"",$2); print $2}' SHA256SUMS | LC_ALL=C sort) == "$(find . -type f ! -name 'SHA256SUMS*' | sed 's|^\./||' | LC_ALL=C sort)" ]] \
  || die "SHA256SUMS does not list exactly the files in the update"
n=0
for p in packages/*.pkg.tar.zst; do
  [[ -f $p.sig ]] || die "$p has no signature"
  good_sig "$p.sig" "$p" || die "bad signature on $p"
  n=$((n + 1))
done
(( n > 0 )) || die "no packages"
ver=$(sed -n 's/^version=//p' manifest | head -n1)
ls packages/sufun-base-"$ver"-*.pkg.tar.zst >/dev/null 2>&1 || die "no sufun-base package for version $ver"
ls packages/sufun-keyring-"$ver"-*.pkg.tar.zst >/dev/null 2>&1 || die "no sufun-keyring package for version $ver"
[[ -z $WANT || $ver == "$WANT" ]] || die "version is $ver, expected $WANT"
echo "OK: $(basename "$F") version $ver, $n signed packages, signed by $(head -n1 "$W/trusted")"
