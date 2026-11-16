#!/bin/bash
# vmherstart.sh: Windows shutdown + crosvm stop + windows-vm.sh start (no guest reset: avoids the droidvmd crash on reset)
S=R3GL60E8R2K; G="ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=5 USER@127.0.0.1"; VMID=552e0e49-1003-49d4-8199-c5d38942f549
$G 'shutdown /s /t 0' >/dev/null 2>&1; for i in $(seq 1 60); do $G 'exit 0' 2>/dev/null || break; sleep 3; done; sleep 12
adb -s $S shell "su -c \"sh /data/local/tmp/vmreq.sh vm_stop '\\\"vm_id\\\":\\\"$VMID\\\"'\"" >/dev/null
adb -s $S shell "su -c 'for i in \$(seq 1 30); do pidof crosvm >/dev/null || break; sleep 2; done; sh /data/adb/fold-vm/windows-vm.sh start'" | tail -2
adb -s $S forward tcp:2222 tcp:2222 >/dev/null
adb -s $S shell "su -c 'netstat -ltn | grep -q 127.0.0.1:2222 || (setsid toybox nc -s 127.0.0.1 -p 2222 -L toybox nc 10.77.0.100 22 </dev/null >/dev/null 2>&1 &)'"
t=0; until $G 'exit 0' 2>/dev/null; do sleep 5; t=$((t+5)); [ $t -ge 300 ] && { echo "gast niet terug"; exit 1; }; done
until [ "$($G '[int]((Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds' | tr -dc 0-9)" -gt 45 ]; do sleep 5; done
echo "gast terug na ${t}s"
