<#
.SYNOPSIS
  SUFUN을 microSD 카드에서 켜기 위한 준비 (USB 없이). Surface Go 3의 Windows에서 관리자로 한 번 실행합니다.

.DESCRIPTION
  이 Surface는 USB로 부팅할 수 없고, 펌웨어(UEFI)는 microSD 카드에서 직접 부팅하지 못합니다.
  그래서:
    - microSD 카드:  SUFUN 라이브 시스템 전체 (ISO 내용)
    - 내부 저장장치: 아주 작은 "부팅 단계"만 (부팅 메뉴 + 커널 + initramfs, 약 150 MB)
                     EFI 시스템 파티션의 \EFI\SUFUN\ 폴더, 공간이 모자라면 C:를 1 GB 줄여 만든 작은 파티션
  펌웨어가 내부 저장장치에서 커널을 읽고, 커널이 카드(UUID로 찾음)에서 SUFUN을 시작합니다.
  펌웨어 부팅 항목 "SUFUN (SD)"를 추가하지만 기본값은 바꾸지 않습니다: Windows가 계속 먼저 켜집니다.

  카드가 2가지 경우:
    (a) ISO가 내부 저장장치에 있음: 카드를 포맷하고 앞부분(약 4 GB)에 라이브 파일을 넣습니다.
        나머지는 비워 둡니다 (나중에 "SD카드에 설치" 용).
    (b) ISO가 카드 자체에 있음 (C: 공간이 적을 때): 포맷하지 않고 같은 카드에 ISO 내용을 풀고,
        원하면 ISO 파일을 지웁니다. (카드 전체가 한 파티션이라 "SD카드에 설치"는 할 수 없습니다.)

  안전 규칙: BusType이 SD/MMC이거나 이동식인 디스크만 카드로 씁니다. Windows가 있는 디스크는
  절대 카드로 쓰지 않습니다. 내부 저장장치에서는 \EFI\SUFUN, SUFUN의 \loader 폴더,
  그리고 (필요할 때만) C: 축소 + "SUFUNBOOT" 파티션만 바뀝니다.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\sufun-sd-setup.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\sufun-sd-setup.ps1 -IsoPath "D:\sufun-1.0-x86_64.iso"
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\sufun-sd-setup.ps1 -Uninstall
  모두 되돌립니다: 부팅 항목, 부팅 파일, SUFUNBOOT 파티션 (C:를 원래 크기로). 카드의 파일은 그대로 둡니다.
#>
[CmdletBinding()]
param(
    [string]$IsoPath,
    [switch]$Uninstall,
    # ---- CI test mode (GitHub Actions only, virtual disks only; refused everywhere else) ----
    [int]$CiCardDisk = -1,
    [string]$CiEspLetter,
    [string]$CiWindowsLetter,
    [int]$BootPartMB = 1024        # size of the SUFUNBOOT partition, if one is needed
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$EntryName     = 'SUFUN (SD)'          # firmware menus have no Korean font: ASCII
$BootPartLabel = 'SUFUNBOOT'           # FAT32 labels: max 11 letters
$LiveLabel     = 'SUFUNLIVE'
$BasicDataGuid = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
$StateDir      = Join-Path $env:ProgramData 'SUFUN'
$StateFile     = Join-Path $StateDir 'sd-setup.txt'
$Ci            = $false

# ------------------------------------------------------------------ messages
function Say([string]$m)  { Write-Host $m }
function Step([string]$m) { Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host $m -ForegroundColor Yellow }
function Pause-End {
    # keeps the window open when started by double-click; never waits in CI or without a console
    if ($script:Ci -or $env:GITHUB_ACTIONS -eq 'true' -or [Console]::IsInputRedirected) { return }
    try { [void](Read-Host 'Enter를 누르면 창을 닫습니다') } catch {}
}
function Fail([string]$m) {
    Write-Host ''
    Write-Host "오류: $m" -ForegroundColor Red
    Cleanup
    Pause-End
    exit 1
}
function Ask-Word([string]$word, [string]$prompt) {
    if ($script:Ci) { Say "$prompt $word (테스트 모드: 자동)"; return }
    $a = Read-Host $prompt
    if ($a -cne $word) { Fail '취소했습니다. 아무것도 바뀌지 않았습니다.' }
}
function Ask-YesNo([string]$prompt, [bool]$defaultYes) {
    if ($script:Ci) { return $defaultYes }
    $hint = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
    $a = (Read-Host "$prompt $hint").Trim()
    if ($a -eq '') { return $defaultYes }
    return ($a -match '^(y|yes|예|네|ㅇ)$')
}

# ------------------------------------------------------------------ helpers
$script:MountedIso   = $null
$script:EspLetter    = $null
$script:TempLetters  = @()

function Cleanup {
    if ($script:MountedIso) {
        try { Dismount-DiskImage -ImagePath $script:MountedIso | Out-Null } catch {}
        $script:MountedIso = $null
    }
    if ($script:EspLetter -and -not $script:Ci) {
        [void](Run-Native 'mountvol.exe' @("$($script:EspLetter):", '/d'))
        $script:EspLetter = $null
    }
    foreach ($p in $script:TempLetters) {
        try { Remove-PartitionAccessPath -DiskNumber $p[0] -PartitionNumber $p[1] -AccessPath "$($p[2]):\" -ErrorAction Stop } catch {}
    }
    $script:TempLetters = @()
}

function Get-FreeLetter {
    $used = @([IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpper() })
    foreach ($c in 'S', 'U', 'V', 'W', 'X', 'Y', 'Z', 'R', 'Q', 'P', 'O', 'N', 'M', 'L') {
        if ($used -notcontains $c) { return $c }
    }
    Fail '빈 드라이브 문자가 없습니다.'
}

function Write-Unix([string]$path, [string[]]$lines) {
    # systemd-boot files: plain UTF-8 without BOM, Linux line endings
    $enc = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), $enc)
}

