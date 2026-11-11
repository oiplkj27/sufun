#!/usr/bin/env bash
# Puts the ISO into the release folder. GitHub Releases allow at most 2 GiB per
# file, so a bigger ISO is split into 1900 MB parts with Korean join instructions.
#   bash scripts/ci/add-iso-to-release.sh <iso-dir> <dist-dir>
set -euo pipefail
iso=$(ls "$1"/*.iso | head -n1); dist=$2; name=$(basename "$iso")
mkdir -p "$dist"
( cd "$(dirname "$iso")" && sha256sum "$name" ) > "$dist/ISO-SHA256.txt"

if (( $(stat -c %s "$iso") < 2147483648 )); then
  cp "$iso" "$dist/"
  exit 0
fi

split -b 1900M -d -a 2 "$iso" "$dist/$name.part"
parts=$(cd "$dist" && ls "$name".part* | paste -sd+ - | sed 's/+/ + /g')
cat > "$dist/ISO-합치는-방법.txt" <<EOF
ISO 파일이 2 GiB보다 커서 여러 조각(.part00, .part01, ...)으로 나누어 올렸습니다.
GitHub Release는 파일 하나에 2 GiB까지만 올릴 수 있기 때문입니다.
모든 조각을 같은 폴더에 내려받은 뒤 하나로 합치세요.

Windows (명령 프롬프트 cmd, 조각이 있는 폴더에서):
  copy /b $parts $name

Linux / macOS:
  cat $name.part* > $name

합친 뒤 ISO-SHA256.txt 의 값과 비교하세요 (같아야 정상):
  Windows PowerShell:  Get-FileHash $name -Algorithm SHA256
  Linux:               sha256sum $name
EOF
ls -lh "$dist"
