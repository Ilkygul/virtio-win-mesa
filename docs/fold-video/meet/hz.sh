#!/bin/bash
# hz.sh <hz> [w h] | lijst: run scherm.exe in the interactive session (task "scherm")
G="ssh -p 2222 -o BatchMode=yes USER@127.0.0.1"
$G "\$a=New-ScheduledTaskAction -Execute C:\Users\Public\meet\scherm.exe -Argument '$*'; Register-ScheduledTask scherm -Action \$a -Principal (Get-ScheduledTask meethulp).Principal -Settings (Get-ScheduledTask meethulp).Settings -Force | Out-Null; Remove-Item C:\Users\Public\meet\scherm.txt -EA 0; Start-ScheduledTask scherm; Start-Sleep 2; while((Get-ScheduledTask scherm).State -eq 'Running'){Start-Sleep -m 300}; Get-Content C:\Users\Public\meet\scherm.txt"