function Read-State {
    $h = @{}
    if (Test-Path -LiteralPath $StateFile) {
        foreach ($line in Get-Content -LiteralPath $StateFile) {
            if ($line -match '^([A-Za-z]+)=(.*)$') { $h[$Matches[1]] = $Matches[2] }
        }
    }
    return $h
}

function Save-State([hashtable]$h, [string]$copyTo) {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $lines = @('# SUFUN microSD boot setup (sufun-sd-setup.ps1). Used by -Uninstall.')
    foreach ($k in ($h.Keys | Sort-Object)) { $lines += "$k=$($h[$k])" }
    Set-Content -LiteralPath $StateFile -Value $lines -Encoding UTF8
    if ($copyTo) { Write-Unix $copyTo $lines }
}

function Run-Native([string]$exe, [string[]]$argv) {
    # Windows PowerShell 5.1: with ErrorActionPreference=Stop, any text a program
    # writes to stderr would stop the script. Here it is just collected.
    $ErrorActionPreference = 'Continue'
    $out = & $exe @argv 2>&1 | ForEach-Object { "$_" } | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function Invoke-Native([string]$exe, [string[]]$argv, [string]$what) {
    $r = Run-Native $exe $argv
    if ($r.Code -ne 0) { Fail "$what 실패: $($r.Out.Trim())" }
    return $r.Out
}

function Fmt-GB([double]$bytes) { return ('{0:N1} GB' -f ($bytes / 1GB)) }

function Get-WindowsPartition {
    $l = if ($script:Ci) { $CiWindowsLetter } else { $env:SystemDrive.Substring(0, 1) }
    return Get-Partition -DriveLetter $l
}

# BitLocker / Device Encryption on C:. Changing boot settings or partitions can
# make Windows ask for the recovery key at the next start.
function Check-BitLocker {
    Step 'BitLocker(장치 암호화) 확인'
    if ($script:Ci) { Say '    테스트 모드: 건너뜀'; return }
    $drive = $env:SystemDrive
    $prot = $null; $vol = $null
    try {
        $v = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
        $prot = "$($v.ProtectionStatus)"; $vol = "$($v.VolumeStatus)"
    } catch {
        try {
            $w = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$drive'" -ErrorAction Stop
            if ($w) { $prot = @('Off', 'On', 'Unknown')[[int]$w.ProtectionStatus] }
        } catch {}
    }
    if (-not $prot) {
        Warn '    BitLocker 상태를 확인할 수 없습니다. 복구 키를 미리 준비해 두세요: https://aka.ms/myrecoverykey'
        return
    }
    Say "    $drive 보호 상태: $prot  (암호화: $vol)"
    if ($prot -ne 'On') { Ok 'BitLocker 보호가 꺼져 있습니다.'; return }
    Warn ''
    Warn '    BitLocker(장치 암호화)가 켜져 있습니다.'
    Warn '    부팅 설정이나 파티션을 바꾸면 다음 시작 때 Windows가 48자리 "복구 키"를 물어볼 수 있습니다.'
    Warn '    다른 기기(휴대폰)에서 https://aka.ms/myrecoverykey 에 Microsoft 계정으로 로그인해'
    Warn '    이 Surface의 복구 키를 찾아 종이에 적어 두세요. 복구 키 없이는 Windows를 열 수 없습니다.'
    Ask-Word 'YES' '    복구 키를 준비했으면 YES 를 입력하세요'
    if (Ask-YesNo '    다음 재시작 1번 동안 BitLocker를 일시 중지할까요? (Suspend-BitLocker -RebootCount 1, 권장)' $true) {
        try {
            Suspend-BitLocker -MountPoint $drive -RebootCount 1 -ErrorAction Stop | Out-Null
        } catch {
            Invoke-Native 'manage-bde.exe' @('-protectors', '-disable', $drive, '-RebootCount', '1') 'BitLocker 일시 중지' | Out-Null
        }
        Ok 'BitLocker를 다음 재시작 1번 동안 일시 중지했습니다 (그 뒤 자동으로 다시 켜짐).'
    }
}

function Check-SecureBoot {
    Step 'Secure Boot 확인'
    if ($script:Ci) { Say '    테스트 모드: 건너뜀'; return }
    try { $sb = Confirm-SecureBootUEFI } catch {
        Fail "UEFI 정보를 읽을 수 없습니다 ($($_.Exception.Message)). 이 PC가 UEFI 모드인지 확인하세요."
    }
    if ($sb) {
        Fail 'Secure Boot가 켜져 있습니다. 전원을 끄고 볼륨 위(+) + 전원 → Surface UEFI → Security → Secure Boot → None 으로 바꾼 뒤 다시 실행하세요.'
    }
    Ok 'Secure Boot: 꺼짐'
}

# Disks that may be used as the card: SD/MMC bus or removable media, never the
# disk with Windows (C:), never a boot/system disk.
function Get-CardDisks {
    if ($script:Ci) { return @(Get-Disk -Number $CiCardDisk) }
    $winDisk = (Get-WindowsPartition).DiskNumber
    $removable = @{}
    foreach ($d in Get-CimInstance Win32_DiskDrive) {
        if ("$($d.MediaType)" -match 'Removable') { $removable[[int]$d.Index] = $true }
    }
    $out = @()
    foreach ($d in Get-Disk) {
        $bt = "$($d.BusType)"
        if ($d.Number -eq $winDisk -or $d.IsBoot -or $d.IsSystem) { continue }
        if ($bt -eq 'USB') { continue }      # this Surface's USB-C has no data anyway
        if ($bt -eq 'SD' -or $bt -eq 'MMC' -or $removable.ContainsKey([int]$d.Number)) { $out += $d }
    }
    return $out
}

function Show-Disk($d) {
    $name = "$($d.FriendlyName)".Trim()
    if (-not $name) { $name = "$($d.Model)".Trim() }
    Say ('    디스크 {0}:  {1}  {2}  (버스: {3})' -f $d.Number, (Fmt-GB $d.Size), $name, $d.BusType)
}

function Get-FatUuid([string]$letter) {
    # Linux shows a FAT32/exFAT volume serial number as its UUID: "ABCD-1234"
    $v = Get-CimInstance Win32_Volume -Filter "DriveLetter='${letter}:'"
    if (-not $v -or $null -eq $v.SerialNumber) { Fail "$letter`: 의 볼륨 일련 번호를 읽을 수 없습니다." }
    $h = '{0:X8}' -f ([uint32]$v.SerialNumber)
    return $h.Substring(0, 4) + '-' + $h.Substring(4, 4)
}

function Mount-Esp {
    if ($script:Ci) { return $CiEspLetter }
    $l = Get-FreeLetter
    Invoke-Native 'mountvol.exe' @("${l}:", '/s') 'EFI 시스템 파티션 연결 (mountvol /s)' | Out-Null
    $script:EspLetter = $l
    return $l
}
function Dismount-Esp {
    if ($script:EspLetter -and -not $script:Ci) {
        [void](Run-Native 'mountvol.exe' @("$($script:EspLetter):", '/d'))
    }
    $script:EspLetter = $null
}

function Get-FolderBytes([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    $s = (Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($s) { return [int64]$s } else { return 0 }
}

function Find-BcdEntries {
    # identifiers of firmware entries called "SUFUN (SD)" (works on any Windows language:
    # only the GUIDs and our own name are read)
    $ids = @()
    $txt = (Run-Native 'bcdedit.exe' @('/enum', 'firmware', '/v')).Out
    foreach ($block in ($txt -split '(\r?\n)\s*(\r?\n)')) {
        if ($block.Contains($EntryName) -and $block -match '\{[0-9a-fA-F-]{36}\}') { $ids += $Matches[0] }
    }
    return $ids
}

function Get-BootPartitions([int]$disk) {
    $out = @()
    foreach ($p in Get-Partition -DiskNumber $disk) {
        $v = $null
        try { $v = Get-Volume -Partition $p -ErrorAction Stop } catch {}
        if ($v -and $v.FileSystemLabel -eq $BootPartLabel) { $out += $p }
    }
    return $out
}

function Use-Letter($part) {
    # gives a partition a temporary drive letter (removed again by Cleanup)
    if ($part.DriveLetter -and "$($part.DriveLetter)".Trim() -and [int][char]$part.DriveLetter -ne 0) { return [string]$part.DriveLetter }
    $l = Get-FreeLetter
    Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $l
    $script:TempLetters += , @($part.DiskNumber, $part.PartitionNumber, $l)
    return $l
}

# ============================================================== start
if ($CiCardDisk -ge 0) {
    if ($env:GITHUB_ACTIONS -ne 'true' -or $env:SUFUN_CI_TEST -ne '1') { Fail '테스트 모드는 GitHub Actions 전용입니다.' }
    $cd = Get-Disk -Number $CiCardDisk
    $chk = @($cd)
    foreach ($l in @($CiEspLetter, $CiWindowsLetter)) { $chk += Get-Disk -Number (Get-Partition -DriveLetter $l).DiskNumber }
    foreach ($d in $chk) {
        if ("$($d.BusType)" -ne 'File Backed Virtual' -or $d.IsBoot -or $d.IsSystem) { Fail '테스트 모드는 가상 디스크(VHD)에만 쓸 수 있습니다.' }
    }
    $Ci = $true
    Warn '*** CI 테스트 모드 (가상 디스크만 사용, 펌웨어 부팅 항목은 만들지 않음) ***'
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail '관리자 권한이 필요합니다. 시작 단추를 오른쪽 클릭 → "터미널(관리자)" 를 열고 다시 실행하세요.'
}

Write-Host ''
Write-Host '=== SUFUN microSD 부팅 준비 (Surface Go 3, USB 없이) ===' -ForegroundColor White
if ($Uninstall) { Write-Host '    모드: 되돌리기 (-Uninstall)' }

# ============================================================== -Uninstall
if ($Uninstall) {
    $st = Read-State
    Check-BitLocker
    if (-not $Ci) {
        Step "펌웨어 부팅 항목 '$EntryName' 삭제"
        $ids = @()
        if ($st.ContainsKey('BcdId')) { $ids += $st['BcdId'] }
        $ids += Find-BcdEntries
        foreach ($id in ($ids | Sort-Object -Unique)) {
            $r = Run-Native 'bcdedit.exe' @('/enum', $id)
            if ($r.Code -eq 0 -and $r.Out.Contains($EntryName)) {
                Invoke-Native 'bcdedit.exe' @('/delete', $id) "부팅 항목 $id 삭제" | Out-Null
                Ok "삭제됨: $id"
            }
        }
    }

    Step 'EFI 시스템 파티션에서 SUFUN 부팅 파일 삭제'
    $l = Mount-Esp
    foreach ($p in @("${l}:\EFI\SUFUN")) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force; Ok "삭제됨: $p" }
    }
    if (Test-Path -LiteralPath "${l}:\loader\sufun-owned.txt") {
        Remove-Item -LiteralPath "${l}:\loader" -Recurse -Force; Ok "삭제됨: ${l}:\loader (SUFUN이 만든 폴더)"
    }
    Dismount-Esp

    Step "'$BootPartLabel' 파티션 삭제, Windows 파티션을 원래 크기로"
    $wp = Get-WindowsPartition
    $removed = [int64]0
    foreach ($p in Get-BootPartitions $wp.DiskNumber) {
        # only the SUFUNBOOT partition right after the Windows partition is "ours"
        $gap = $p.Offset - ($wp.Offset + $wp.Size)
        if ($gap -lt 0 -or $gap -gt 64MB) { Warn "    디스크 $($p.DiskNumber) 파티션 $($p.PartitionNumber) 은(는) Windows 파티션 바로 뒤가 아니라 건드리지 않습니다."; continue }
        Remove-Partition -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -Confirm:$false
        $removed += $gap + $p.Size
        Ok "삭제됨: 디스크 $($p.DiskNumber) 파티션 $($p.PartitionNumber) ($(Fmt-GB $p.Size))"
    }
    Update-HostStorageCache
    $wp = Get-WindowsPartition
    $sup = Get-PartitionSupportedSize -DiskNumber $wp.DiskNumber -PartitionNumber $wp.PartitionNumber
    # Give back exactly the space SUFUN took (never other free space that was already there)
    $target = [int64]$wp.Size
    if ($removed -gt 0) {
        if ($st.ContainsKey('WindowsSizeBefore')) { $target = [Math]::Min([int64]$sup.SizeMax, [int64]$st['WindowsSizeBefore']) }
        else { $target = [Math]::Min([int64]$sup.SizeMax, [int64]$wp.Size + $removed) }
    }
    if ($target -gt $wp.Size) {
        Resize-Partition -DiskNumber $wp.DiskNumber -PartitionNumber $wp.PartitionNumber -Size $target
        Ok "Windows 파티션: $(Fmt-GB $wp.Size) → $(Fmt-GB $target)"
    } else { Ok 'Windows 파티션 크기는 그대로입니다.' }

    if (Test-Path -LiteralPath $StateFile) { Remove-Item -LiteralPath $StateFile -Force }
    Cleanup
    Write-Host ''
    Ok '되돌리기 완료. Windows는 SUFUN 준비 전과 같습니다.'
    Say '    microSD 카드의 파일은 그대로 있습니다. 카드를 다른 용도로 쓰려면'
    Say '    파일 탐색기에서 카드를 오른쪽 클릭 → 포맷 (exFAT) 을 하세요.'
    Pause-End
    exit 0
}

# ============================================================== setup
Check-SecureBoot
Check-BitLocker

Step 'SUFUN ISO 열기'
if (-not $IsoPath) { $IsoPath = Read-Host '    SUFUN ISO 파일 경로 (파일 탐색기에서 Shift+오른쪽 클릭 → "경로로 복사" 후 붙여넣기)' }
$IsoPath = $IsoPath.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) { Fail "파일을 찾을 수 없습니다: $IsoPath" }
$IsoPath = (Resolve-Path -LiteralPath $IsoPath).ProviderPath
$isoSize = (Get-Item -LiteralPath $IsoPath).Length
$img = Get-DiskImage -ImagePath $IsoPath
if (-not $img.Attached) { $img = Mount-DiskImage -ImagePath $IsoPath -PassThru; $script:MountedIso = $IsoPath }
$isoLetter = $null
for ($i = 0; $i -lt 20 -and -not $isoLetter; $i++) {
    $v = Get-DiskImage -ImagePath $IsoPath | Get-Volume -ErrorAction SilentlyContinue
    if ($v -and $v.DriveLetter) { $isoLetter = [string]$v.DriveLetter } else { Start-Sleep -Milliseconds 500 }
}
if (-not $isoLetter) { Fail 'ISO를 열었지만 드라이브 문자가 없습니다.' }
$IsoRoot = "${isoLetter}:\"
$need = @('arch\boot\x86_64\vmlinuz-linux-surface', 'arch\boot\x86_64\initramfs-linux-surface.img',
          'arch\x86_64\airootfs.sfs', 'EFI\BOOT\BOOTx64.EFI')
