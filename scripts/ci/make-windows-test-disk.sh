#!/usr/bin/env bash
# Makes the "Surface with Windows" test disk for the installer test (qemu-test.sh,
# test 2): a 64 GB disk image laid out like a Windows 11 install (EFI + reserved +
# NTFS "Windows" + recovery), with a pretend Windows user and known files. No
# Microsoft files. The installer's "Windows 파일 가져오기" must bring exactly the
# right files into the new SUFUN (checked by sufun-selftest, import_checks).
#   bash scripts/ci/make-windows-test-disk.sh <out.qcow2>
# Needs root (sudo) for loop devices, plus: sgdisk, mkfs.vfat, mkntfs + ntfs-3g, qemu-img.
set -euo pipefail
OUT=${1:?output qcow2}
W=$(mktemp -d)
RAW=$W/win.raw
LOOP=
cleanup() {
  sudo umount "$W/mnt" 2>/dev/null || true
  [[ -n $LOOP ]] && sudo losetup -d "$LOOP" 2>/dev/null
  sudo rm -rf "$W"
}
trap cleanup EXIT

truncate -s 64G "$RAW"
sgdisk -n1:0:+260M -t1:ef00 -c1:"EFI system partition" \
       -n2:0:+16M  -t2:0c01 -c2:"Microsoft reserved partition" \
       -n3:0:+20G  -t3:0700 -c3:"Basic data partition" \
       -n4:0:+700M -t4:2700 "$RAW" >/dev/null
LOOP=$(sudo losetup -Pf --show "$RAW")
sudo mkfs.vfat -F32 -n SYSTEM "${LOOP}p1" >/dev/null
sudo mkntfs -Q -q -L Windows "${LOOP}p3"
mkdir -p "$W/mnt"
sudo mount -t ntfs-3g "${LOOP}p3" "$W/mnt"
M=$W/mnt
U=$M/Users/gildong
sudo mkdir -p "$M/Windows/System32" "$M/Program Files" "$M/\$RECYCLE.BIN" \
  "$U/Desktop" "$U/Documents/보고서" "$U/Pictures" "$U/Downloads" "$U/Videos" \
  "$U/OneDrive/Documents" "$U/OneDrive/문서" "$U/AppData/Roaming/App" \
  "$M/Users/Public/Documents" "$M/Users/Default"
w() { sudo tee "$1" >/dev/null; }      # w <file>: stdin -> file (as root)
echo "pretend registry"      | w "$U/NTUSER.DAT"
echo "pretend registry"      | w "$M/Users/Default/NTUSER.DAT"
echo "desktop note"          | w "$U/Desktop/메모 한글.txt"
printf 'tiny'                | w "$U/Desktop/tiny.txt"            # 4 bytes: stored inside the file table
printf '[.ShellClassInfo]\n' | w "$U/Desktop/desktop.ini"
echo "pretend shortcut"      | w "$U/Desktop/Edge.lnk"
echo "pretend thumbnails"    | w "$U/Pictures/Thumbs.db"
head -c 3000000 < <(yes sufun-import-test) | w "$U/Documents/보고서/report big.bin"
echo "kept in OneDrive, but really on this disk" | w "$U/OneDrive/Documents/from-onedrive.txt"
head -c 200000 /dev/urandom  | w "$U/Pictures/photo.jpg"
head -c 50000 /dev/urandom   | w "$U/Downloads/setup-file.zip"
echo "appdata-secret"        | w "$U/AppData/Roaming/App/secret.txt"
echo "someone else's file"   | w "$M/Users/Public/Documents/public-file.txt"
echo "deleted"               | w "$M/\$RECYCLE.BIN/deleted.txt"
# OneDrive "online-only" files: they have a size, but their data is not on the disk
sudo truncate -s 5M "$U/OneDrive/문서/online-only-big.docx"
sudo truncate -s 40K "$U/OneDrive/Documents/online-only-small.xlsx"
sync
echo "windows test disk: online-only files use $(sudo stat -c '%b blocks for %s bytes' "$U/OneDrive/문서/online-only-big.docx"), tiny.txt $(sudo stat -c '%b blocks' "$U/Desktop/tiny.txt")"
sudo find "$M/Users" -type f | sed "s|$M/||" | sort
sudo umount "$M"
sudo losetup -d "$LOOP"; LOOP=
qemu-img convert -f raw -O qcow2 "$RAW" "$OUT"
ls -l "$OUT"
