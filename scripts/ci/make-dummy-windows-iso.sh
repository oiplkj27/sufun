#!/usr/bin/env bash
# Makes a DUMMY "Windows 11 ISO" for the Windows restore test. It has the same
# layout as Microsoft's ISO, but no Microsoft files at all:
#   efi/boot/bootx64.efi      = systemd-boot from the SUFUN ISO (stands in for
#                               Windows' boot file: it proves the firmware entry
#                               "Windows Setup" really starts this file)
#   efi/microsoft/boot/bcd, boot/bcd, bootmgr, bootmgr.efi, setup.exe   placeholders
#   sources/boot.wim          a real (tiny) WIM file
#   sources/install.wim       a real WIM with 48 MB of random data; the test makes
#                             sufun-windows-restore split it into 16 MB .swm parts
#   loader/ + sufun-test/     what bootx64.efi (systemd-boot) starts: the SUFUN live
#                             kernel with "sufun.test=winsetup" (reports and powers off)
#   bash make-dummy-windows-iso.sh <sufun.iso> <sufun-iso-label> <out.iso>
set -euo pipefail
ISO=$1 LABEL=$2 OUTISO=$3
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
D=$T/iso
mkdir -p "$D"/{efi/boot,efi/microsoft/boot,boot,sources,loader/entries,sufun-test} "$T/wim-boot" "$T/wim-install"
xorriso -osirrox on -indev "$ISO" \
  -extract /EFI/BOOT/BOOTx64.EFI "$D/efi/boot/bootx64.efi" \
  -extract /arch/boot/x86_64/vmlinuz-linux-surface "$D/sufun-test/vmlinuz" \
  -extract /arch/boot/x86_64/initramfs-linux-surface.img "$D/sufun-test/initrd.img" >/dev/null 2>&1
chmod -R u+w "$D"
for f in efi/microsoft/boot/bcd boot/bcd bootmgr bootmgr.efi setup.exe; do
  echo "SUFUN test placeholder (not a Microsoft file)" > "$D/$f"
done
echo "SUFUN test" > "$T/wim-boot/readme.txt"
head -c $((48 * 1024 * 1024)) /dev/urandom > "$T/wim-install/random.bin"
wimlib-imagex capture "$T/wim-boot" "$D/sources/boot.wim" "Test boot" --compress=none >/dev/null
wimlib-imagex capture "$T/wim-install" "$D/sources/install.wim" "Test install" --compress=none >/dev/null
printf 'default winsetup.conf\ntimeout 0\n' > "$D/loader/loader.conf"
cat > "$D/loader/entries/winsetup.conf" <<EOT
title   SUFUN restore test (stands in for Windows Setup)
linux   /sufun-test/vmlinuz
initrd  /sufun-test/initrd.img
options archisobasedir=arch archisolabel=$LABEL copytoram=n console=ttyS0,115200 console=tty0 sufun.test=winsetup
EOT
xorriso -as mkisofs -quiet -V SUFUN_WINTEST -J -joliet-long -R -o "$OUTISO" "$D"
ls -l "$OUTISO"