foreach ($f in $need) {
    if (-not (Test-Path -LiteralPath (Join-Path $IsoRoot $f))) { Fail "SUFUN ISO가 아닙니다 ($f 없음)." }
}
$efiText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $IsoRoot 'EFI\BOOT\BOOTx64.EFI')))
if (-not $efiText.Contains('systemd-boot')) { Fail '이 ISO의 부팅 프로그램이 systemd-boot가 아닙니다. 최신 SUFUN ISO를 쓰세요.' }
$isoFiles = @(Get-ChildItem -LiteralPath $IsoRoot -Recurse -File -Force)
$isoBytes = [int64]($isoFiles | Measure-Object -Property Length -Sum).Sum
$bigFile  = [int64]($isoFiles | Measure-Object -Property Length -Maximum).Maximum
Ok "ISO: $IsoPath  ($(Fmt-GB $isoBytes), 드라이브 ${isoLetter}:)"

# ---------------------------------------------------------------- the card
Step 'microSD 카드 찾기'
$cards = @(Get-CardDisks)
if ($cards.Count -eq 0) { Fail 'microSD 카드를 찾을 수 없습니다. 카드를 끝까지 넣고 파일 탐색기에 보이는지 확인하세요.' }
$isoDisk = $null
try { $isoDisk = (Get-Partition -DriveLetter $IsoPath.Substring(0, 1) -ErrorAction Stop).DiskNumber } catch {}
$card = $null
$case = 'a'
foreach ($d in $cards) { if ($null -ne $isoDisk -and $d.Number -eq $isoDisk) { $card = $d; $case = 'b' } }
if (-not $card) {
    if ($cards.Count -eq 1) { $card = $cards[0] }
    else {
        foreach ($d in $cards) { Show-Disk $d }
        $n = Read-Host '    카드로 쓸 디스크 번호'
        $card = $cards | Where-Object { "$($_.Number)" -eq $n.Trim() } | Select-Object -First 1
        if (-not $card) { Fail '그 번호의 카드가 없습니다.' }
    }
}
Show-Disk $card
$winPart = Get-WindowsPartition
if ($card.Number -eq $winPart.DiskNumber -or $card.IsBoot -or $card.IsSystem) { Fail '이 디스크에는 Windows가 있습니다. 카드로 쓸 수 없습니다.' }

