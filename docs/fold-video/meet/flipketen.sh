#!/bin/bash
# flipketen.sh <label>: WPR trace around 3 Start openings (guest input) + host clocks; per DWM present: ms to the
# MMIO flip (116) and to the next vsync report (17); host CPU/GPU clocks over the run.
cd "$(dirname "$0")"; G=../g.sh; S=R3GL60E8R2K
adb -s $S push hostklok.sh /data/local/tmp/hostklok.sh >/dev/null
$G 'wpr -cancel 2>$null; Remove-Item C:\Users\Public\meet\fk.etl -EA 0; wpr -start GPU -filemode | Out-Null' >/dev/null
adb -s $S shell "su -c 'sh /data/local/tmp/hostklok.sh 11'" > log/klok-$1.txt &
sleep 1; $G 'Set-Content C:\Users\Public\meet\mode.txt gastanim; Start-ScheduledTask meethulp; Start-Sleep 2; while((Get-ScheduledTask meethulp).State -eq "Running"){Start-Sleep -m 300}' >/dev/null; wait
$G 'wpr -stop C:\Users\Public\meet\fk.etl | Out-Null; $dwm=(Get-Process dwm).Id; $o=New-Object System.Collections.Generic.List[string]; Get-WinEvent -Path C:\Users\Public\meet\fk.etl -Oldest -EA SilentlyContinue | ?{ $_.ProviderName -eq "Microsoft-Windows-DxgKrnl" -and $_.Id -in 178,116,17,168 } | % { $v=$_.Properties | % { $_.Value }; if($_.Id -eq 178){ if("$($v[6])" -eq "True" -and $_.ProcessId -eq $dwm){ $o.Add("P," + $_.TimeCreated.ToFileTimeUtc()) } } elseif($_.Id -eq 116){ $o.Add("M," + $_.TimeCreated.ToFileTimeUtc() + "," + $v[4]) } elseif($_.Id -eq 168){ $o.Add("F," + $_.TimeCreated.ToFileTimeUtc()) } else { $o.Add("V," + $_.TimeCreated.ToFileTimeUtc() + "," + $v[2]) } }; $o | Set-Content C:\Users\Public\meet\fk.csv' >/dev/null
scp -q -P 2222 -o BatchMode=yes USER@127.0.0.1:C:/Users/Public/meet/fk.csv log/fk-$1.csv
python3 - log/fk-$1.csv log/klok-$1.txt "$1" <<'PY'
import sys,bisect
P=[];M=[];F=[];V=[]
for l in open(sys.argv[1],encoding='utf-8-sig'):
    p=l.strip().split(',')
    if p[0]=='P':P.append(int(p[1]))
    elif p[0]=='M':M.append((int(p[1]),p[2]))
    elif p[0]=='F':F.append(int(p[1]))
    elif p[0]=='V':V.append((int(p[1]),p[2]))
print(f"== {sys.argv[3]}: dwm-presents {len(P)}, MMIO-flips(116) {len(M)}, flip-DMA(168) {len(F)}, vsyncs {len(V)}")
chg=[];last=None
for t,a in V:
    if a!=last: chg.append(t); last=a
print(f"  vsync-adreswissels {len(chg)}")
mt=[t for t,_ in M]
# bursts of presents
b=[];cur=[P[0]] if P else []
for a,c in zip(P,P[1:]):
    if (c-a)/1e4>300: b.append(cur); cur=[c]
    else: cur.append(c)
if cur:b.append(cur)
for c in b:
    if len(c)<4: continue
    rows=[]
    for p in c[:12]:
        i=bisect.bisect_left(mt,p); m=(mt[i]-p)/1e4 if i<len(mt) else -1
        j=bisect.bisect_right(chg,p); v=(chg[j]-p)/1e4 if j<len(chg) else -1
        rows.append(f"{m:.0f}/{v:.0f}")
    iv=[round((y-x)/1e4) for x,y in zip(c,c[1:])][:12]
    print(f"  burst n={len(c)} intervals {iv}\n    present->mmio/->vsyncwissel ms: {rows}")
ks=[l.split() for l in open(sys.argv[2]) if l.strip()]
import statistics as st
c0=[int(k[1]) for k in ks if len(k)>4]; c6=[int(k[2]) for k in ks if len(k)>4]; g=[int(k[3]) for k in ks if len(k)>4]
print(f"  host: cpu0 MHz min/med/max {min(c0)}/{st.median(c0)}/{max(c0)}, cpu6 {min(c6)}/{st.median(c6)}/{max(c6)}, gpu {min(g)}/{st.median(g)}/{max(g)}, samples {len(g)}")
PY
