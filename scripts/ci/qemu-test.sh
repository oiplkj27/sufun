#!/usr/bin/env bash
# Automatic boot + install test (idea from KDE Linux: every image must boot to the desktop).
#   bash scripts/ci/qemu-test.sh <iso> <expected-version> <output-dir>
#
#   Test 1: live USB boots to the Plasma desktop, checks the Windows 11-style layout,
#           prints RAM numbers
#   Test 2: the installer installs SUFUN to an empty 64 GB virtual disk (test mode)
#   Test 3: the installed system boots, shows the login screen, checks itself, then
#           logs in (test disk only) and checks the Korean desktop
#           (SUFUN boot entry + Plymouth, version, zram, earlyoom, firewall, fstab)
# Success is read from the serial console ("SUFUN-TEST: ..." lines written by
# sufun-selftest), not from fixed waiting times. Screenshots are saved every
# 10 seconds for the first 3 minutes, then every minute (QEMU monitor
# "screendump"), plus the serial logs: upload <output-dir>.
#
# Needs: qemu-system-x86_64, qemu-img, OVMF (UEFI firmware), xorriso, python3.
# Uses KVM when /dev/kvm is usable, otherwise slow software emulation with longer timeouts.
set -uo pipefail

ISO="$(realpath "${1:?iso}")"; WANT="${2:?version}"; OUT="${3:?output dir}"
mkdir -p "$OUT"; OUT="$(realpath "$OUT")"
cd "$OUT" || exit 1

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  ACCEL=(-accel kvm -cpu host); F=1; echo "Using KVM"
else
  ACCEL=(-accel tcg -cpu max); F=4; echo "No KVM: software emulation, timeouts x$F"
fi

# UEFI firmware (Ubuntu: package "ovmf", Arch: "edk2-ovmf")
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.fd; do
  [[ -f $c ]] && { CODE=$c; break; }
done
VARS_SRC=${CODE/CODE/VARS}
[[ -n ${CODE:-} && -f $VARS_SRC ]] || { echo "OVMF firmware not found" >&2; exit 1; }
cp "$VARS_SRC" vars.fd

# Kernel + initramfs from the ISO: test 1 and 2 add kernel options
# (serial console, sufun.test=...) without touching the boot menu.
xorriso -osirrox on -indev "$ISO" \
  -extract /arch/boot/x86_64/vmlinuz-linux-surface vmlinuz \
  -extract /arch/boot/x86_64/initramfs-linux-surface.img initrd.img \
  -extract /arch/boot/intel-ucode.img ucode.img >/dev/null 2>&1 || true
[[ -s vmlinuz && -s initrd.img ]] || { echo "kernel not found in ISO" >&2; exit 1; }
LABEL=$(blkid -s LABEL -o value "$ISO" 2>/dev/null || xorriso -indev "$ISO" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p')
LIVEOPTS="archisobasedir=arch archisolabel=$LABEL console=ttyS0,115200 console=tty0"

qemu-img create -f qcow2 disk.qcow2 64G >/dev/null

monitor() {  # monitor <socket> <command>   (QEMU human monitor)
  python3 - "$1" "$2" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.settimeout(5)
try:
    s.connect(sys.argv[1]); time.sleep(0.2); s.recv(4096)
    s.sendall((sys.argv[2] + "\n").encode()); time.sleep(1)
except Exception as e:
    print("monitor:", e, file=sys.stderr)
PY
}

# run_vm <name> <timeout-seconds> <success-regex> <fail-regex> <qemu args...>
run_vm() {
  local name=$1 timeout=$(( $2 * F )) ok=$3 bad=$4; shift 4
  local log="$name-serial.log" sock="$OUT/$name.sock" next_shot=10 el start=$SECONDS result=TIMEOUT
  : > "$log"
  qemu-system-x86_64 "${ACCEL[@]}" -machine q35 -smp 2 -m 4096 \
    -drive if=pflash,format=raw,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,file="$OUT/vars.fd" \
    -device virtio-vga -display none \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -serial file:"$log" -monitor unix:"$sock",server,nowait \
    "$@" &
  local pid=$!
  echo "== $name started (timeout ${timeout}s)"
  while kill -0 $pid 2>/dev/null; do
    sleep 2
    # Screenshots: every 10 s for the first 3 minutes (boot splash, login screen,
    # desktop appearing), then every minute. File name = seconds since start,
    # e.g. 3-installed-t0040.png = 40 s after the virtual PC was switched on.
    el=$((SECONDS - start))
    if (( el >= next_shot )); then
      monitor "$sock" "screendump $name-t$(printf %04d "$el").png -f png"
      if (( el < 180 )); then next_shot=$((el + 10)); else next_shot=$((el + 60)); fi
    fi
    if grep -qE "$ok" "$log"; then result=OK; break; fi
    if grep -qE "$bad" "$log"; then result=FAILED; break; fi
    (( SECONDS - start > timeout )) && break
  done
  monitor "$sock" "screendump $name-final.png -f png"
  # Installer and installed-system tests power off by themselves; give them a moment.
  for _ in 1 2 3 4 5 6; do kill -0 $pid 2>/dev/null || break; sleep 5; done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  grep -q 'SUFUN-TEST' "$log" && grep 'SUFUN-TEST' "$log" | sed "s/^/   [$name] /"
  echo "== $name: $result"
  [[ $result == OK ]]
}

fail=0
run_vm 1-live 1200 'SUFUN-TEST: LIVE-DESKTOP-OK' 'SUFUN-TEST: LIVE-DESKTOP-TIMEOUT' \
  -cdrom "$ISO" -kernel vmlinuz -initrd initrd.img -append "$LIVEOPTS sufun.test=live" || fail=1

run_vm 2-install 3600 'SUFUN-TEST: INSTALL-DONE' 'SUFUN-TEST: INSTALL-FAILED' \
  -cdrom "$ISO" -drive file=disk.qcow2,if=virtio,format=qcow2 \
  -kernel vmlinuz -initrd initrd.img -append "$LIVEOPTS sufun.test=install" || fail=1

if (( ! fail )); then
  # Boot from the virtual disk only, like a real start: firmware -> systemd-boot -> SUFUN
  run_vm 3-installed 1200 'SUFUN-TEST: INSTALLED-DONE' 'SUFUN-TEST: NEVER' \
    -drive file=disk.qcow2,if=virtio,format=qcow2 || fail=1
  log=3-installed-serial.log
  if grep -q 'SUFUN-TEST: FAIL' "$log"; then echo "Some checks failed on the installed system"; fail=1; fi
  got=$(sed -n 's/.*SUFUN-TEST: VERSION \([^[:space:]]*\).*/\1/p' "$log" | head -n1)
  if [[ $got != "$WANT" ]]; then echo "sufun-base version is '$got', expected '$WANT'"; fail=1; fi
fi

rm -f disk.qcow2 vmlinuz initrd.img ucode.img ./*.sock
(( fail )) && { echo "TESTS FAILED"; exit 1; }
echo "ALL TESTS PASSED"
