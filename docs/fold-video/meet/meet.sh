#!/bin/bash
# meet.sh - punten 1-4 van het vloeiendheidsdoel, gemeten op de DroidVM-laag in SurfaceFlinger (Fold-scherm).
#   meet.sh [start|sleep|scroll|cursor|video|alles] [label]
# Windows-coordinaten -> scherm: x gelijk, y + OY (DroidVM-beeld 1:1, gemeten 15-11).
S=${S:-R3GL60E8R2K}; OY=${OY:-396}; VIDEO=${VIDEO:-aqz-KE-bpKQ}   # Big Buck Bunny 1080p60
G="ssh -p 2222 -o BatchMode=yes USER@127.0.0.1"
A() { adb -s $S shell "$@"; }
laag() { A 'dumpsys SurfaceFlinger --list' | sed -n 's/.*RequestedLayerState{\([0-9a-f]* SurfaceView\[cn.classfun.droidvm[^]]*VMNativeDisplayActivity\]@0(BLAST)#[0-9]*\).*/\1/p'; }
# Collect present times of layer $L for $1 seconds (polls every 0.8 s; the SF ring holds 128 frames), then
# runs the action in $2 in parallel. Output: one monotonic ns timestamp per line in $T.
# Both DroidVM BLAST layers are polled; the one with the most frames in the window counts.
verzamel() { local dur=$1 l q=""; T=$(mktemp); while read -r l; do q="$q \"$l\""; done <<< "$L"
  A "end=\$((\$(date +%s)+$dur)); while [ \$(date +%s) -lt \$end ]; do for l in $q; do echo \"L \${l##*#}\"; dumpsys SurfaceFlinger --latency \"\$l\"; done; sleep 0.8; done" |
    awk '$1=="L"{id=$2;next} NF==3&&$2>0&&$2<9e18{print id, $2}' | sort -u > $T.all & local pid=$!; sleep 0.3; T0=$(mono); eval "$2"; wait $pid
  local best=$(awk -v t0=$T0 '$2>t0{c[$1]++} END{for(k in c) print c[k], k}' $T.all | sort -rn | head -1 | cut -d' ' -f2)
  awk -v b="$best" '$1==b{print $2}' $T.all | sort -n > $T; rm -f $T.all; }
# stats VAN TOT: only frames between T0+VAN ms and T0+TOT ms (the moving part)
stats() { awk -v from=$((T0+${1:-0}*1000000)) -v to=$((T0+${2:-60000}*1000000)) '$1>=from&&$1<=to{t[++c]=$1} END{ if(c<3){print "te weinig frames ("c")"; exit}
  d=(t[c]-t[1])/1e9; m=0; for(i=2;i<=c;i++){g=(t[i]-t[i-1])/1e6; if(g>m)m=g; if(g>35)b++}
  for(i=2;i<=c;i++){g=(t[i]-t[i-1])/1e6; if(g>=13&&g<=21)k++}
  printf "%.1f fps (%d frames/%.2fs), max gat %.0f ms, gaten>35ms %d, ritme 17±4ms %.0f%%\n",(c-1)/d,c,d,m,b+0,100*k/(c-1) }' $T; }
mono() { A "su -c \"awk '/now at/{print \\\$3; exit}' /proc/timer_list\"" | tr -d '\r'; }
gast() { $G "Set-Content C:\\Users\\Public\\meet\\quality.txt '${QUALITY:-hd1080}'; Set-Content C:\\Users\\Public\\meet\\mode.txt '$1'; Set-Content C:\\Users\\Public\\meet\\video.txt '$VIDEO'; Remove-Item C:\\Users\\Public\\meet\\out.txt -EA 0; Start-ScheduledTask meethulp; Start-Sleep 1; for(\$i=0;\$i -lt 90 -and (Get-ScheduledTask meethulp).State -eq 'Running';\$i++){Start-Sleep -m 500}; Get-Content C:\\Users\\Public\\meet\\out.txt"; }
tap() { A "input tap $1 $(($2+OY))"; }
swipe() { A "input swipe $1 $(($2+OY)) $3 $(($4+OY)) $5"; }

