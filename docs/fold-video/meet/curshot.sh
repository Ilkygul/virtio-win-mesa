#!/bin/bash
# curshot.sh <out.png> [task]: show curtest, centre the mouse, crop a 120 px screenshot around the cursor layer
S=$(dirname "$1"); id=$(adb -s R3GL60E8R2K shell dumpsys SurfaceFlinger --display-id | head -1 | awk '{print $2}')
ssh -p 2222 -o BatchMode=yes USER@127.0.0.1 "Start-ScheduledTask ${2:-curtest}; Start-Sleep 6; Start-ScheduledTask midden; Start-Sleep 3"
set -- "$1" $(adb -s R3GL60E8R2K shell dumpsys SurfaceFlinger | grep -E "64.0    64.0 \|" | grep -oE "\| +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ \|" | head -1 | tr -d "|")
echo "cursorlaag $2 $3 $4 $5"
adb -s R3GL60E8R2K exec-out screencap -p -d $id > "$S/full.png"
sips -c 120 120 --cropOffset $(( $3 - 30 )) $(( $2 - 30 )) "$S/full.png" --out "$1" >/dev/null; sips -z 360 360 "$1" >/dev/null
rm -f -- "$S/full.png"
