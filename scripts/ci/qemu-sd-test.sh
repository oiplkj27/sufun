#!/usr/bin/env bash
# microSD boot test: uses the two virtual disks that scripts/windows/sufun-sd-setup.ps1
# made on a real Windows runner (job "windows-sd-setup", case (a), boot stage in
# the EFI partition):
#   internal.vhdx  = the Surface's internal disk: EFI partition (with \EFI\SUFUN and
#                    \loader made by the script) + an NTFS "Windows" partition
#   card.vhdx      = the 32 GiB microSD card: 4 GB SUFUNLIVE partition + free space
#   bash scripts/ci/qemu-sd-test.sh <vhd-dir> <expected-version> <output-dir> [sufun.iso]
#
#   Test 6: SD live boot: firmware -> systemd-boot on the internal disk -> kernel ->
#           live system from the emulated SD card (sdhci-pci + sd-card): LIVE-DESKTOP-OK
#   Test 7: "SD카드에 설치 (윈도우 유지)" from that live system (into the card's free space)
#   Test 8: the installed system boots from the card (boot stage on the internal
#           disk) to the desktop and checks itself (kernel updates keep the boot stage in sync)
#   Afterwards: the internal disk's partition table and the "Windows" partition are
#   byte-for-byte unchanged.
#   Test 9: Windows restore REHEARSAL disk (rehearsal.vhdx, made on the Windows runner
#           by sufun-sd-setup.ps1 -RestoreRehearsal with the dummy Windows ISO): the
#           firmware starts \efi\boot\bootx64.efi from the FAT32 WININSTALL partition
#           that Windows made, and the firmware entry bytes the Windows script made
#           are exactly the bytes Linux's efibootmgr makes for that partition (the
#           later restore uses efibootmgr). Needs the SUFUN ISO (4th argument).
#
# Not testable here: the firmware entry "SUFUN (SD)" (bcdedit, Windows' NVRAM) and the
# Surface UEFI itself. The firmware entry is emulated by copying the boot menu to the
# EFI fallback path \EFI\BOOT\BOOTX64.EFI on the test disk.
#
# Needs: qemu-system-x86_64, qemu-img, OVMF, python3, mtools, gdisk, util-linux.
set -uo pipefail

VHD="$(realpath "${1:?vhd dir}")"; WANT="${2:?version}"; OUT="${3:?output dir}"
ISO="${4:-}"; [[ -n $ISO ]] && ISO="$(realpath "$ISO")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT"; OUT="$(realpath "$OUT")"
cd "$OUT" || exit 1
# shellcheck source=qemu-common.sh
source "$HERE/qemu-common.sh"
VARS="$OUT/sd-vars.fd"; cp "$VARS_SRC" "$VARS"

die() { echo "ERROR: $*" >&2; exit 1; }
export MTOOLS_SKIP_CHECK=1      # FAT made by Windows: mtools must not be picky about its geometry
qemu-img convert -O raw "$VHD/internal.vhdx" internal.img || die "internal.vhdx"
qemu-img convert -O raw "$VHD/card.vhdx" card.img || die "card.vhdx"
ls -ls internal.img card.img

# Partition of internal.img whose FAT label is ESPTEST1 (made by the Windows job)
ESPN= ; ESPOFF=
while read -r n start; do
  if [[ $(blkid -p -O $((start * 512)) -o value -s LABEL internal.img 2>/dev/null) == ESPTEST1 ]]; then
    ESPN=$n; ESPOFF=$((start * 512))
  fi
done < <(partx -g -o NR,START internal.img)
[[ -n $ESPN ]] || die "EFI test partition not found"
# Windows' diskpart can't make a "real" ESP on a virtual disk with a drive letter; set the type here.
sgdisk -t "$ESPN:ef00" internal.img >/dev/null
M="internal.img@@$ESPOFF"
echo "== boot stage made by sufun-sd-setup.ps1:"; mdir -/ -i "$M" ::/EFI/SUFUN ::/loader 2>&1 | grep -vE '^$|Volume|Directory for' | head -30
mtype -i "$M" ::/loader/entries/sufun-live.conf | tee live-entry.conf
grep -q 'archisodevice=/dev/disk/by-uuid/' live-entry.conf || die "live entry has no archisodevice"
# Emulate the firmware entry "SUFUN (SD)": the EFI fallback path starts the same file.
mmd -i "$M" ::/EFI/BOOT 2>/dev/null || true
mcopy -o -i "$M" "::/EFI/SUFUN/systemd-bootx64.efi" bootx64.efi && mcopy -o -i "$M" bootx64.efi ::/EFI/BOOT/BOOTX64.EFI

set_entry_test() {  # set_entry_test <mode> [extra options]: serial console + sufun.test=<mode> in the live entry
  # plymouth.ignore-serial-consoles: the SUFUN boot splash is still drawn on the
  # screen (for the screenshots) although a serial console is attached.
  sed -e 's/ console=ttyS0[^ ]*//g; s/ console=tty0//g; s/ sufun\.test=[a-z]*//g; s/ sufun\.welcome=[^ ]*//g' \
      -e "/^options/s/\$/ console=ttyS0,115200 console=tty0 plymouth.ignore-serial-consoles sufun.test=$1 ${2:-}/" live-entry.conf > e.conf
  mcopy -o -i "$M" e.conf ::/loader/entries/sufun-live.conf
}

