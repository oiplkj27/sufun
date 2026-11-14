# CI test of scripts/windows/sufun-sd-setup.ps1 on a GitHub Windows runner.
# Only virtual disks (VHDX files) are used; the runner's own disks and boot
# entries are never touched (the setup script's CI mode refuses anything that is
# not a virtual disk and does not create firmware boot entries).
#
#   -Phase setup      S1: card case (a), boot stage in the "EFI partition"   -> kept for the QEMU test
#                     S2: card case (b) (ISO on the card), EFI partition too small
#                         -> "Windows" partition shrunk + SUFUNBOOT partition; then -Uninstall
#   -Phase uninstall  S1 again: -Uninstall removes \EFI\SUFUN and \loader
#
# Not testable here: bcdedit / the UEFI firmware entry "SUFUN (SD)", Secure Boot and
# BitLocker checks (the runner is a VM without them), a real SD card reader.
param(
    [Parameter(Mandatory)] [ValidateSet('setup', 'uninstall')] [string]$Phase,
    [Parameter(Mandatory)] [string]$Work,
    [string]$Iso
)
$ErrorActionPreference = 'Stop'
$env:SUFUN_CI_TEST = '1'
$Setup = Join-Path $PSScriptRoot '..\windows\sufun-sd-setup.ps1'
$script:failed = $false
New-Item -ItemType Directory -Force -Path $Work | Out-Null

function Check([string]$name, [bool]$ok, [string]$info = '') {
    if ($ok) { Write-Host "PASS $name $info" -ForegroundColor Green }
    else { Write-Host "FAIL $name $info" -ForegroundColor Red; $script:failed = $true }
}
function DiskPart([string[]]$lines) {
    $f = Join-Path $Work 'dp.txt'
    Set-Content -LiteralPath $f -Value $lines -Encoding ASCII
    $o = & diskpart.exe /s $f | Out-String
    if ($LASTEXITCODE -ne 0) { throw "diskpart failed:`n$o" }
}
function DiskOf([string]$vhd) { return (Get-DiskImage -ImagePath $vhd | Get-Disk).Number }
function Run-Setup([string[]]$argv) {
    Write-Host "---- sufun-sd-setup.ps1 $($argv -join ' ')" -ForegroundColor Cyan
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Setup @argv | Out-Host
    return $LASTEXITCODE
}
function Letter-Of([string]$label, [string]$want) {
    # makes sure the volume with this label has drive letter $want
    $v = Get-Volume -FileSystemLabel $label
    $p = Get-Partition -Volume $v
    if ("$($p.DriveLetter)" -ne $want) { Set-Partition -InputObject $p -NewDriveLetter $want }
}
function Volume-Serial([string]$letter) {
    $h = '{0:X8}' -f ([uint32](Get-CimInstance Win32_Volume -Filter "DriveLetter='${letter}:'").SerialNumber)
    return $h.Substring(0, 4) + '-' + $h.Substring(4, 4)
}
$state = Join-Path $env:ProgramData 'SUFUN\sd-setup.txt'
$int1 = Join-Path $Work 'internal.vhdx'; $card1 = Join-Path $Work 'card.vhdx'
$int2 = Join-Path $Work 'internal2.vhdx'; $card2 = Join-Path $Work 'card2.vhdx'

