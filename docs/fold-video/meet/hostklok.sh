#!/system/bin/sh
# hostklok.sh <seconds>: every 10 ms monotonic ns, cpu policy0/6 cur freq (MHz), gpu clock (MHz), gpu busy %
end=$(( $(date +%s) + $1 )); K=/sys/class/kgsl/kgsl-3d0; C=/sys/devices/system/cpu/cpufreq
while [ $(date +%s) -lt $end ]; do
  echo "$(awk '/now at/{print $3; exit}' /proc/timer_list) $(( $(cat $C/policy0/scaling_cur_freq)/1000 )) $(( $(cat $C/policy6/scaling_cur_freq)/1000 )) $(( $(cat $K/gpuclk)/1000000 )) $(cat $K/gpu_busy_percentage | tr -dc 0-9)"
  usleep 10000
done
