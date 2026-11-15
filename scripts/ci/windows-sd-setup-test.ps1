# CI test of scripts/windows/sufun-sd-setup.ps1 on a GitHub Windows runner.
# Only virtual disks (VHDX files) are used; the runner's own disks and boot
# entries are never touched (the setup script's CI mode refuses anything that is
# not a virtual disk and does not create firmware boot entries).
#
#   -Phase setup      S1: card case (a), boot stage in the "EFI partition"   -> kept for the QEMU test
#                     S2: card case (b) (ISO on the card), EFI partition too small
#                         -> "Windows" partition shrunk + SUFUNBOOT partition; then -Uninstall
#                     S3: Windows restore REHEARSAL (-RestoreRehearsal) with the dummy
#                         "Windows 11 ISO" from the build job (no Microsoft files):
#                         "Windows" partition shrunk, FAT32 WININSTALL partition right after
#                         it, ISO copied, install.wim split by DISM, firmware entry bytes
#                         -> kept for the QEMU test (it must boot, and Linux's efibootmgr
#                         must make the very same entry bytes)
#   -Phase uninstall  S1 again: -Uninstall removes \EFI\SUFUN and \loader
#                     S3 again: -Uninstall removes the rehearsal only, "Windows" gets its
#                         exact size back, the result is noted for the SUFUN installer
#
# Not testable here: bcdedit / the UEFI firmware entry "SUFUN (SD)", Secure Boot and
# BitLocker checks (the runner is a VM without them), a real SD card reader.
param(
    [Parameter(Mandatory)] [ValidateSet('setup', 'uninstall')] [string]$Phase,
    [Parameter(Mandatory)] [string]$Work,
    [string]$Iso,
    [string]$WinIso          # dummy Windows ISO (scripts/ci/make-dummy-windows-iso.sh)
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
$int3 = Join-Path $Work 'rehearsal.vhdx'
$rstate = Join-Path $env:ProgramData 'SUFUN\restore-rehearsal.txt'

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

    # ---- S3: Windows restore rehearsal. Disk: 200 MB "EFI" (with a pretend SUFUN boot
    #      stage, so the result note has a place) + 3 GB NTFS "Windows"
    $WinIso = (Resolve-Path $WinIso).ProviderPath
    DiskPart @("create vdisk file=`"$int3`" maximum=4096 type=expandable", 'attach vdisk', 'convert gpt',
               'create partition primary size=200', 'format quick fs=fat32 label=ESPTEST3', 'assign letter=R',
               'create partition primary size=3000', 'format quick fs=ntfs label=WINTEST3', 'assign letter=Q')
    Set-Content -LiteralPath 'Q:\windows-test.txt' -Value 'pretend Windows'
    New-Item -ItemType Directory -Force -Path 'R:\EFI\SUFUN' | Out-Null
    Set-Content -LiteralPath $state -Value @('Mode=esp', 'Case=a', 'Version=1')      # as after an SD setup
    $qBefore = (Get-Partition -DriveLetter Q).Size
    $fw = "$env:firmware_type"
    Write-Host "runner firmware type: '$fw'"
    # Only on a UEFI runner: really write the entry into this (throw-away) VM's firmware
    # and take it out again, to test the code that the real Surface will run.
    if ($fw -eq 'UEFI') { $env:SUFUN_CI_NVRAM = '1' }
    $bo = Join-Path $env:ProgramData 'SUFUN\ci-bootorder.txt'
    Remove-Item -Force $bo -ErrorAction SilentlyContinue
    $rc = Run-Setup @('-RestoreRehearsal', $WinIso, '-CiEspLetter', 'R', '-CiWindowsLetter', 'Q', '-CiSplitMB', '16')
    Check 's3-exit-code' ($rc -eq 0) "($rc)"
    $rp = @(Get-Partition -DiskNumber (DiskOf $int3) | Where-Object { (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -eq 'WININSTALL' })
    Check 's3-wininstall-partition' ($rp.Count -eq 1)
    if ($rp.Count -eq 1) {
        $q = Get-Partition -DriveLetter Q
        Check 's3-windows-shrunk' ($q.Size -lt $qBefore - 900MB) ("({0} -> {1} MB)" -f ($qBefore / 1MB), ($q.Size / 1MB))
        Check 's3-right-after-windows' (($rp[0].Offset - ($q.Offset + $q.Size)) -ge 0 -and ($rp[0].Offset - ($q.Offset + $q.Size)) -le 2MB)
        Check 's3-fat32' ((Get-Volume -Partition $rp[0]).FileSystem -eq 'FAT32')
        Check 's3-no-letter' (-not "$($rp[0].DriveLetter)".Trim([char]0).Trim())
        Check 's3-basic-data-type' ("$($rp[0].GptType)" -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}')
        Set-Partition -InputObject $rp[0] -NewDriveLetter 'Y'
        Check 's3-boot-files' ((Test-Path 'Y:\efi\boot\bootx64.efi') -and (Test-Path 'Y:\efi\microsoft\boot\bcd') -and (Test-Path 'Y:\sources\boot.wim'))
        $swm = @(Get-ChildItem 'Y:\sources' -Filter 'install*.swm')
        Check 's3-wim-split' ($swm.Count -ge 1 -and -not (Test-Path 'Y:\sources\install.wim')) "($($swm.Count) parts: $($swm.Name -join ' '))"
        Check 's3-marker-file' (Test-Path 'Y:\SUFUN-WININSTALL.txt')
        Remove-PartitionAccessPath -InputObject (Get-Partition -DriveLetter Y) -AccessPath 'Y:\'
    }
    $rs = Get-Content -Raw $rstate
    Check 's3-state' ($rs -match 'WindowsSizeBefore=\d+' -and $rs -match 'PartitionGuid=\{')
    $hex = ''; if ($rs -match 'EntryHex=([0-9a-f]+)') { $hex = $Matches[1] }
    Check 's3-entry-bytes' ($hex.Length -gt 200 -and $hex.StartsWith('01000000'))
    Set-Content -LiteralPath (Join-Path $Work 'rehearsal-entry.hex') -Value $hex -Encoding ASCII
    $method = ''; if ($rs -match 'Method=(\w+)') { $method = $Matches[1] }
    Write-Host "INFO rehearsal firmware entry method on this runner: $method"
    if ($fw -eq 'UEFI') {
        Check 's3-firmware-entry-written' ($method -eq 'nvram')
        # the setup script notes the firmware's BootOrder (hex) before and after
        $n = @{}; foreach ($l in Get-Content $bo) { if ($l -match '^(\w+)=(.*)$') { $n[$Matches[1]] = $Matches[2] } }
        Write-Host "INFO BootOrder before $($n['before']) after $($n['added']) entry Boot$($n['num'])"
        $le = $n['num'].Substring(2, 2) + $n['num'].Substring(0, 2)
        Check 's3-firmware-entry-last' ($n['added'] -eq ($n['before'] + $le.ToLower()))
        Check 's3-firmware-default-same' ($n['added'].Substring(0, 4) -eq $n['before'].Substring(0, 4))
    } else {
        Write-Host 'INFO this runner has no UEFI firmware: writing the entry could not be tested here'
    }
    Check 's3-windows-file-kept' (Test-Path 'Q:\windows-test.txt')
    Check 's3-second-run-refused' ((Run-Setup @('-RestoreRehearsal', $WinIso, '-CiEspLetter', 'R', '-CiWindowsLetter', 'Q')) -ne 0)
    Move-Item -Force $rstate (Join-Path $Work 's3-rehearsal-state.txt')
    Move-Item -Force $state (Join-Path $Work 's3-state.txt')
    Set-Content -LiteralPath (Join-Path $Work 's3-windows-size.txt') -Value $qBefore

    # S1 and S3 disks are detached for the QEMU test (uploaded as an artifact next)
    Set-Content -LiteralPath (Join-Path $Work 's1-windows-size.txt') -Value $wBefore
    DiskPart @("select vdisk file=`"$int1`"", 'detach vdisk', "select vdisk file=`"$card1`"", 'detach vdisk',
               "select vdisk file=`"$int2`"", 'detach vdisk', "select vdisk file=`"$card2`"", 'detach vdisk',
               "select vdisk file=`"$int3`"", 'detach vdisk')
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

    # ---- S3 -Uninstall: only the rehearsal goes away, "Windows" gets its exact size back
    DiskPart @("select vdisk file=`"$int3`"", 'attach vdisk')
    Start-Sleep -Seconds 3
    Letter-Of 'ESPTEST3' 'R'; Letter-Of 'WINTEST3' 'Q'
    Copy-Item (Join-Path $Work 's3-rehearsal-state.txt') $rstate -Force
    Copy-Item (Join-Path $Work 's3-state.txt') $state -Force
    if ("$env:firmware_type" -eq 'UEFI') { $env:SUFUN_CI_NVRAM = '1' }
    $rc = Run-Setup @('-Uninstall', '-CiEspLetter', 'R', '-CiWindowsLetter', 'Q')
    Check 's3-uninstall-exit-code' ($rc -eq 0) "($rc)"
    $rp = @(Get-Partition -DiskNumber (DiskOf $int3) | Where-Object { (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -eq 'WININSTALL' })
    Check 's3-uninstall-partition-gone' ($rp.Count -eq 0)
    Check 's3-uninstall-windows-size-back' ((Get-Partition -DriveLetter Q).Size -eq [int64](Get-Content (Join-Path $Work 's3-windows-size.txt'))) ("({0} MB)" -f ((Get-Partition -DriveLetter Q).Size / 1MB))
    Check 's3-uninstall-windows-file-kept' (Test-Path 'Q:\windows-test.txt')
    Check 's3-uninstall-state-gone' (-not (Test-Path $rstate))
    Check 's3-uninstall-sd-setup-kept' ((Test-Path $state) -and (Test-Path 'R:\EFI\SUFUN'))
    Check 's3-uninstall-result-noted' ((Test-Path 'R:\EFI\SUFUN\rehearsal.txt') -and (Get-Content -Raw 'R:\EFI\SUFUN\rehearsal.txt') -match 'Result=ok')
    if ("$env:firmware_type" -eq 'UEFI') {
        $n = @{}; foreach ($l in Get-Content (Join-Path $env:ProgramData 'SUFUN\ci-bootorder.txt')) { if ($l -match '^(\w+)=(.*)$') { $n[$Matches[1]] = $Matches[2] } }
        Write-Host "INFO BootOrder before $($n['before']) after removing $($n['removed'])"
        Check 's3-uninstall-boot-order-same' ($n['removed'] -and $n['removed'] -eq $n['before'])
        Check 's3-uninstall-firmware-entry-gone' ($n['gone'] -eq '1')
    }
    Remove-Item -Force $state -ErrorAction SilentlyContinue
    DiskPart @("select vdisk file=`"$int3`"", 'detach vdisk')
}

if ($script:failed) { Write-Host 'WINDOWS SD SETUP TEST FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'WINDOWS SD SETUP TEST PASSED' -ForegroundColor Green
exit 0
