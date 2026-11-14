#!/usr/bin/env bash
# Static security checks of the repository (docs/security-audit.md). Runs first in
# every build (job "security-lint"); no secrets, no network needed except one
# optional lookup at addons.mozilla.org.
#   bash scripts/ci/security-lint.sh
# Each rule is one regression test for a finding of the audit.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
bad=0
ok()   { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; bad=1; }
rule() { if "${@:2}" >/dev/null 2>&1; then ok "$1"; else fail "$1"; fi; }
WF=.github/workflows

echo "== GitHub workflows"
# G-1: nothing runs for pull requests / forks, so they can never reach secrets
rule "no pull_request / pull_request_target trigger"   bash -c "! grep -rnE '^\s*pull_request(_target)?\s*:|\[.*pull_request.*\]' $WF"
# G-2: actions pinned to a full commit id (a tag like @v5 can be moved by its owner)
rule "every action pinned to a 40-character commit id" bash -c "! grep -rhE '^\s*(- )?uses:' $WF | grep -vE 'uses: \./' | grep -vE '@[0-9a-f]{40}(\s|$)'"
# G-3: no text from outside (titles, branch names, comments) inside commands
rule "no untrusted \${{ github.event/head_ref }} text"  bash -c "! grep -rnE '\\$\{\{[^}]*(github\.event\.|github\.head_ref|github\.actor)' $WF"
rule "job token is read-only by default"               bash -c "for f in $WF/*.yml; do grep -A1 '^permissions:' \"\$f\" | grep -q '^  contents: read' || exit 1; done"
rule "only the release job may write (contents: write once)" bash -c "[[ \$(cat $WF/*.yml | grep -c 'contents: write') == 1 ]] && grep -q 'contents: write' $WF/release.yml"
rule "secrets are used only in release.yml"            bash -c "! grep -lE '\\$\{\{\s*secrets\.' $WF/*.yml | grep -v release.yml"
rule "release job waits in the 'release' environment"  bash -c "grep -qE '^\s+environment: release' $WF/release.yml"
rule "release needs the build and tests first"         bash -c "grep -qE '^\s+needs: build-test' $WF/release.yml"
rule "checkout never keeps the job token"              bash -c "[[ \$(cat $WF/*.yml | grep -c 'actions/checkout@') == \$(cat $WF/*.yml | grep -c 'persist-credentials: false') ]]"
# G-4: the key passphrase is never a command line argument
rule "signing passphrase only through a pipe"          bash -c "! grep -rnE -- '--passphrase \"?\\$' $WF scripts/make-sufun-update.sh"
rule "release refuses a secret that holds the primary key" grep -q 'contains the PRIMARY key' $WF/release.yml

echo "== signing keys"
rule "no private key in the repository"                bash -c "! git grep -lI -e 'BEGIN PGP PRIVATE KEY' -e 'BEGIN OPENSSH PRIVATE KEY' -e 'BEGIN RSA PRIVATE KEY' -- . ':!scripts/ci/security-lint.sh'"
rule "no key backup files tracked"                     bash -c "! git ls-files | grep -iE 'secret|\.rev$|\.gpg$|\.kbx$|\.key$|subkey'"
rule ".gitignore still blocks key files"               bash -c "grep -qx 'keys/\*' .gitignore && grep -qx '\*SECRET\*' .gitignore && grep -qx '\*.gpg' .gitignore"

echo "== CI test mode can never start on a real computer"
# T-1: every program that looks at the kernel option sufun.test also needs the
# computer to be a QEMU virtual machine (read from the firmware, not changeable
# by a user). The kernel command line itself can't be changed by a normal user.
for f in $(git grep -lE 'sufun\\?\.test' -- sufun-base profile | grep -v '\.service$'); do
  rule "test mode in $f also needs a QEMU VM" bash -c "grep -q 'sys_vendor' '$f' && grep -q 'QEMU' '$f'"
done
rule "selftest stops at once outside QEMU"             bash -c "sed -n '1,25p' profile/airootfs/usr/local/bin/sufun-selftest | grep -q 'sys_vendor.*QEMU.*|| exit 0'"
rule "selftest + its service exist only on the live ISO" bash -c "! git ls-files sufun-base | grep -i selftest"
rule "installer copies the selftest only in test mode" bash -c "grep -B1 'install -Dm755 /usr/local/bin/sufun-selftest' profile/airootfs/usr/local/bin/sufun-install | grep -q 'if (( AUTO )); then'"
rule "installer test mode: env + kernel option + QEMU" bash -c "grep -A3 'SUFUN_AUTO:-0} == 1' profile/airootfs/usr/local/bin/sufun-install | grep -q 'sys_vendor'"
rule "test kernel option only added by a test install" bash -c "[[ \$(grep -c 'sufun.test=installed' profile/airootfs/usr/local/bin/sufun-install) == 1 ]] && grep 'sufun.test=installed' profile/airootfs/usr/local/bin/sufun-install | grep -q '^(( AUTO ))'"

