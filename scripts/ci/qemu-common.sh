# Shared parts of the QEMU boot tests (sourced by qemu-test.sh and qemu-sd-test.sh).
# Needs: OUT (output directory, current directory). Sets: ACCEL, F, CODE, VARS_SRC.
# Defines: monitor, run_vm, check_serial.

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
# FAST_SHOTS=<seconds> run_vm ...: screenshots about every 2 s for that long first
# Also about every 2 s for 40 s after the VM prints "SUFUN-TEST: LOGIN-START"
# (the installed-system test logging in: the SUFUN login splash appears then).
run_vm() {
  local name=$1 timeout=$(( $2 * F )) ok=$3 bad=$4; shift 4
  local fast=${FAST_SHOTS:-0} next_shot=10 burst=0 named=0 n label
  (( fast > 0 )) && next_shot=2
  local log="$name-serial.log" sock="$OUT/$name.sock" el start=$SECONDS result=TIMEOUT
  : > "$log"
  qemu-system-x86_64 "${ACCEL[@]}" -machine q35 -smp 2 -m 4096 \
    -drive if=pflash,format=raw,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,file="${VARS:-$OUT/vars.fd}" \
    -device virtio-vga -display none \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -serial file:"$log" -monitor unix:"$sock",server,nowait \
    "$@" &
  local pid=$!
  echo "== $name started (timeout ${timeout}s)"
  while kill -0 $pid 2>/dev/null; do
    el=$((SECONDS - start))
    if (( burst == 0 )) && grep -q 'SUFUN-TEST: LOGIN-START' "$log"; then
      burst=$((el + 40)); next_shot=$el
    fi
    if (( el < fast || el < burst )); then sleep 1; else sleep 2; fi
    # "SUFUN-TEST: SHOT <label>": the VM asks for a screenshot now, saved as
    # <name>-<label>.png (e.g. 3-installed-logout.png, the Plasma logout screen).
    n=$(grep -c 'SUFUN-TEST: SHOT ' "$log" || true)
    if (( n > named )); then
      named=$n
      label=$(grep -o 'SUFUN-TEST: SHOT [a-z0-9-]*' "$log" | tail -n 1 | awk '{print $3}')
      monitor "$sock" "screendump $name-$label.png -f png"
    fi
    # Screenshots: every 10 s for the first 3 minutes (boot splash, login screen,
    # desktop appearing), then every minute. File name = seconds since start,
    # e.g. 3-installed-t0040.png = 40 s after the virtual PC was switched on.
    el=$((SECONDS - start))
    if (( el >= next_shot )); then
      monitor "$sock" "screendump $name-t$(printf %04d "$el").png -f png"
      if (( el < fast || el < burst )); then next_shot=$((el + 2))
      elif (( el < 180 )); then next_shot=$((el + 10)); else next_shot=$((el + 60)); fi
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

# check_serial <vm-name> <version>: fail if the VM reported a failed check or the
# wrong sufun-base version
check_serial() {
  local log=$1-serial.log got rc=0
  if grep -q 'SUFUN-TEST: FAIL' "$log"; then echo "Some checks failed in $1"; rc=1; fi
  if [[ -n ${2:-} ]]; then
    got=$(sed -n 's/.*SUFUN-TEST: VERSION \([^[:space:]]*\).*/\1/p' "$log" | head -n1)
    if [[ $got != "$2" ]]; then echo "sufun-base version is '$got', expected '$2'"; rc=1; fi
  fi
  return $rc
}
