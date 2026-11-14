#!/usr/bin/env bash
# Build the SUFUN live/installer ISO (SUFUN = Arch Linux made for the Surface Go 3).
#
# Requirements: Arch Linux (bare metal, WSL "archlinux", or a privileged
# archlinux container), run as root. Output: ./out/sufun-<version>-x86_64.iso
# and ./out/packages/ (our own packages, used by the release workflow).
#
# How it works: we start from Arch's official "releng" archiso profile
# (which already has working BIOS/UEFI boot configs), then
#   - build our own packages (sufun-base, keyring, fonts, theme...) into a local repo
#   - swap the stock kernel for linux-surface and add its package repo
#   - install "sufun-base", which brings all SUFUN settings and the desktop
#   - add the live-only files (profile/airootfs: auto-login, installer)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HERE/work}"
OUT="${OUT:-$HERE/out}"
PROFILE="$WORK/profile"
RELENG=/usr/share/archiso/configs/releng
LOCALREPO=/var/tmp/sufun-repo         # path without spaces (pacman file:// URLs)
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION")"

# linux-surface package signing key: the FULL fingerprint (a short id could be imitated)
SURFACE_KEY=87DEFA4AB94A99A4C8C3112556C464BAAC421453
SURFACE_KEY_URL=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
SURFACE_REPO=$'\n[linux-surface]\nServer = https://pkg.surfacelinux.com/arch/\n'

log() { printf '\e[1;36m==> %s\e[0m\n' "$*"; }
die() { printf '\e[1;31m==> ERROR: %s\e[0m\n' "$*" >&2; exit 1; }
strip_list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$@"; }

[[ $EUID -eq 0 ]] || { echo "build.sh must run as root" >&2; exit 1; }
# mkinitcpio: lsinitcpio, to check the live initramfs at the end
pacman -Sy --needed --noconfirm archiso curl mkinitcpio

rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"

log "Trusting the linux-surface signing key on the build host"
curl -fsSL "$SURFACE_KEY_URL" -o "$WORK/surface.asc"
pacman-key --init >/dev/null 2>&1 || true
# The downloaded file must contain exactly that one key, nothing else
got=$(gpg --batch --with-colons --show-keys "$WORK/surface.asc" 2>/dev/null | awk -F: '$1 == "pub" {n++; w=1} $1 == "fpr" && w {f = $10; w=0} END {print f " keys=" n}')
[[ $got == "$SURFACE_KEY keys=1" ]] || die "the downloaded linux-surface key is not the expected one ($got)"
pacman-key --add "$WORK/surface.asc"
pacman-key --lsign-key "$SURFACE_KEY"