if ($case -eq 'a') {
    # ---- (a) format the card: live partition at the front, rest left free ----
    $liveMB = [int][Math]::Ceiling(($isoBytes + 1GB) / 512MB) * 512
    if ($liveMB -lt 4096) { $liveMB = 4096 }
    if ($card.Size -lt ($liveMB * 1MB + 256MB)) { Fail "카드가 너무 작습니다 ($(Fmt-GB $card.Size)). 최소 $([Math]::Ceiling($liveMB / 1024) + 1) GB 필요." }
    $fs = if ($bigFile -ge 4GB) { 'exfat' } else { 'fat32' }
    Step "카드 포맷 (경우 a: ISO가 카드 밖에 있음)"
    Warn "    카드(디스크 $($card.Number), $(Fmt-GB $card.Size))의 모든 데이터가 지워집니다."
    Say  "    앞부분 $([Math]::Round($liveMB / 1024, 1)) GB = SUFUN 라이브 ($($fs.ToUpper()), 이름 $LiveLabel), 나머지 = 빈 공간 (나중에 'SD카드에 설치' 용)"
    Ask-Word 'YES' '    이 카드를 포맷하려면 YES 를 입력하세요'
    $dp = Join-Path $env:TEMP 'sufun-diskpart.txt'
    Set-Content -LiteralPath $dp -Encoding ASCII -Value @(
        "select disk $($card.Number)", 'clean', 'convert mbr',
        "create partition primary size=$liveMB", "format quick fs=$fs label=$LiveLabel", 'assign')
    $r = Run-Native 'diskpart.exe' @('/s', $dp)
    Remove-Item -LiteralPath $dp -Force
    if ($r.Code -ne 0) { Fail "카드를 포맷하지 못했습니다 (diskpart):`n$($r.Out)" }
    Update-HostStorageCache
    $cardPart = Get-Partition -DiskNumber $card.Number | Where-Object { $_.Size -gt 1GB } | Select-Object -First 1
    if (-not $cardPart) { Fail '포맷한 카드 파티션을 찾을 수 없습니다.' }
    $cardLetter = Use-Letter $cardPart
    Ok "카드 파티션: ${cardLetter}: ($(Fmt-GB $cardPart.Size))"
} else {
    # ---- (b) the ISO is on the card: no format, extract next to it ----
    Step '경우 b: ISO가 카드에 있음 → 포맷하지 않고 같은 카드에 풉니다'
    $cardLetter = $IsoPath.Substring(0, 1).ToUpper()
    $cv = Get-Volume -DriveLetter $cardLetter
    if ($cv.FileSystem -notin @('FAT32', 'exFAT')) {
        Fail "카드 파일 시스템이 $($cv.FileSystem) 입니다. SUFUN은 FAT32 또는 exFAT 카드에서만 켜집니다. ISO를 다른 곳에 두고 다시 실행하면 카드를 알맞게 포맷합니다."
    }
    if ($bigFile -ge 4GB -and $cv.FileSystem -eq 'FAT32') { Fail 'ISO에 4 GB보다 큰 파일이 있어 FAT32 카드에 넣을 수 없습니다 (exFAT 필요).' }
    $have = [int64]$cv.SizeRemaining + (Get-FolderBytes "${cardLetter}:\arch")
    if ($have -lt $isoBytes + 256MB) {
        Fail "카드에 빈 공간이 부족합니다: $(Fmt-GB $have) 남음, $(Fmt-GB ($isoBytes + 256MB)) 필요."
    }
    Say "    카드: ${cardLetter}: ($($cv.FileSystem), 빈 공간 $(Fmt-GB $cv.SizeRemaining))"
    Say '    참고: 카드 전체가 한 파티션이라 나중에 "SD카드에 설치"는 할 수 없습니다'
    Say '          (라이브 실행과 "내부 저장장치에 설치"는 됩니다).'
    Ask-Word 'YES' '    계속하려면 YES 를 입력하세요'
    $cardPart = Get-Partition -DriveLetter $cardLetter
}