# Fingerprint of everything on the internal disk that is NOT the SUFUN boot stage
fingerprint() {
  sfdisk -d internal.img | grep -v '^label-id\|^first-lba\|^last-lba' | sed "s/type=.*//"
  partx -g -o NR,START,SECTORS internal.img | while read -r n s c; do
    [[ $n == "$ESPN" ]] || dd if=internal.img bs=512 skip="$s" count="$c" status=none | sha256sum
  done
}
fingerprint > before.txt

SD=(-device sdhci-pci,addr=0x3,sd-spec-version=3 -drive id=sdimg,if=none,format=raw,file=card.img -device sd-card,drive=sdimg)
# bootindex: the firmware must start the internal disk (boot stage), never the card itself
# (the card is bootable too; which one an unconfigured OVMF picks first is not fixed)
DISK=(-drive file=internal.img,if=none,id=idisk,format=raw -device virtio-blk-pci,addr=0x4,drive=idisk,bootindex=1)

fail=0
# The first-start chooser picks English (US) here: the "abroad" path (English
# desktop, America/New_York, US keyboard); the other tests use Korean.
set_entry_test live sufun.welcome=en_US.UTF-8
FAST_SHOTS=40 run_vm 6-sd-live 2400 'SUFUN-TEST: LIVE-DESKTOP-OK' 'SUFUN-TEST: LIVE-DESKTOP-TIMEOUT' "${DISK[@]}" "${SD[@]}" || fail=1
grep -q 'SUFUN-TEST: PASS live-from-sd' 6-sd-live-serial.log || { echo "the live system did not run from the SD card"; fail=1; }
check_serial 6-sd-live || fail=1

if (( ! fail )); then
  set_entry_test sdinstall
  run_vm 7-sd-install 5400 'SUFUN-TEST: INSTALL-DONE' 'SUFUN-TEST: INSTALL-FAILED' "${DISK[@]}" "${SD[@]}" || fail=1
  grep -qE 'SUFUN-TEST: TARGET /dev/mmcblk0[[:space:]]*$' 7-sd-install-serial.log || { echo "SD install did not target the card"; fail=1; }
fi
if (( ! fail )); then
  echo "== card after install:"; sfdisk -l card.img
  FAST_SHOTS=20 run_vm 8-sd-installed 1500 'SUFUN-TEST: INSTALLED-DONE' 'SUFUN-TEST: NEVER' "${DISK[@]}" "${SD[@]}" || fail=1
  check_serial 8-sd-installed "$WANT" || fail=1
  fingerprint > after.txt
  if diff before.txt after.txt; then
    echo "OK: internal disk unchanged outside the SUFUN boot stage (partition table, Windows partition)"
  else
    echo "internal disk changed outside the SUFUN boot stage!"; fail=1
  fi
  echo "== boot stage after install:"; mdir -/ -i "$M" ::/EFI/SUFUN ::/loader 2>&1 | grep -vE '^$|Volume|Directory for' | head -30
fi

# --- test 9: the restore rehearsal disk made on Windows ---
if [[ -n $ISO && -f $VHD/rehearsal.vhdx ]]; then
  qemu-img convert -O raw "$VHD/rehearsal.vhdx" rehearsal.img || die "rehearsal.vhdx"
  echo "== rehearsal disk made by sufun-sd-setup.ps1 -RestoreRehearsal:"; sfdisk -l rehearsal.img
  SAVED_VARS=$VARS; VARS="$OUT/reh-vars.fd"; cp "$VARS_SRC" "$VARS"
  # bootindex: the firmware tries this disk first; the SUFUN ISO is only there as
  # the root file system of the test kernel that stands in for Windows Setup
  run_vm 9-rehearsal 900 'SUFUN-TEST: WINSETUP-BOOT-OK' 'SUFUN-TEST: BOOTED' \
    -drive file=rehearsal.img,if=none,id=rdisk,format=raw -device virtio-blk-pci,drive=rdisk,bootindex=1 \
    -cdrom "$ISO" || fail=1
  VARS=$SAVED_VARS
  win=$(tr -d '[:space:]' < "$VHD/rehearsal-entry.hex" 2>/dev/null | tr 'A-F' 'a-f')
  lin=$(grep -ao 'efibootmgr-entry-hex [0-9a-f]*' 9-rehearsal-serial.log | head -n1 | awk '{print $2}')
  echo "entry made by the Windows script: $win"
  echo "entry made by efibootmgr:         $lin"
  if [[ -n $win && $win == "$lin" ]]; then
    echo "OK: the rehearsal's firmware entry is byte-for-byte the entry efibootmgr makes"
  else
    echo "the rehearsal's firmware entry differs from efibootmgr's"; fail=1
  fi
  rm -f rehearsal.img
elif [[ ${GITHUB_ACTIONS:-} == true ]]; then
  echo "restore rehearsal disk or SUFUN ISO missing"; fail=1
fi

rm -f internal.img card.img bootx64.efi e.conf ./*.sock
(( fail )) && { echo "SD TESTS FAILED"; exit 1; }
echo "ALL SD TESTS PASSED"