echo "== accounts, sudo, polkit"
rule "password-less sudo only for the live user"       bash -c "[[ \$(git grep -l NOPASSWD -- sufun-base profile | grep -v sufun-selftest | tr '\n' ' ') == 'profile/airootfs/etc/sudoers.d/10-sufun-live ' ]]"
rule "auto-login only in the live ISO"                 bash -c "! git grep -liE '^\[Autologin\]' -- sufun-base"
rule "installed user must type the password for sudo"  grep -q "echo '%wheel ALL=(ALL:ALL) ALL'" profile/airootfs/usr/local/bin/sufun-install
rule "installer locks the root account"                grep -q 'passwd -l root' profile/airootfs/usr/local/bin/sufun-install
rule "user is not added to the 'input' group (I-1)"    bash -c "! grep -rnE 'useradd.*-G[^\"]*input' profile sufun-base"
rule "polkit actions always ask for the admin password" bash -c "! grep -hE '<allow_(any|inactive|active)>' sufun-base/rootfs/usr/share/polkit-1/actions/*.policy | grep -v '>auth_admin<'"
rule "the only polkit rule allows one unit, one verb"  bash -c "f=sufun-base/rootfs/usr/share/polkit-1/rules.d/50-sufun-typecover.rules; [[ \$(ls sufun-base/rootfs/usr/share/polkit-1/rules.d | wc -l) == 1 ]] && grep -q 'sufun-typecover-rebind.service' \$f && grep -q '\"start\"' \$f && grep -q 'subject.active && subject.local' \$f && [[ \$(grep -c 'polkit.Result.YES' \$f) == 1 ]]"
rule "no setuid bits set by our packages"              bash -c "! grep -rnE 'chmod [0-7]*[4267][0-7]{3}\b|chmod [ug]\+s' sufun-base/PKGBUILD sufun-keyring/PKGBUILD packages/pkgbuilds/sufun-*/PKGBUILD build.sh"

