#!/bin/bash
# waakhondtest.sh: install the current KMD without confirming and restart until the guest watchdog rolls back
G="ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=6 USER@127.0.0.1"
up() { $G '[int]((Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds' 2>/dev/null | tr -dc 0-9; }
$G 'Copy-Item C:\Users\Public\meet\f95.sys C:\Users\Public\fold-install\nieuw\viogpu3d-nativejob.sys -Force; $f="C:\Users\Public\fold-install\fold-install.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File $f -Actie voorbereiden -Delen kmd; powershell -NoProfile -ExecutionPolicy Bypass -File $f -Actie installeer' | tail -1
for r in 1 2 3 4; do
  $G 'shutdown /r /t 2' >/dev/null 2>&1; sleep 30
  for i in $(seq 1 60); do u=$(up); [ -n "$u" ] && [ "$u" -gt 50 ] && [ "$u" -lt 400 ] && break; sleep 5; done
  echo "na herstart $r (uptime $u):"; $G 'Get-Content C:\Users\Public\fold-install\install.log | select -Last 2; "pending: " + (Test-Path C:\Users\Public\fold-install\pending.json)'
  $G 'Get-Content C:\Users\Public\fold-install\install.log' | grep -q waakhond && { echo "waakhond heeft teruggezet"; break; }
done