log "Building our own packages into a local repo (no AUR downloads)"
bash "$HERE/build-local-repo.sh" "$LOCALREPO"
rm -rf "$OUT/packages" && mkdir -p "$OUT/packages"
cp "$LOCALREPO"/*.pkg.tar.zst "$OUT/packages/"

log "Copying releng profile and applying our live-only overlay"
cp -a "$RELENG" "$PROFILE"
cp -a "$HERE/profile/airootfs/." "$PROFILE/airootfs/"
SHARE="$PROFILE/airootfs/usr/share/sufun-iso"      # used by the installer
install -Dm644 "$WORK/surface.asc" "$SHARE/surface.asc"
install -Dm644 -t "$SHARE" "$HERE/packages/install.txt" "$HERE/packages/desktop.txt" "$HERE/VERSION"
cp -a "$LOCALREPO" "$SHARE/repo"

# pacman.conf used to build the ISO: stock + [multilib] (Steam) + linux-surface + our repo
sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' "$PROFILE/pacman.conf"
grep -q '^\[multilib\]' "$PROFILE/pacman.conf" || { echo "could not enable [multilib]" >&2; exit 1; }
printf '%s' "$SURFACE_REPO" >> "$PROFILE/pacman.conf"
printf '\n[sufun-local]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$LOCALREPO" >> "$PROFILE/pacman.conf"

log "Building package list"
# Drop the stock kernel and anything that hard-depends on it.
sed -i -E '/^(linux|broadcom-wl)$/d' "$PROFILE/packages.x86_64"
# sufun-base depends on every desktop package; listing desktop.txt too makes the
# explicit driver/provider choices (vulkan-intel, lib32-mesa, ...) count here as well.
# fio: live ISO only, for the installer's microSD speed test (4K random writes).
{ echo sufun-base; echo fio; strip_list "$HERE/packages/desktop.txt"; } >> "$PROFILE/packages.x86_64"
sort -u -o "$PROFILE/packages.x86_64" "$PROFILE/packages.x86_64"

log "Pointing bootloaders and mkinitcpio at linux-surface, naming the menus SUFUN"
grep -rlE 'vmlinuz-linux|initramfs-linux' "$PROFILE"/efiboot "$PROFILE"/grub "$PROFILE"/syslinux 2>/dev/null \
  | xargs -r sed -i -e 's/vmlinuz-linux/vmlinuz-linux-surface/g' -e 's/initramfs-linux/initramfs-linux-surface/g'
# Menu titles: "Arch Linux install medium ..." -> "SUFUN live USB / installer ..."
grep -rl 'Arch Linux' "$PROFILE"/efiboot "$PROFILE"/grub "$PROFILE"/syslinux 2>/dev/null \
  | xargs -r sed -i -e 's/Arch Linux install medium/SUFUN live USB \/ installer/g' -e 's/Arch Linux/SUFUN/g'
# Older archiso shipped its own airootfs/etc/mkinitcpio.d/linux.preset; archiso 92+
# does not: there the linux-surface package's own preset is used (it already
# names vmlinuz-linux-surface / initramfs-linux-surface.img) and archiso's hooks
# come from the drop-in etc/mkinitcpio.conf.d/archiso.conf.
PRESETS="$PROFILE/airootfs/etc/mkinitcpio.d"
if [[ -f $PRESETS/linux.preset ]]; then
  mv "$PRESETS/linux.preset" "$PRESETS/linux-surface.preset"
  sed -i -e 's/vmlinuz-linux/vmlinuz-linux-surface/g' -e 's/initramfs-linux/initramfs-linux-surface/g' \
    "$PRESETS/linux-surface.preset"
fi
[[ -f $PROFILE/airootfs/etc/mkinitcpio.conf.d/archiso.conf ]] \
  || die "releng profile has no mkinitcpio.conf.d/archiso.conf: archiso changed, check build.sh"
# The live system keeps archiso's own initramfs hooks (archiso.conf); our
# airootfs/etc/mkinitcpio.conf.d/zz-sufun-sd.conf adds the SD card drivers and
# "plymouth" after "kms" (SUFUN boot screen; the theme is set by sufun-base).

log "Boot menu: SUFUN boot screen by default, plus a text mode entry"
# Every normal live entry gets "quiet splash" (Plymouth logo, Esc shows the text);
# a copy without it is the "text mode" entry for troubleshooting. (The microSD
# boot stage made on Windows gets the same two entries from sufun-sd-setup.ps1.)
n=0
for e in "$PROFILE"/efiboot/loader/entries/*.conf; do
  [[ -f $e ]] || continue
  grep -q '^options.*archisobasedir' "$e" || continue
  grep -qiE 'speech|accessib' "$e" && continue        # screen reader entry: keep text
  t="$PROFILE/efiboot/loader/entries/zz-sufun-text-$(basename "$e")"
  sed -e '/^title/s/$/ (text mode)/' -e '/^sort-key/s/$/9/' "$e" > "$t"
  # live writes (home, logs) go to RAM ("cowspace"); 512 MiB instead of 256 MiB
  # usbcore.quirks=045e:09b5:g: Type Cover touchpad starts reliably (delayed init)
  sed -i '/^options/s/$/ cow_spacesize=512M usbcore.quirks=045e:09b5:g/' "$e" "$t"
  sed -i '/^options/s/$/ quiet splash loglevel=3/' "$e"
  n=$((n + 1))
done
(( n > 0 )) || die "no archiso boot entries found in efiboot/loader/entries (archiso changed?)"

log "Configuring services"
SD="$PROFILE/airootfs/etc/systemd/system"
# NetworkManager replaces iwd/networkd; no SSH server on a desktop.
find "$SD" -type l \( -name 'iwd.service' -o -name 'systemd-networkd*' -o -name 'sshd.service' \) -delete
enable() { # enable <unit> <target.wants dir>
  mkdir -p "$SD/$2"
  ln -sf "/usr/lib/systemd/system/$1" "$SD/$2/$1"
}
enable NetworkManager.service        multi-user.target.wants
enable power-profiles-daemon.service multi-user.target.wants
enable thermald.service              multi-user.target.wants
enable earlyoom.service              multi-user.target.wants
enable ananicy-cpp.service           multi-user.target.wants
# Firewall in the live system too (see etc/systemd/system/ufw.service.d/10-sufun-live.conf)
enable ufw.service                   multi-user.target.wants
# Bluetooth: NOT started at boot. This alias lets it start on demand when the
# Bluetooth applet asks for it over D-Bus.
ln -sf /usr/lib/systemd/system/bluetooth.service "$SD/dbus-org.bluez.service"
mkdir -p "$SD/multi-user.target.wants"
ln -sf /etc/systemd/system/sufun-live-user.service "$SD/multi-user.target.wants/sufun-live-user.service"
ln -sf /etc/systemd/system/sufun-selftest.service  "$SD/multi-user.target.wants/sufun-selftest.service"
ln -sf /usr/lib/systemd/system/sddm.service     "$SD/display-manager.service"
ln -sf /usr/lib/systemd/system/graphical.target "$SD/default.target"

log "Branding and file permissions"
cat >> "$PROFILE/profiledef.sh" <<EOF

# --- SUFUN overrides ---
iso_name="sufun"
iso_version="$VERSION"
iso_label="SUFUN_\$(date --date="@\${SOURCE_DATE_EPOCH:-\$(date +%s)}" +%Y%m)"
iso_publisher="SUFUN (for the Microsoft Surface Go 3)"
iso_application="SUFUN Live/Installer"
install_dir="arch"
# zstd with 256 KiB blocks instead of xz with 1 MiB blocks: a little bigger, but
# every small file read (start menu, search, power menu) decompresses ~10x less
# data, much faster on the Pentium 6500Y and a slow microSD card (~23 MB/s).
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '256K')
file_permissions+=(
  ["/usr/local/bin/sufun-install"]="0:0:755"
  ["/usr/local/bin/sufun-install-gui"]="0:0:755"
  ["/usr/local/bin/sufun-selftest"]="0:0:755"
  ["/etc/sudoers.d/10-sufun-live"]="0:0:440"
)
EOF

log "Running mkarchiso (this takes a while)"
mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE"

log "Checking the live ISO for microSD boot (Surface Go 3 card reader)"
# The live system must start from a microSD card (boot stage on the internal disk,
# see scripts/windows/sufun-sd-setup.ps1): the SD drivers and file systems from
# airootfs/etc/mkinitcpio.conf.d/zz-sufun-sd.conf must really be in the initramfs.
ISODIR="$WORK/build/iso"
INITRD="$ISODIR/arch/boot/x86_64/initramfs-linux-surface.img"
[[ -f $INITRD ]] || die "live initramfs not found: $INITRD"
INITRD_FILES=$(lsinitcpio "$INITRD") || die "lsinitcpio failed on $INITRD"
# Module file names use "_" or "-" (sdhci-pci.ko, nls_iso8859-1.ko): match both.
# A module built into the kernel itself (modules.builtin) needs no file.
BUILTIN=$(cat "$WORK"/build/x86_64/airootfs/usr/lib/modules/*/modules.builtin 2>/dev/null || true)
for m in rtsx_pci rtsx_pci_sdmmc mmc_block mmc_core sdhci sdhci_pci vfat exfat nls_cp437 nls_iso8859_1; do
  grep -qE "/${m//_/[-_]}\.ko(\.(zst|xz|gz))?$" <<< "$INITRD_FILES" \
    || grep -qE "/${m//_/[-_]}\.ko$" <<< "$BUILTIN" \
    || die "module $m is missing from the live initramfs (microSD boot would fail)"
