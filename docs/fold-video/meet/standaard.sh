#!/bin/bash
# standaard.sh <label>: de standaardmeting van één proef (±12 min). Eindigt op 60 Hz met effecten aan.
cd "$(dirname "$0")"; L=${1:-x}
A() { adb -s ${S:-R3GL60E8R2K} shell "$@"; }
rust() { # crosvm CPU time (ms) and GPU floor/clock over 10 s idle desktop, after 5 s settling
  A "su -c 'sleep 5; t() { s=0; for p in \$(pidof crosvm) \$(pidof virgl_render_server); do set -- \$(cut -d\" \" -f14,15 /proc/\$p/stat); s=\$((s+\$1+\$2)); done; echo \$s; }; a=\$(t); g=0; n=0; for i in 1 2 3 4 5 6 7 8 9 10; do sleep 1; g=\$((g+\$(cat /sys/class/kgsl/kgsl-3d0/gpuclk)/1000000)); done; b=\$(t); echo \"  rust 10 s: crosvm+render CPU \$(((b-a)*10)) ms, gpu gem \$((g/10)) MHz, gpumin \$(cat /sys/class/kgsl/kgsl-3d0/min_clock_mhz), cpu0min \$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq)\"'" | tr -d '\r'; }
voor() { A "dumpsys window | grep -m2 mCurrentFocus" 2>/dev/null | grep -q VMNativeDisplay || { A "su -c 'sh /data/adb/fold-vm/windows-vm.sh openen 0'" >/dev/null; sleep 5; echo "  (Windows opnieuw vooraan gezet $(date +%T))"; }; }
echo "#### $L $(date '+%d-%m %H:%M')"
bash meet.sh fx 1 | tail -1; bash hz.sh 60 1848 1768 >/dev/null
echo "## rust"; rust
voor; echo "## 60 Hz effecten aan (r1 = eerste opening na 60 s rust)"; sleep 60; voor; GATEN=1 bash meet.sh anim $L; bash meet.sh scroll $L; bash meet.sh video $L; bash flips.sh 2
voor; echo "## 60 Hz effecten uit"; bash meet.sh fx 0 | tail -1; sleep 3; bash meet.sh scroll $L; bash meet.sh bench $L
voor; echo "## 120 Hz effecten uit"; bash hz.sh 120 1848 1768; sleep 4; RT=8.33 TOL=2 bash meet.sh scroll $L; bash flips.sh 2
voor; echo "## 120 Hz effecten aan"; bash meet.sh fx 1 | tail -1; sleep 3; RT=8.33 TOL=2 bash meet.sh scroll $L; RT=8.33 bash meet.sh anim $L; bash flips.sh 2
bash hz.sh 60 1848 1768
A "su -c 'logcat -d | grep \"fold r8\" | tail -3; tail -2 /data/adb/fold-vm/vloerhulp.log'" | tr -d '\r'
