#!/usr/bin/env bash
# SUFUN signing key helper. Run it yourself in a normal Git Bash / Linux terminal
# (it asks for passphrases, so do not run it through an AI assistant or a script).
#
# Key structure:
#   primary key  = "certify only". Lives ONLY in your offline backup (USB drive).
#                  It is needed to extend, replace or revoke the signing subkey.
#   signing subkey = signs releases. Expires after 2 years. A copy of it (without
#                  the primary key) is stored as a GitHub Actions secret.
#
# Every command works in a temporary GnuPG folder that is deleted at the end,
# so the private keys are never left in this computer's normal keyring.
#
#   bash scripts/sufun-key.sh create  <backup-folder>     make a new key (first time)
#   bash scripts/sufun-key.sh extend  <backup-folder>     add 2 more years to the subkey
#   bash scripts/sufun-key.sh rotate  <backup-folder>     revoke the subkey and make a new one (leak!)
#   bash scripts/sufun-key.sh info    <backup-folder>     show what is in the backup
#
# <backup-folder> must be OUTSIDE this repository, e.g. E:/SUFUN-KEY (your USB drive).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUB="$HERE/keys/sufun.asc"
cmd="${1:-}"; BK="${2:-}"
[[ -n $cmd && -n $BK ]] || { sed -n '2,20p' "$0"; exit 1; }

say()  { printf '\e[1;36m==> %s\e[0m\n' "$*"; }
die()  { printf '\e[1;31mError: %s\e[0m\n' "$*" >&2; exit 1; }

# Refuse a backup folder inside the repository (it could get committed).
mkdir -p "$BK"
BK="$(cd "$BK" && pwd)"
case "$BK/" in "$HERE"/*) die "the backup folder must be outside the repository ($HERE)";; esac

GNUPGHOME="$(mktemp -d)"; export GNUPGHOME
chmod 700 "$GNUPGHOME"
cleanup() { gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$GNUPGHOME"; }
trap cleanup EXIT
# Tests only: SUFUN_KEY_NOPASS=1 creates keys without a passphrase.
NOPASS=()
[[ ${SUFUN_KEY_NOPASS:-} == 1 ]] && NOPASS=(--batch --pinentry-mode loopback --passphrase '')

primary_fpr() { gpg --with-colons --list-secret-keys | awk -F: '$1=="sec"{w=1} $1=="fpr"&&w{print $10; exit}'; }
# Newest valid (not revoked/expired) signing subkey fingerprint
signing_sub() {
  gpg --with-colons --list-keys "$1" | awk -F: '
    $1=="sub" { ok = ($2!="r" && $2!="e" && $12 ~ /s/); next }
    $1=="fpr" && ok { f=$10; ok=0 } END { print f }'
}

export_all() {  # write public key to the repo, secrets to the backup
  local fpr="$1" sub
  sub="$(signing_sub "$fpr")"
  [[ -n $sub ]] || die "no valid signing subkey found"
  gpg --armor --export "$fpr" > "$PUB"
  gpg --armor --export-secret-keys "$fpr" > "$BK/sufun-primary-SECRET.asc"
  gpg --armor --export "$fpr" > "$BK/sufun-public.asc"
  # Only the subkey (primary is exported as a stub, so CI can sign but never certify)
  gpg --armor --export-secret-subkeys "${sub}!" > "$BK/sufun-signing-subkey-for-github.asc"
  cp -f "$GNUPGHOME"/openpgp-revocs.d/*.rev "$BK/" 2>/dev/null || true
  {
    echo "SUFUN signing key backup - $(date -u +%F)"
    echo "Primary key (certify only): $fpr"
    echo "Signing subkey:             $sub"
    gpg --list-keys --keyid-format long "$fpr"
  } > "$BK/README-KEY.txt"
  say "Public key written to keys/sufun.asc (commit this file)."
  say "Backup written to $BK"
  cat <<EOF

Next steps:
 1. Upload the SIGNING SUBKEY to GitHub (environment "release"):
      gh secret set SUFUN_SIGNING_KEY --env release < "$BK/sufun-signing-subkey-for-github.asc"
      gh secret set SUFUN_SIGNING_PASSPHRASE --env release      (type the key passphrase)
 2. Delete "$BK/sufun-signing-subkey-for-github.asc" after uploading, if you like.
 3. Keep the folder $BK on an offline USB drive. Never upload it to cloud storage.
 4. git add keys/sufun.asc && git commit -m "Update SUFUN public key"
EOF
}

import_backup() {
  [[ -f $BK/sufun-primary-SECRET.asc ]] || die "no sufun-primary-SECRET.asc in $BK"
  gpg --batch --import "$BK/sufun-primary-SECRET.asc"
  primary_fpr
}

case "$cmd" in
  create)
    [[ ! -e $BK/sufun-primary-SECRET.asc ]] || die "$BK already has a key. Use 'extend' or 'rotate'."
    read -rp "Name on the key [SUFUN Release Signing]: " name; name=${name:-SUFUN Release Signing}
    read -rp "E-mail on the key (optional, it becomes public): " mail
    uid="$name"; [[ -n $mail ]] && uid="$name <$mail>"
    say "Creating the primary key (certify only, no expiry). Choose a STRONG passphrase."
    gpg "${NOPASS[@]}" --quick-gen-key "$uid" ed25519 cert never
    fpr="$(primary_fpr)"
    say "Adding the signing subkey (expires in 2 years)"
    gpg "${NOPASS[@]}" --quick-add-key "$fpr" ed25519 sign 2y
    export_all "$fpr"
    ;;
  extend)
    fpr="$(import_backup)"; sub="$(signing_sub "$fpr")"
    [[ -n $sub ]] || die "no valid signing subkey to extend (expired or revoked: use 'rotate')"
    say "Extending subkey $sub by 2 years from today"
    gpg "${NOPASS[@]}" --quick-set-expire "$fpr" 2y "$sub"
    export_all "$fpr"
    echo "Also upload the new subkey file to GitHub (step 1), then release an update so users get the new expiry date."
    ;;
  rotate)
    fpr="$(import_backup)"; old="$(signing_sub "$fpr")"
    if [[ -n $old ]]; then
      say "Revoking the old signing subkey $old (reason: key compromised)"
      # Answers for gpg's interactive questions: select key, revoke, yes, reason 1, no text, ok
      printf 'key %s\nrevkey\ny\n1\n\ny\nsave\n' "$old" \
        | gpg "${NOPASS[@]}" --command-fd 0 --status-fd 2 --edit-key "$fpr" 2>/dev/null
    fi
    say "Adding a new signing subkey (2 years)"
    gpg "${NOPASS[@]}" --quick-add-key "$fpr" ed25519 sign 2y
    export_all "$fpr"
    echo "Old subkey is now revoked in keys/sufun.asc. Release an update soon: it ships the revocation to users."
    ;;
  info)
    fpr="$(import_backup)"
    gpg --list-keys --keyid-format long "$fpr"
    ;;
  *) die "unknown command $cmd" ;;
esac