done
# SUFUN boot screen in the live initramfs (zz-sufun-sd.conf + sufun-base's theme)
grep -q 'plymouth/themes/sufun/logo.png' <<< "$INITRD_FILES"   || die "the live initramfs has no SUFUN Plymouth theme (boot splash)"
# Languages offered by the first-start chooser must be generated (locale-archive)
ARCHIVE="$WORK/build/x86_64/airootfs/usr/lib/locale/locale-archive"
for l in $(awk -F'	' '!/^#/ && NF {print $1}' "$HERE/sufun-base/rootfs/usr/share/sufun/languages.tsv"); do
  l=${l%.UTF-8}
  grep -aq "${l}.utf8" "$ARCHIVE" || die "locale ${l}.UTF-8 was not generated in the live system"
done
# The live root image must fit a FAT32 card partition (one file < 4 GiB)
SFS="$ISODIR/arch/x86_64/airootfs.sfs"
(( $(stat -c %s "$SFS") < 4294967296 )) || die "airootfs.sfs is 4 GiB or larger (FAT32 limit)"
log "airootfs.sfs: $(du -h "$SFS" | cut -f1)"
# The Windows setup script copies EFI/BOOT/BOOTx64.EFI as the boot menu and
# writes systemd-boot entries for it: it must be systemd-boot.
grep -aq 'systemd-boot' "$ISODIR/EFI/BOOT/BOOTx64.EFI" \
  || die "EFI/BOOT/BOOTx64.EFI on the ISO is not systemd-boot (sufun-sd-setup.ps1 needs it)"

log "Done:"
ls -lh "$OUT"/*.iso
