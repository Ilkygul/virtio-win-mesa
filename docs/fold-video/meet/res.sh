#!/bin/bash
# res.sh <keuze> [hz]: clipsync "Resolutie" choice in the interactive session, then print mode + marker
G="ssh -p 2222 -o BatchMode=yes USER@127.0.0.1"
$G "\$a=New-ScheduledTaskAction -Execute 'C:\Program Files\DroidVM\clipsync.exe' -Argument 'res $*'; Register-ScheduledTask resk -Action \$a -Principal (Get-ScheduledTask meethulp).Principal -Settings (Get-ScheduledTask meethulp).Settings -Force | Out-Null; Start-ScheduledTask resk" >/dev/null
sleep ${WACHT:-6}
bash "$(dirname "$0")/hz.sh" 0 | sed 's/^/  /'; $G '"  vast: " + (Test-Path C:\Users\Public\viogpu-vast); Get-Content $env:LOCALAPPDATA\clipsync.log -Tail 2 | % { "  " + $_ }'
