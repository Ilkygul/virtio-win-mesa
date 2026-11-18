#!/bin/bash
# startshot.sh <naam>: bring Windows to front, open Start from inside the guest, screenshot the Fold screen, close Start
P=$(dirname "$0")
adb shell "dumpsys window | grep mCurrentFocus" 2>/dev/null | tail -1 | grep -q VMNative || { adb shell "su -c 'sh /data/adb/modules/fold-vm/bin/windows-vm.sh openen 0'" >/dev/null; sleep 4; }
st() { bash $P/g.sh "Set-Content C:\\Users\\Public\\meet\\mode.txt startopen; Start-ScheduledTask meethulp; Start-Sleep 1; while((Get-ScheduledTask meethulp).State -eq 'Running'){Start-Sleep -m 200}" >/dev/null; }
st; sleep 1.5
D=$(adb shell "dumpsys SurfaceFlinger --display-id" 2>/dev/null | head -1 | awk '{print $2}')
adb shell "su -c 'screencap -d $D -p /data/local/tmp/s.png'" 2>/dev/null; adb pull /data/local/tmp/s.png $P/s.png >/dev/null 2>&1; adb shell "su -c 'rm /data/local/tmp/s.png'"
st
sips -s format jpeg -Z 900 $P/s.png --out $P/shot-$1.jpg >/dev/null 2>&1; rm -f $P/s.png; echo $P/shot-$1.jpg
