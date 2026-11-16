# Guest half of fold-installeer.sh (run elevated; files in C:\Users\Public\fold-install).
#   -Actie voorbereiden -Delen umd,kmd   copy the current versions to vorige\, write pending.json (boots 0)
#   -Actie installeer                    put nieuw\* in place (loaded files are renamed first, active after a restart)
#   -Actie terug [-Reden x]              restore vorige\* for the parts in pending.json (or laatste.json)
#   -Actie bevestig                      install is healthy: pending.json -> laatste.json
#   -Actie wacht                         boot watchdog (task fold-install-wacht, at startup as SYSTEM): third boot
#                                        with an unconfirmed install -> terug + restart
param([string]$Actie, [string]$Delen = '', [string]$Reden = 'handmatig')
$ErrorActionPreference = 'Stop'
$D = 'C:\Users\Public\fold-install'; $V = "$D\vorige"; $N = "$D\nieuw"
$PendPad = "$D\pending.json"; $LaatstPad = "$D\laatste.json"; $log = "$D\install.log"
$k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000'
$store = Split-Path ((Get-ItemProperty $k).UserModeDriverName | ?{ $_ -like '*neptune_umd.dll' } | Select -First 1)
$kmd = 'C:\Windows\System32\drivers\DroidVM\viogpu3d-nativejob.sys'
# NB: PowerShell variable names ignore case: never reuse $d/$p/$l etc. for something else.
# part -> list of (installed path, file name in vorige\ and nieuw\)
$map = @{
  umd = @(@("$store\neptune_umd.dll", 'neptune_umd.dll'), @("$store\neptune_umd_arm64.dll", 'neptune_umd.dll'),
          @("$store\neptune_umd_ec.dll", 'neptune_umd_ec.dll'))
  kmd = @(,@($kmd, 'viogpu3d-nativejob.sys'))   # leading comma: keep the single pair an array of arrays
}
function Log($m) { $l = "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') $Actie $m"; Add-Content $log $l; $l }
function Hash8($f) { (Get-FileHash $f).Hash.Substring(0, 8) }
function Plaats($bron, $doel) {   # replace a (possibly loaded) file: rename the old one, copy the new one
  if (Test-Path $doel) { $oud = "$doel.oud-$(Get-Date -f yyyyMMddHHmmss)"; Rename-Item $doel (Split-Path $oud -Leaf) }
  Copy-Item $bron $doel
  Get-ChildItem "$doel.oud-*" | Sort LastWriteTime -Descending | Select -Skip 2 | Remove-Item -EA 0   # keep two
}
New-Item -ItemType Directory -Force $D, $V, $N | Out-Null
switch ($Actie) {
  'voorbereiden' {
    if (Test-Path $PendPad) { throw "er loopt al een installatie ($PendPad); eerst bevestig of terug" }
    $lijst = @("$Delen" -split '[, ]+' | ?{ $_ -in 'umd','kmd' })
    foreach ($deel in $lijst) { foreach ($e in $map[$deel]) { Copy-Item $e[0] "$V\$($e[1])" -Force } }
    @{ delen = $lijst; boots = 0; tijd = (Get-Date -f s) } | ConvertTo-Json | Set-Content $PendPad
    # crosvm-only installs get a pending.json too (no guest parts): the watchdog then only counts boots
    $s = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File $D\fold-install.ps1 -Actie wacht"
    Register-ScheduledTask fold-install-wacht -Action $s -Trigger (New-ScheduledTaskTrigger -AtStartup) -User SYSTEM -RunLevel Highest -Force | Out-Null
    Log "delen=$($lijst -join ',') vorige: $((Get-ChildItem $V | % { $_.Name + '=' + (Hash8 $_.FullName) }) -join ' ')" }
  'installeer' {
    $st = Get-Content $PendPad -Raw | ConvertFrom-Json
    foreach ($deel in $st.delen) { foreach ($e in $map[$deel]) {
      if (-not (Test-Path "$N\$($e[1])")) { throw "nieuw\$($e[1]) ontbreekt" }
      Plaats "$N\$($e[1])" $e[0] } }
    Log "geplaatst: $(($st.delen | % { $map[$_] } | % { (Split-Path $_[0] -Leaf) + '=' + (Hash8 $_[0]) }) -join ' ')" }
  'terug' {
    $bron = if (Test-Path $PendPad) { $PendPad } elseif (Test-Path $LaatstPad) { $LaatstPad } else { throw 'geen installatie om terug te zetten' }
    $st = Get-Content $bron -Raw | ConvertFrom-Json
    foreach ($deel in $st.delen) { foreach ($e in $map[$deel]) { Plaats "$V\$($e[1])" $e[0] } }
    Remove-Item $PendPad -EA 0
    Log "reden=$Reden teruggezet: $(($st.delen | % { $map[$_] } | % { (Split-Path $_[0] -Leaf) + '=' + (Hash8 $_[0]) }) -join ' ')" }
  'bevestig' { if (Test-Path $PendPad) { Move-Item $PendPad $LaatstPad -Force }; Log 'gezond, bevestigd' }
  'wacht' {
    if (-not (Test-Path $PendPad)) { return }
    $st = Get-Content $PendPad -Raw | ConvertFrom-Json; $st.boots++; $st | ConvertTo-Json | Set-Content $PendPad
    Log "boot $($st.boots) zonder bevestiging"
    if ($st.boots -ge 3) { & $PSCommandPath -Actie terug -Reden waakhond; shutdown /r /t 5 /c 'fold-install: terug naar de vorige versie' } }
  default { throw 'Actie: voorbereiden|installeer|terug|bevestig|wacht' }
}
