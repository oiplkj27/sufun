#!/usr/bin/env bash
# Automatic boot + install test (idea from KDE Linux: every image must boot to the desktop).
#   bash scripts/ci/qemu-test.sh <iso> <expected-version> <output-dir>
#
#   Test 1: live USB boots to the Plasma desktop, checks the Windows 11-style layout,
#           prints RAM numbers
#   Test 2: the installer installs SUFUN in "내부 저장장치에 설치" mode to an empty
#           64 GB virtual disk (test mode). An empty microSD card is attached too:
#           the installer must pick the internal disk by itself, never the card.
#   Test 3: the installed system boots, shows the login screen, checks itself, then
#           logs in (test disk only) and checks the Korean desktop
#           (SUFUN boot entry + Plymouth, version, zram, earlyoom, firewall, fstab).
#           Then the Windows restore test, with a DUMMY Windows ISO (same layout,
#           no Microsoft files, see make-dummy-windows-iso.sh): WININSTALL partition
#           (SUFUN shrunk), install.wim split, "Windows Setup" entry last, BootNext.
#   Test 4: the firmware starts the "Windows Setup" entry (BootNext) from the
#           WININSTALL partition (the dummy ISO's boot file + a test kernel option)
#   Test 5: the installed system again: sufun-windows-restore --remove puts back
#           the partition sizes and removes the entry
# Security audit tests (docs/security-audit.md), in tests 1 and 3:
#   - the host scans the VM's ports over a private scan network (portscan.sh)
#   - test 3 gets a small "USB stick" with a .sufun update made by the real release
#     tools and a throwaway key (make-security-media.sh, needs the packages tar as
#     4th argument); the VM tries tampered/unsigned/old/wrong-key updates.
# Success is read from the serial console ("SUFUN-TEST: ..." lines written by
# sufun-selftest), not from fixed waiting times. Screenshots are saved every
# 10 seconds for the first 3 minutes, then every minute (QEMU monitor
# "screendump"), plus the serial logs: upload <output-dir>. The installed system
# also gets one about every 2 seconds for its first 20 seconds (boot splash).
#
# Needs: qemu-system-x86_64, qemu-img, OVMF (UEFI firmware), xorriso, python3, wimtools.
# Uses KVM when /dev/kvm is usable, otherwise slow software emulation with longer timeouts.
set -uo pipefail

ISO="$(realpath "${1:?iso}")"; WANT="${2:?version}"; OUT="${3:?output dir}"
PKGTAR="${4:-}"; [[ -n $PKGTAR ]] && PKGTAR="$(realpath "$PKGTAR")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT"; OUT="$(realpath "$OUT")"
cd "$OUT" || exit 1
# shellcheck source=qemu-common.sh
source "$HERE/qemu-common.sh"
cp "$VARS_SRC" vars.fd

# Kernel + initramfs from the ISO: test 1 and 2 add kernel options
# (serial console, sufun.test=...) without touching the boot menu.
xorriso -osirrox on -indev "$ISO" \
  -extract /arch/boot/x86_64/vmlinuz-linux-surface vmlinuz \
  -extract /arch/boot/x86_64/initramfs-linux-surface.img initrd.img \
  -extract /arch/boot/intel-ucode.img ucode.img >/dev/null 2>&1 || true