punt1() { # Start (Win-toets) en netwerk-flyout (tik): input -> einde van de frame-burst (eerste gat >150 ms). De opstarttijd van
  # Android's "input" (gemeten met een lege toets, KEYCODE_UNKNOWN) gaat er af: die tik bereikt Windows pas daarna.
  local ov=$(A 'su -c "t=\$(awk \"/now at/{print \\\$3; exit}\" /proc/timer_list); input keyevent 0; awk -v t=\$t \"/now at/{print int((\\\$3-t)/1e6); exit}\" /proc/timer_list"' | tr -d '\r')
  echo "  input-overhead ${ov} ms (afgetrokken)"
  for doel in "Start key KEYCODE_META_LEFT" "Netwerk-flyout tap 2316 1119"; do set -- $doel
    for r in 1 2 3; do sleep 2; if [ $2 = key ]; then verzamel 3 "A 'input keyevent $3'"; else verzamel 3 "tap $3 $4"; fi
      awk -v t0=$T0 -v ov=$ov '$1>t0+ov*1e6 && $1<t0+(ov+2000)*1e6 {t[++c]=$1} END{ if(!c){print "  geen frames"; exit}
        e=1; for(i=2;i<=c;i++){ if(t[i]-t[i-1]>150e6) break; e=i }
        printf "  %s r%d: eerste frame %.0f ms, einde animatie %.0f ms (%d frames; daarna losse frames tot %.0f ms, bv. knipperende cursor)\n","'$1'",'$r',(t[1]-t0)/1e6-ov,(t[e]-t0)/1e6-ov,e,(t[c]-t0)/1e6-ov }' $T
      sleep 1; A 'input keyevent KEYCODE_ESCAPE'; rm -f $T; done; done; }
punt2() { # Verkenner en Edge: venster slepen (titelbalk) en scrollen (aanraakswipe in de inhoud)
  for app in explorer edge; do echo "  $app: $(gast $app | tail -1)"; sleep 4
    verzamel 6 "gast drag >/dev/null" ; echo "  $app slepen:  $(stats 1600 3700)"; rm -f $T
    sleep 1; verzamel 4 "swipe 900 800 900 300 1500; swipe 900 300 900 800 1500"; echo "  $app scrollen: $(stats 200 2900)"; rm -f $T; done
  gast close >/dev/null; }
punt3() { # muiscursor: muisbeweging over het bureaublad; zonder hardware-cursor = elk cursorbeeld een DWM-frame
  verzamel 6 "gast cursor >/dev/null"; echo "  cursor rustig: $(stats 1500 4000)"; rm -f $T
  gast explorer >/dev/null; sleep 3
  verzamel 6 "(gast cursor >/dev/null &); sleep 1.5; swipe 900 800 900 300 2500"; echo "  cursor + scrollen: $(stats 1700 3900)"; rm -f $T; gast close >/dev/null; }
punt4() { # YouTube 1080p60 in Edge (eigen profiel): SF-fps + Chromium dropped frames over 20 s
  gast video >/dev/null; sleep 8; gast play | tail -1; sleep 10; q0=$(gast quality | tail -1); verzamel 20 "sleep 20"; q1=$(gast quality | tail -1)
  echo "  video SF: $(stats 0 20000)"; rm -f $T
  python3 -c "import json,sys;a=json.loads(sys.argv[1]);b=json.loads(sys.argv[2]);t=b['total']-a['total'];d=b['dropped']-a['dropped'];print('  Chromium: %dx%d, %d frames in %.1fs = %.1f fps, dropped %d (%.1f%%), paused=%s'%(b['w'],b['h'],t,b['t']-a['t'],t/max(b['t']-a['t'],.1),d,100*d/max(t,1),b['paused']))" "$q0" "$q1" 2>&1
  gast close >/dev/null; }

L=$(laag); [ -n "$L" ] || { echo "geen DroidVM-laag (Windows-scherm niet open?)"; exit 1; }
echo "== meting ${2:-} $(date '+%d-%m %H:%M')"
case ${1:-alles} in
  ritme) # 1080p60-video: frame-intervallen van de DroidVM-laag (paneel-Hz meegeven als label)
    gast video >/dev/null; sleep 8; gast play | tail -1; sleep 8; verzamel 15 "sleep 15"; echo "  video ritme: $(stats 0 15000)"
    awk '{if(p)printf "%d ", ($1-p)/1e6+0.5; p=$1}' $T | tr ' ' '\n' | sort -n | uniq -c | sort -k2 -n | awk '{printf "%sms:%s ",$2,$1}'; echo; rm -f $T; gast close >/dev/null;;
  hist) verzamel ${3:-6} "$4"; awk -v t0=$T0 '{b=int(($1-t0)/2.5e8)*250; c[b]++} END{for(k in c) print k"ms:"c[k]}' $T | sort -n | tr '\n' ' '; echo; rm -f $T;;
  start) punt1;; sleep|scroll) punt2;; cursor) punt3;; video) punt4;;
  alles) echo "1 Start/flyout:"; punt1; echo "2 slepen/scrollen:"; punt2; echo "3 cursor:"; punt3; echo "4 video:"; punt4;;
esac