Step "SUFUN 라이브 파일을 카드(${cardLetter}:)에 복사 (몇 분 걸립니다)"
# robocopy: exit codes 0-7 = success, 8 or more = error
$r = Run-Native 'robocopy.exe' @($IsoRoot, "${cardLetter}:\", '/E', '/R:2', '/W:2', '/NFL', '/NDL', '/NP', '/NJH', '/A-:R')
Say $r.Out.Trim()
$rc = $r.Code
if ($rc -ge 8) { Fail "복사하지 못했습니다 (robocopy 코드 $rc). 카드가 손상되었거나 공간이 부족할 수 있습니다." }
if (-not (Test-Path -LiteralPath "${cardLetter}:\arch\x86_64\airootfs.sfs")) { Fail '복사한 파일을 카드에서 찾을 수 없습니다.' }
$cardSfs = (Get-Item -LiteralPath "${cardLetter}:\arch\x86_64\airootfs.sfs").Length
if ($cardSfs -ne (Get-Item -LiteralPath (Join-Path $IsoRoot 'arch\x86_64\airootfs.sfs')).Length) { Fail '카드의 airootfs.sfs 크기가 ISO와 다릅니다 (복사 실패).' }
$CardUuid = Get-FatUuid $cardLetter
Ok "카드 UUID: $CardUuid (Linux가 이 번호로 카드를 찾습니다)"

# ---------------------------------------------------------------- boot stage
$kernel = Join-Path $IsoRoot 'arch\boot\x86_64\vmlinuz-linux-surface'
$initrd = Join-Path $IsoRoot 'arch\boot\x86_64\initramfs-linux-surface.img'
$ucode  = Join-Path $IsoRoot 'arch\boot\intel-ucode.img'
$sdboot = Join-Path $IsoRoot 'EFI\BOOT\BOOTx64.EFI'
$liveBytes = (Get-Item $kernel).Length + (Get-Item $initrd).Length + (Get-Item $sdboot).Length
if (Test-Path -LiteralPath $ucode) { $liveBytes += (Get-Item $ucode).Length }
# Room for the kernel copies of a later "SD카드에 설치" (kernel + initramfs + microcode)
$needBytes = $liveBytes + 120MB

Step '내부 저장장치의 부팅 단계 위치 정하기'
$st = Read-State
$mode = $null
$l = Mount-Esp
$espFree = [int64]([IO.DriveInfo]"${l}:\").AvailableFreeSpace + (Get-FolderBytes "${l}:\EFI\SUFUN")
$foreignLoader = (Test-Path -LiteralPath "${l}:\loader") -and -not (Test-Path -LiteralPath "${l}:\loader\sufun-owned.txt")
Say "    EFI 시스템 파티션: 빈 공간 $([Math]::Round($espFree / 1MB)) MB, 필요 $([Math]::Round($needBytes / 1MB)) MB"
if ($espFree -ge $needBytes -and -not $foreignLoader -and -not ($st.ContainsKey('Mode') -and $st['Mode'] -eq 'partition')) {
    $mode = 'esp'
    $bl = $l
    Ok 'EFI 시스템 파티션의 \EFI\SUFUN 에 넣습니다.'
} else {
    Dismount-Esp
    $mode = 'partition'
    if ($foreignLoader) { Say '    EFI 시스템 파티션에 다른 systemd-boot(\loader)가 있어 건드리지 않습니다.' }
    $wp = Get-WindowsPartition
    $wDisk = Get-Disk -Number $wp.DiskNumber
    $existing = @(Get-BootPartitions $wp.DiskNumber)
    if ($existing.Count -gt 0) {
        $bp = $existing[0]
        Ok "이미 있는 '$BootPartLabel' 파티션을 다시 씁니다."
    } else {
        if ("$($wDisk.PartitionStyle)" -ne 'GPT') { Fail 'Windows 디스크가 GPT가 아닙니다.' }
        $partBytes = [int64]$BootPartMB * 1MB
        $newSize = [int64]([Math]::Floor(($wp.Size - $partBytes - 1MB) / 1MB)) * 1MB
        $sup = Get-PartitionSupportedSize -DiskNumber $wp.DiskNumber -PartitionNumber $wp.PartitionNumber
        Say "    EFI 시스템 파티션이 작아서 Windows 파티션을 $BootPartMB MB 줄이고 FAT32 파티션 '$BootPartLabel' 를 만듭니다."
        if ($newSize -lt [int64]$sup.SizeMin) {
            Fail "Windows 파티션을 줄일 수 없습니다 (최소 크기 $(Fmt-GB $sup.SizeMin)). C: 에서 파일을 지우거나 '디스크 정리'를 한 뒤 다시 하세요."
        }
        Ask-Word 'YES' "    Windows 파티션을 $(Fmt-GB $wp.Size) → $(Fmt-GB $newSize) 로 줄이려면 YES 를 입력하세요"
        $st['WindowsSizeBefore'] = [string][int64]$wp.Size
        Resize-Partition -DiskNumber $wp.DiskNumber -PartitionNumber $wp.PartitionNumber -Size $newSize
        $bp = New-Partition -DiskNumber $wp.DiskNumber -Offset ($wp.Offset + $newSize) -Size $partBytes -GptType $BasicDataGuid
        Format-Volume -Partition $bp -FileSystem FAT32 -NewFileSystemLabel $BootPartLabel -Confirm:$false -Force | Out-Null
        $bp = Get-Partition -DiskNumber $bp.DiskNumber -PartitionNumber $bp.PartitionNumber
        Ok "만듦: 디스크 $($bp.DiskNumber) 파티션 $($bp.PartitionNumber) ($(Fmt-GB $bp.Size), FAT32 '$BootPartLabel')"
    }
    $bl = Use-Letter $bp
    # No drive letter in Explorer after this script (so nobody deletes it by accident)
    Set-Partition -DiskNumber $bp.DiskNumber -PartitionNumber $bp.PartitionNumber -NoDefaultDriveLetter $true
}

Step "부팅 파일 복사 (${bl}:\EFI\SUFUN)"
$B = "${bl}:\"
New-Item -ItemType Directory -Force -Path "${B}EFI\SUFUN\live", "${B}loader\entries" | Out-Null
Copy-Item -LiteralPath $sdboot -Destination "${B}EFI\SUFUN\systemd-bootx64.efi" -Force
Copy-Item -LiteralPath $kernel, $initrd -Destination "${B}EFI\SUFUN\live\" -Force
$initrdLines = @()
if (Test-Path -LiteralPath $ucode) {
    Copy-Item -LiteralPath $ucode -Destination "${B}EFI\SUFUN\live\" -Force
    $initrdLines += 'initrd  /EFI/SUFUN/live/intel-ucode.img'
}
$initrdLines += 'initrd  /EFI/SUFUN/live/initramfs-linux-surface.img'
Write-Unix "${B}loader\sufun-owned.txt" @('This loader folder was made by SUFUN (sufun-sd-setup.ps1). -Uninstall removes it.')
Write-Unix "${B}loader\entries\sufun-live.conf" (@(
    'title   SUFUN Live (microSD)',
    'linux   /EFI/SUFUN/live/vmlinuz-linux-surface') + $initrdLines + @(
    "options archisobasedir=arch archisodevice=/dev/disk/by-uuid/$CardUuid copytoram=n"))
if ($case -eq 'a' -and (Test-Path -LiteralPath "${B}loader\entries\sufun-sd.conf")) {
    # The card was formatted: an older "SD카드에 설치" on it is gone.
    Remove-Item -LiteralPath "${B}loader\entries\sufun-sd.conf", "${B}loader\entries\sufun-sd-fallback.conf" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "${B}EFI\SUFUN\sd" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "${B}loader\loader.conf" -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path -LiteralPath "${B}loader\loader.conf")) {
    Write-Unix "${B}loader\loader.conf" @('default sufun-live.conf', 'timeout 4', 'console-mode keep', 'editor no')
}
foreach ($f in @('EFI\SUFUN\systemd-bootx64.efi', 'EFI\SUFUN\live\vmlinuz-linux-surface', 'EFI\SUFUN\live\initramfs-linux-surface.img')) {
    if (-not (Test-Path -LiteralPath "$B$f")) { Fail "$B$f 을(를) 쓰지 못했습니다." }
}
Ok '복사 완료'

# ---------------------------------------------------------------- firmware entry
$bcdId = ''
if ($Ci) {
    Step "펌웨어 부팅 항목 '$EntryName' (테스트 모드: 만들지 않음)"
    Say "    실제로는: bcdedit /copy {bootmgr} /d `"$EntryName`"; path \EFI\SUFUN\systemd-bootx64.efi; device partition=${bl}:; {fwbootmgr} displayorder /addlast"
} else {
    Step "펌웨어 부팅 항목 '$EntryName' 추가 (Windows가 계속 기본)"
    if ($st.ContainsKey('BcdId')) {
        $r = Run-Native 'bcdedit.exe' @('/enum', $st['BcdId'])
        if ($r.Code -eq 0 -and $r.Out.Contains($EntryName)) { $bcdId = $st['BcdId'] }
    }
    if (-not $bcdId) {
        $o = Invoke-Native 'bcdedit.exe' @('/copy', '{bootmgr}', '/d', $EntryName) '부팅 항목 만들기 (bcdedit /copy)'
        if ($o -notmatch '\{[0-9a-fA-F-]{36}\}') { Fail "새 부팅 항목의 ID를 읽을 수 없습니다: $o" }
        $bcdId = $Matches[0]
    }
    Invoke-Native 'bcdedit.exe' @('/set', $bcdId, 'device', "partition=${bl}:") '부팅 항목 장치 설정' | Out-Null
    Invoke-Native 'bcdedit.exe' @('/set', $bcdId, 'path', '\EFI\SUFUN\systemd-bootx64.efi') '부팅 항목 경로 설정' | Out-Null
    Invoke-Native 'bcdedit.exe' @('/set', '{fwbootmgr}', 'displayorder', $bcdId, '/addlast') '부팅 순서에 추가' | Out-Null
    $fw = (Run-Native 'bcdedit.exe' @('/enum', 'firmware')).Out
    if (-not $fw.Contains($bcdId)) { Fail '펌웨어 부팅 목록에 새 항목이 없습니다.' }
    Ok "부팅 항목 $bcdId (부팅 순서 맨 끝, Windows Boot Manager가 기본)"
}

# ---------------------------------------------------------------- save, finish
$st['Version'] = '1'
$st['Mode'] = $mode
$st['Case'] = $case
$st['CardUuid'] = $CardUuid
$st['BcdId'] = $bcdId
$st['Date'] = (Get-Date -Format 'yyyy-MM-dd HH:mm')
if ($mode -eq 'partition') { $st['BootPartitionGuid'] = "$($bp.Guid)" }
Save-State $st "${B}EFI\SUFUN\sd-setup.txt"
if ($mode -eq 'esp') { Dismount-Esp }

if ($case -eq 'b' -and $script:MountedIso) {
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null; $script:MountedIso = $null
}
Cleanup
if ($case -eq 'b') {
    if (Ask-YesNo "    카드의 ISO 파일($(Fmt-GB $isoSize))을 지워 공간을 늘릴까요? (라이브에는 필요 없음)" $true) {
        Remove-Item -LiteralPath $IsoPath -Force
        Ok "ISO 파일을 지웠습니다."
    }
}

Write-Host ''
Write-Host '=== 준비 완료 ===' -ForegroundColor Green
Say '카드를 꽂은 채로 SUFUN을 켜는 방법 (Windows는 그대로 기본입니다):'
Say '  방법 1) 설정 → 시스템 → 복구 → 고급 시작 "지금 다시 시작" → 장치 사용 → "SUFUN (SD)"'
Say '  방법 2) 전원을 끄고 볼륨 위(+) + 전원 → Surface UEFI → Boot configuration →'
Say '          "SUFUN (SD)" 를 왼쪽으로 밀기(swipe) = 지금 한 번 부팅'
Say '부팅 메뉴(검은 화면)에서 "SUFUN Live (microSD)" 를 고르면 됩니다.'
Say '모두 되돌리려면: 이 스크립트를 -Uninstall 로 실행하세요.'
Pause-End
exit 0