echo "== system hardening kept"
rule "CPU mitigations are never switched off"          bash -c "! grep -rn 'mitigations=off' build.sh profile sufun-base scripts/windows packages --include='*' | grep -v 'grep -qw'"
rule "firewall: installer sets deny incoming"          grep -q 'DEFAULT_INPUT_POLICY="DROP"' profile/airootfs/usr/local/bin/sufun-install
rule "firewall is on in the live system too (N-1)"     bash -c "grep -q 'enable ufw.service' build.sh && grep -q 'ENABLED=yes' profile/airootfs/etc/systemd/system/ufw.service.d/10-sufun-live.conf"
rule "no SSH server"                                   bash -c "grep -qE 'sshd\.service.*-delete' build.sh && ! grep -rnE '^openssh\s*$' packages/"
rule "boot menu: options can't be edited"              bash -c "grep -q '^editor no' profile/airootfs/usr/local/bin/sufun-install && grep -q \"'editor no'\" scripts/windows/sufun-sd-setup.ps1"
rule "screen locks after idle and on resume"           bash -c "grep -qx 'Autolock=true' sufun-base/rootfs/etc/xdg/kscreenlockerrc && grep -qx 'LockOnResume=true' sufun-base/rootfs/etc/xdg/kscreenlockerrc"
rule "update tool: private copy, no remote tar names"  bash -c "grep -q -- '--force-local' sufun-base/rootfs/usr/bin/sufun-update && grep -q 'cp --no-preserve=all -- \"\$FILE\" \"\$SRC\"' sufun-base/rootfs/usr/bin/sufun-update && ! grep -nE 'tar .*\"\\\$FILE\"' sufun-base/rootfs/usr/bin/sufun-update"
rule "linux-surface key pinned by full fingerprint"    bash -c "grep -qE '^SURFACE_KEY=[0-9A-F]{40}\b' build.sh && grep -qE '^SURFACE_KEY=[0-9A-F]{40}\b' profile/airootfs/usr/local/bin/sufun-install"
rule "every pinned source has a real checksum"         bash -c "! grep -n \"SKIP\" packages/pkgbuilds/*/PKGBUILD | grep -v '^[^:]*:[0-9]*:#'"
for f in sufun-base/rootfs/usr/bin/sufun-update sufun-base/rootfs/usr/bin/sufun-update-gui sufun-base/rootfs/usr/bin/sufun-windows-restore \
         sufun-base/rootfs/usr/lib/sufun/* profile/airootfs/usr/local/bin/* build.sh build-local-repo.sh scripts/*.sh scripts/ci/*.sh; do
  case $(head -c 2 "$f") in '#!') head -n1 "$f" | grep -q 'sh' && { bash -n "$f" 2>/dev/null || fail "shell syntax: $f"; } ;; esac
done
ok "shell syntax of every script"

echo "== Firefox policy and the bundled uBlock Origin"
python3 - <<'PY' || bad=1
import json, re, sys, urllib.request
bad = 0
def ok(m): print("  ok   ", m)
def fail(m):
    global bad; bad = 1; print("  FAIL ", m)
pol = json.load(open("sufun-base/rootfs/etc/firefox/policies/policies.json", encoding="utf-8"))["policies"]
ext = pol.get("ExtensionSettings", {})
ub = ext.get("uBlock0@raymondhill.net", {})
(ok if list(ext) == ["uBlock0@raymondhill.net"] else fail)("only uBlock Origin is installed by policy, no other extension, no '*' rule")
(ok if ub.get("installation_mode") == "normal_installed" else fail)("uBlock is 'normal_installed' (the user can switch it off), not forced/locked")
(ok if ub.get("install_url") == "file:///usr/share/sufun/firefox/uBlock0@raymondhill.net.xpi" else fail)("uBlock comes from the bundled package file")
weak = ("security.", "fission.", "xpinstall.", "dom.security", "browser.safebrowsing", "extensions.blocklist",
        "network.stricttransportsecurity", "privacy.resistFingerprinting", "media.peerconnection.ice", "extensions.webextensions.remote")
prefs = pol.get("Preferences", {})
hit = [k for k in prefs if k.startswith(weak)]
(ok if not hit else fail)("no security-related Firefox preference is changed %s" % hit)
(ok if all(v.get("Status") == "default" for v in prefs.values()) else fail)("all preferences are defaults the user can change (none locked)")
forbidden = {"Certificates", "Proxy", "DisableSafeMode", "DisableBuiltinPDFViewer", "ExtensionUpdate", "DisableSecurityBypass",
             "SSLVersionMin", "SSLVersionMax", "DisabledCiphers", "EnableTrackingProtection", "PasswordManagerEnabled", "InstallAddonsPermission"}
hit = sorted(set(pol) & forbidden)
(ok if not hit else fail)("no policy that changes certificates, TLS, proxy or add-on signing %s" % hit)

pk = open("packages/pkgbuilds/sufun-ublock-origin/PKGBUILD", encoding="utf-8").read()
ver = re.search(r"^pkgver=(\S+)", pk, re.M).group(1)
fid = re.search(r"^_fileid=(\d+)", pk, re.M).group(1)
sha = re.search(r"^sha256sums=\('([0-9a-f]{64})'\)", pk, re.M).group(1)
(ok if "addons.mozilla.org/firefox/downloads/file/$_fileid/" in pk else fail)("uBlock source is addons.mozilla.org")
# The checksum in our package must be the one Mozilla publishes for that file.
try:
    req = urllib.request.Request("https://addons.mozilla.org/api/v5/addons/addon/ublock-origin/versions/?page_size=50",
                                 headers={"User-Agent": "ci-security-lint"})
    res = json.load(urllib.request.urlopen(req, timeout=30))["results"]
    m = [v for v in res if str(v["file"]["id"]) == fid]
    if not m:
        print("  note  uBlock %s (file %s) is not among Mozilla's newest 50 versions: update the pinned copy" % (ver, fid))
    else:
        f = m[0]["file"]
        good = m[0]["version"] == ver and f["hash"] == "sha256:" + sha and f["status"] == "public"
        (ok if good else fail)("uBlock %s: our checksum = the checksum Mozilla publishes for the signed file (%s)" % (ver, f["hash"][:23] + "..."))
        newest = res[0]["version"]
        if newest != ver:
            print("  note  a newer uBlock Origin exists (%s); Firefox updates it by itself after the first start" % newest)
except Exception as e:
    print("  note  could not ask addons.mozilla.org (%s): checksum comparison skipped this time" % e)
sys.exit(bad)
PY

echo
if (( bad )); then echo "SECURITY LINT FAILED"; exit 1; fi
echo "security lint: all rules passed"