if ($Phase -eq 'setup') {
    $Iso = (Resolve-Path $Iso).ProviderPath
    # ---- S1 disks: internal (GPT: 500 MB "EFI" + NTFS "Windows"), card 32 GiB (empty)
    DiskPart @("create vdisk file=`"$int1`" maximum=2048 type=expandable", 'attach vdisk', 'convert gpt',
               'create partition primary size=500', 'format quick fs=fat32 label=ESPTEST1', 'assign letter=S',
               'create partition primary size=1200', 'format quick fs=ntfs label=WINTEST1', 'assign letter=W',
               "create vdisk file=`"$card1`" maximum=32768 type=expandable", 'attach vdisk')
    Set-Content -LiteralPath 'W:\windows-test.txt' -Value 'pretend Windows'
    $wBefore = (Get-Partition -DriveLetter W).Size
    $rc = Run-Setup @('-IsoPath', $Iso, '-CiCardDisk', (DiskOf $card1), '-CiEspLetter', 'S', '-CiWindowsLetter', 'W')
    Check 's1-exit-code' ($rc -eq 0) "($rc)"
    $cardParts = @(Get-Partition -DiskNumber (DiskOf $card1) | Where-Object { $_.Size -gt 1GB })
    Check 's1-card-one-live-partition' ($cardParts.Count -eq 1) "($($cardParts.Count))"
    $cd = Get-Disk -Number (DiskOf $card1)
    $free = $cd.Size - ($cardParts | Measure-Object Size -Sum).Sum
    Check 's1-card-free-space-for-sd-install' ($free -gt 20GB) ("({0:N1} GB)" -f ($free / 1GB))
    $cl = "$($cardParts[0].DriveLetter)"
    Check 's1-card-files' (Test-Path "${cl}:\arch\x86_64\airootfs.sfs")
    Check 's1-card-fat32' ((Get-Volume -DriveLetter $cl).FileSystem -eq 'FAT32')
    Check 's1-card-label' ((Get-Volume -DriveLetter $cl).FileSystemLabel -eq 'SUFUNLIVE')
    Check 's1-boot-menu' (Test-Path 'S:\EFI\SUFUN\systemd-bootx64.efi')
    Check 's1-kernel' ((Test-Path 'S:\EFI\SUFUN\live\vmlinuz-linux-surface') -and (Test-Path 'S:\EFI\SUFUN\live\initramfs-linux-surface.img'))
    $entry = Get-Content -Raw 'S:\loader\entries\sufun-live.conf'
    $uuid = Volume-Serial $cl
    Check 's1-entry-uuid' ($entry.Contains("archisodevice=/dev/disk/by-uuid/$uuid")) "($uuid)"
    Check 's1-entry-lf' (-not $entry.Contains("`r"))
    Check 's1-entry-splash' ($entry -match 'options .* quiet splash')
    $text = Get-Content -Raw 'S:\loader\entries\sufun-text.conf'
    Check 's1-text-mode-entry' ($text.Contains('text mode') -and $text.Contains("by-uuid/$uuid") -and -not $text.Contains('splash'))
    Check 's1-loader-conf' ((Get-Content -Raw 'S:\loader\loader.conf').Contains('default sufun-live.conf'))
    Check 's1-windows-untouched' (((Get-Partition -DriveLetter W).Size -eq $wBefore) -and (Test-Path 'W:\windows-test.txt'))
    Check 's1-state' ((Get-Content -Raw $state) -match 'Mode=esp' -and (Get-Content -Raw $state) -match 'Case=a')
    Move-Item -Force $state (Join-Path $Work 's1-state.txt')

    # ---- safety: the script must refuse a non-virtual (real) disk in CI mode
    $real = (Get-Partition -DriveLetter ($env:SystemDrive.Substring(0, 1))).DiskNumber
    $rc = Run-Setup @('-IsoPath', $Iso, '-CiCardDisk', $real, '-CiEspLetter', 'S', '-CiWindowsLetter', 'W')
    Check 'refuses-real-disk' ($rc -ne 0) "($rc)"

    # ---- S2 disks: internal (100 MB "EFI" + 3 GB NTFS), card 8 GiB FAT32 holding the ISO
    DiskPart @("create vdisk file=`"$int2`" maximum=4096 type=expandable", 'attach vdisk', 'convert gpt',
               'create partition primary size=100', 'format quick fs=fat32 label=ESPTEST2', 'assign letter=T',
               'create partition primary size=3000', 'format quick fs=ntfs label=WINTEST2', 'assign letter=V',
               "create vdisk file=`"$card2`" maximum=8192 type=expandable", 'attach vdisk', 'convert mbr',
               'create partition primary', 'format quick fs=fat32 label=CARD2', 'assign letter=K')
    Copy-Item -LiteralPath $Iso -Destination 'K:\sufun.iso'
    $vBefore = (Get-Partition -DriveLetter V).Size
    $rc = Run-Setup @('-IsoPath', 'K:\sufun.iso', '-CiCardDisk', (DiskOf $card2), '-CiEspLetter', 'T', '-CiWindowsLetter', 'V')
    Check 's2-exit-code' ($rc -eq 0) "($rc)"
    Check 's2-extracted-in-place' (Test-Path 'K:\arch\x86_64\airootfs.sfs')
    Check 's2-iso-deleted' (-not (Test-Path 'K:\sufun.iso'))
    Check 's2-not-in-small-esp' (-not (Test-Path 'T:\EFI\SUFUN'))
    $vAfter = (Get-Partition -DriveLetter V).Size
    Check 's2-windows-shrunk' ($vAfter -lt $vBefore - 1000MB) ("({0} -> {1} MB)" -f ($vBefore / 1MB), ($vAfter / 1MB))
    $bp = @(Get-Partition -DiskNumber (DiskOf $int2) | Where-Object { (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -eq 'SUFUNBOOT' })
    Check 's2-bootpart' ($bp.Count -eq 1)
    if ($bp.Count -eq 1) {
        Check 's2-bootpart-no-letter' (-not "$($bp[0].DriveLetter)".Trim([char]0).Trim())
        Check 's2-bootpart-fat32' ((Get-Volume -Partition $bp[0]).FileSystem -eq 'FAT32')
        Set-Partition -InputObject $bp[0] -NewDriveLetter 'Y'
        Check 's2-bootpart-files' ((Test-Path 'Y:\EFI\SUFUN\systemd-bootx64.efi') -and (Test-Path 'Y:\loader\entries\sufun-live.conf'))
        Check 's2-entry-uuid' ((Get-Content -Raw 'Y:\loader\entries\sufun-live.conf').Contains("by-uuid/$(Volume-Serial 'K')"))
        Remove-PartitionAccessPath -InputObject (Get-Partition -DriveLetter Y) -AccessPath 'Y:\'
    }
    Check 's2-state' ((Get-Content -Raw $state) -match 'Mode=partition' -and (Get-Content -Raw $state) -match 'Case=b')

    $rc = Run-Setup @('-Uninstall', '-CiCardDisk', (DiskOf $card2), '-CiEspLetter', 'T', '-CiWindowsLetter', 'V')
    Check 's2-uninstall-exit-code' ($rc -eq 0) "($rc)"
    $bp = @(Get-Partition -DiskNumber (DiskOf $int2) | Where-Object { (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -eq 'SUFUNBOOT' })
    Check 's2-uninstall-bootpart-gone' ($bp.Count -eq 0)
    Check 's2-uninstall-windows-size-back' ((Get-Partition -DriveLetter V).Size -eq $vBefore) ("({0} MB)" -f ((Get-Partition -DriveLetter V).Size / 1MB))
    Check 's2-uninstall-state-gone' (-not (Test-Path $state))
    Check 's2-uninstall-card-kept' (Test-Path 'K:\arch\x86_64\airootfs.sfs')

    # S1 disks are detached for the QEMU test (uploaded as an artifact next)
    Set-Content -LiteralPath (Join-Path $Work 's1-windows-size.txt') -Value $wBefore
    DiskPart @("select vdisk file=`"$int1`"", 'detach vdisk', "select vdisk file=`"$card1`"", 'detach vdisk',
               "select vdisk file=`"$int2`"", 'detach vdisk', "select vdisk file=`"$card2`"", 'detach vdisk')
    Remove-Item -Force $int2, $card2
} else {
    # ---- S1 -Uninstall (after the disks were uploaded)
    DiskPart @("select vdisk file=`"$int1`"", 'attach vdisk', "select vdisk file=`"$card1`"", 'attach vdisk')
    Start-Sleep -Seconds 3
    Letter-Of 'ESPTEST1' 'S'; Letter-Of 'WINTEST1' 'W'
    Copy-Item (Join-Path $Work 's1-state.txt') $state -Force
    $rc = Run-Setup @('-Uninstall', '-CiCardDisk', (DiskOf $card1), '-CiEspLetter', 'S', '-CiWindowsLetter', 'W')
    Check 's1-uninstall-exit-code' ($rc -eq 0) "($rc)"
    Check 's1-uninstall-efi-sufun-gone' (-not (Test-Path 'S:\EFI\SUFUN'))
    Check 's1-uninstall-loader-gone' (-not (Test-Path 'S:\loader'))
    Check 's1-uninstall-windows-same' (((Get-Partition -DriveLetter W).Size -eq [int64](Get-Content (Join-Path $Work 's1-windows-size.txt'))) -and (Test-Path 'W:\windows-test.txt'))
    Check 's1-uninstall-state-gone' (-not (Test-Path $state))
    DiskPart @("select vdisk file=`"$int1`"", 'detach vdisk', "select vdisk file=`"$card1`"", 'detach vdisk')
}

if ($script:failed) { Write-Host 'WINDOWS SD SETUP TEST FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'WINDOWS SD SETUP TEST PASSED' -ForegroundColor Green
exit 0
