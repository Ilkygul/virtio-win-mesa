#!/bin/bash
# animtrace.sh <label>: WPR GPU trace around 3 Start-menu openings (guest-side input); prints dwm present intervals per burst
cd "$(dirname "$0")"; G=../g.sh
scp -q -P 2222 -o BatchMode=yes gastanim.ps1 USER@127.0.0.1:C:/Users/Public/meet/gastanim.ps1
$G 'wpr -cancel 2>$null; Remove-Item C:\Users\Public\meet\anim.etl -EA 0; wpr -start GPU -filemode | Out-Null; Set-Content C:\Users\Public\meet\mode.txt gastanim; Start-ScheduledTask meethulp; Start-Sleep 2; while((Get-ScheduledTask meethulp).State -eq "Running"){Start-Sleep -m 300}; wpr -stop C:\Users\Public\meet\anim.etl | Out-Null
$o=New-Object System.Collections.Generic.List[string]; Get-WinEvent -Path C:\Users\Public\meet\anim.etl -Oldest -EA SilentlyContinue | ?{ $_.ProviderName -eq "Microsoft-Windows-DxgKrnl" -and $_.Id -eq 178 } | % { $v=$_.Properties | % { $_.Value }; if("$($v[6])" -eq "True"){ $o.Add(("{0},{1}" -f $_.TimeCreated.ToFileTimeUtc(), $_.ProcessId)) } }; $o | Set-Content C:\Users\Public\meet\anim.csv; Get-Process dwm | % Id' | tr -d '\r' > /tmp/dwmpid.$$
dwm=$(tail -1 /tmp/dwmpid.$$); rm -f /tmp/dwmpid.$$
scp -q -P 2222 -o BatchMode=yes USER@127.0.0.1:C:/Users/Public/meet/anim.csv log/anim-$1.csv
python3 - "$dwm" "log/anim-$1.csv" "$1" <<'PY'
import sys
dwm,f,lab=sys.argv[1:4]
t=[int(l.split(',')[0]) for l in open(f,encoding='utf-8-sig') if l.strip() and l.strip().split(',')[1]==dwm]
t.sort(); bursts=[]; cur=[t[0]] if t else []
for a,b in zip(t,t[1:]):
    if (b-a)/1e4>300: bursts.append(cur); cur=[b]
    else: cur.append(b)
if cur: bursts.append(cur)
print(f"== {lab}: dwm-presents per Start-animatie")
for c in bursts:
    if len(c)<5: continue
    iv=[(b-a)/1e4 for a,b in zip(c,c[1:])]
    d=(c[-1]-c[0])/1e7
    print(f"  {len(c):3d} frames in {d*1000:5.0f} ms = {(len(c)-1)/d:5.1f} fps, max gat {max(iv):4.0f} ms, gaten>25ms {sum(1 for x in iv if x>25)}  {[round(x) for x in iv][:30]}")
PY
