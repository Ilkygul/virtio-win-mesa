# Fold / DroidVM: switch the Windows guest to the legacy GPU route with DWM write-sync off (register D2-D5,
# 15 Nov 2026): drag/scroll 55-59 fps, YouTube 1080p60 1.4% drops, no white/magenta. Drivers stay the same
# (C46 UMD / F91 KMD / C37 host / C33 DXVK from release fold-retained-c46-c37-c33-20261115-r1).
# Run elevated in the guest. Restart Windows afterwards (NativeGpuJobV1 is read by the KMD at boot).
#   legacy-route.ps1          legacy route, DWM-sync and Present-sync off
#   legacy-route.ps1 -Terug   back to Native1 (NativeGpuJobV1=1, runtime marker on, DWM- and Present-sync on)
param([switch]$Terug)
$p = 'HKLM:\SYSTEM\CurrentControlSet\Services\VioGpu3D\Parameters'
$m = 'C:\Users\Public'
function Marker($name, [bool]$on) {
    $f = "$m\$name"; $off = "$f.uit"
    if ($on) { if (Test-Path $off) { Rename-Item $off $name } elseif (-not (Test-Path $f)) { New-Item $f -ItemType File | Out-Null } }
    else { if (Test-Path $f) { Remove-Item $off -EA 0; Rename-Item $f "$name.uit" } }
}
New-Item $p -Force | Out-Null
Set-ItemProperty $p NativeGpuJobV1 ([int][bool]$Terug) -Type DWord
Marker triton-runtimestream $Terug
Marker triton-dwmwritesync $Terug
Marker triton-presentwritesync $Terug   # off since K4: 4K60 drops 23.7% -> 2.0%
"NativeGpuJobV1=$((Get-ItemProperty $p).NativeGpuJobV1); markers: " + ((Get-ChildItem "$m\triton-*").Name -join ', ')
"Herstart Windows om de route te wisselen."
