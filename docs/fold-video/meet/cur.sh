#!/bin/bash
# cur.sh <label>: DWM frames while the mouse moves over curtest windows (masked-color cursor, then the inverting one)
cd "$(dirname "$0")"; G="ssh -p 2222 -o BatchMode=yes USER@127.0.0.1"
for t in curtest curtestinv; do
  $G "Start-ScheduledTask $t" >/dev/null; sleep 2
  echo "$t: $(bash meet.sh hist "$1 $t" 5 "sleep 1; $G \"Set-Content C:\\Users\\Public\\meet\\mode.txt cursor; Start-ScheduledTask meethulp; Start-Sleep 4\" >/dev/null" | tail -1)"
  sleep 4
done
