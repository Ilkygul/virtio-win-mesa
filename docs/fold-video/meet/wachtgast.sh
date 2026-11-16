#!/bin/bash
# wachtgast.sh: wait until the guest answers and has been up > 50 s; print the fold-install log tail
G="ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=6 USER@127.0.0.1"
for i in $(seq 1 80); do u=$($G '[int]((Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds' 2>/dev/null | tr -dc 0-9); [ -n "$u" ] && [ "$u" -gt 50 ] && break; sleep 5; done
echo "uptime ${u:-?}"; $G 'Get-Content C:\Users\Public\fold-install\install.log | select -Last 3; "pending: " + (Test-Path C:\Users\Public\fold-install\pending.json)'
