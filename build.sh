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

SURFACE_KEY=56C464BAAC421453
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
# Note: the live USB keeps archiso's own initramfs hooks (archiso.conf), without
# the Plymouth boot screen: Plymouth is not reliable with archiso's hooks.
# The installed system gets the SUFUN boot screen (sufun-base, 10-sufun.conf).

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
file_permissions+=(
  ["/usr/local/bin/sufun-install"]="0:0:755"
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
# The Windows setup script copies EFI/BOOT/BOOTx64.EFI as the boot menu and
# writes systemd-boot entries for it: it must be systemd-boot.
grep -aq 'systemd-boot' "$ISODIR/EFI/BOOT/BOOTx64.EFI" \
  || die "EFI/BOOT/BOOTx64.EFI on the ISO is not systemd-boot (sufun-sd-setup.ps1 needs it)"

log "Done:"
ls -lh "$OUT"/*.iso
