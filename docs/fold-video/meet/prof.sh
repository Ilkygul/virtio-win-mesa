#!/bin/bash
# prof.sh <video|scroll> : host profile with effects on and off during a steady load
cd "$(dirname "$0")"; G="ssh -p 2222 -o BatchMode=yes USER@127.0.0.1"; S=R3GL60E8R2K
gast() { $G "Set-Content C:\\Users\\Public\\meet\\mode.txt $1; Start-ScheduledTask meethulp; Start-Sleep 1; while((Get-ScheduledTask meethulp).State -eq 'Running'){Start-Sleep -m 300}; Get-Content C:\\Users\\Public\\meet\\out.txt -EA 0" | tr -d '\r' | tail -1; }
for fx in 1 0; do
  bash meet.sh fx $fx | tail -1; sleep 3
  case $1 in
    video) gast video >/dev/null; sleep 10; gast play; sleep 6
           echo "== effecten $fx, video"; adb -s $S shell "su -c 'sh /data/local/tmp/hostprof.sh 10'"; gast close >/dev/null;;
    scroll) gast explorer >/dev/null; sleep 3
           echo "== effecten $fx, scrollen"
           ( for i in 1 2 3 4; do adb -s $S shell input swipe 900 1200 900 700 1200; adb -s $S shell input swipe 900 700 900 1200 1200; done ) &
           adb -s $S shell "su -c 'sh /data/local/tmp/hostprof.sh 8'"; wait; gast close >/dev/null;;
  esac
done