[[ -s vmlinuz && -s initrd.img ]] || { echo "kernel not found in ISO" >&2; exit 1; }
LABEL=$(blkid -s LABEL -o value "$ISO" 2>/dev/null || xorriso -indev "$ISO" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p')
LIVEOPTS="archisobasedir=arch archisolabel=$LABEL cow_spacesize=512M console=ttyS0,115200 console=tty0"

qemu-img create -f qcow2 disk.qcow2 64G >/dev/null
# Empty 1 GiB microSD card (QEMU SD cards must be a power of 2 in size)
truncate -s 1G sdblank.img
SDCARD=(-device sdhci-pci,sd-spec-version=3 -drive id=sdimg,if=none,format=raw,file=sdblank.img -device sd-card,drive=sdimg)
# Dummy Windows 11 ISO for the restore test (no Microsoft files)
bash "$HERE/make-dummy-windows-iso.sh" "$ISO" "$LABEL" winiso.iso || { echo "could not make the dummy Windows ISO" >&2; exit 1; }

fail=0
# --- security tests: scan network + update test media. In GitHub Actions they
#     must work (no silent skip); on a developer machine without sudo/nmap they
#     are left out. ---
SCANNIC=() SECUSB=()
if command -v nmap >/dev/null && sudo -n true 2>/dev/null && bash "$HERE/portscan.sh" --setup; then
  SCANNIC=(-netdev tap,id=n1,ifname=sufuntap,script=no,downscript=no -device virtio-net-pci,netdev=n1,mac=52:54:00:77:00:02)
  trap 'bash "$HERE/portscan.sh" --teardown' EXIT
elif [[ ${GITHUB_ACTIONS:-} == true ]]; then
  echo "the port scan network could not be set up"; fail=1
fi
if [[ -n $PKGTAR ]] && bash "$HERE/make-security-media.sh" "$PKGTAR" "$OUT/sec.iso"; then
  # as a USB stick: never an "internal disk" for the installer or the restore tool
  SECUSB=(-device qemu-xhci,id=secxhci -drive if=none,id=secmedia,format=raw,readonly=on,file=sec.iso -device usb-storage,bus=secxhci.0,drive=secmedia)
elif [[ ${GITHUB_ACTIONS:-} == true ]]; then
  echo "the update test media could not be made"; fail=1
fi

run_vm 1-live 2400 'SUFUN-TEST: LIVE-DESKTOP-OK' 'SUFUN-TEST: LIVE-DESKTOP-TIMEOUT' \
  -cdrom "$ISO" -kernel vmlinuz -initrd initrd.img -append "$LIVEOPTS sufun.test=live" "${SCANNIC[@]}" || fail=1
check_serial 1-live || fail=1
if (( ${#SCANNIC[@]} )); then
  grep -q 'REACHED=1 OPEN_TCP=0 OPEN_UDP=0 ' 1-live-portscan.txt 2>/dev/null || { echo "live system: port scan found open ports or did not run"; fail=1; }
fi

run_vm 2-install 3600 'SUFUN-TEST: INSTALL-DONE' 'SUFUN-TEST: INSTALL-FAILED' \
  -cdrom "$ISO" -drive file=disk.qcow2,if=virtio,format=qcow2 "${SDCARD[@]}" \
  -kernel vmlinuz -initrd initrd.img -append "$LIVEOPTS sufun.test=install" || fail=1
if ! grep -qE 'SUFUN-TEST: TARGET /dev/vda[[:space:]]*$' 2-install-serial.log; then
  echo "the installer did not pick the internal disk /dev/vda"; fail=1
fi

if (( ! fail )); then
  # Boot from the virtual disk only, like a real start: firmware -> systemd-boot -> SUFUN.
  # Extra screenshots in the first 20 s catch the SUFUN boot splash (Plymouth),
  # and after LOGIN-START the SUFUN login splash (ksplash).
  FAST_SHOTS=20 run_vm 3-installed 2400 'SUFUN-TEST: INSTALLED-DONE' 'SUFUN-TEST: NEVER' \
    -drive file=disk.qcow2,if=virtio,format=qcow2 \
    -drive file=winiso.iso,media=cdrom,readonly=on "${SCANNIC[@]}" "${SECUSB[@]}" || fail=1
  check_serial 3-installed "$WANT" || fail=1
  if (( ${#SCANNIC[@]} )); then
    grep -q 'REACHED=1 OPEN_TCP=0 OPEN_UDP=0 ' 3-installed-portscan.txt 2>/dev/null || { echo "installed system: port scan found open ports or did not run"; fail=1; }
  fi
  if (( ${#SECUSB[@]} )); then
    grep -q 'SUFUN-TEST: PASS update-newer-signed-passes' 3-installed-serial.log || { echo "update attack tests did not run"; fail=1; }
  fi
  grep -q 'SUFUN-TEST: RESTORE-PREPARED' 3-installed-serial.log || { echo "Windows restore: prepare did not finish"; fail=1; }
fi

if (( ! fail )); then
  # The firmware's BootNext (set by sufun-windows-restore) must start the
  # "Windows Setup" entry. The dummy boot file there starts the live kernel with
  # sufun.test=winsetup; the live ISO is attached for its root file system.
  run_vm 4-winsetup 600 'SUFUN-TEST: WINSETUP-BOOT-OK' 'SUFUN-TEST: BOOTED' \
    -drive file=disk.qcow2,if=virtio,format=qcow2 -cdrom "$ISO" || fail=1
  # Then a normal start again: the installed system undoes the restore preparation.
  run_vm 5-restore-cleanup 900 'SUFUN-TEST: RESTORE-CLEANUP-DONE' 'SUFUN-TEST: BOOTED installed' \
    -drive file=disk.qcow2,if=virtio,format=qcow2 || fail=1
  check_serial 5-restore-cleanup || fail=1
fi

rm -f disk.qcow2 sdblank.img winiso.iso sec.iso vmlinuz initrd.img ucode.img ./*.sock
(( fail )) && { echo "TESTS FAILED"; exit 1; }
echo "ALL TESTS PASSED"
