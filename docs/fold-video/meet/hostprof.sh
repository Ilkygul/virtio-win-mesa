#!/system/bin/sh
# hostprof.sh <seconds>: GPU busy/freq samples + per-thread CPU of crosvm and the virgl render workers
D=${1:-10}; K=/sys/class/kgsl/kgsl-3d0
pids="$(pidof crosvm) $(pidof virgl_render_server) $(for p in /proc/[0-9]*; do c=$(cat $p/comm 2>/dev/null); case $c in virgl-*) echo ${p#/proc/};; esac; done)"
snap() { for p in $pids; do for t in /proc/$p/task/*; do s=$(cat $t/stat 2>/dev/null) || continue; set -- ${s#*) }; echo "$p ${t##*/} $(cat $t/comm) $(( ${12} + ${13} ))"; done; done; }
snap > /data/local/tmp/hp.a; end=$(( $(date +%s) + D )); bs=""; fs=""
while [ $(date +%s) -lt $end ]; do bs="$bs $(cat $K/gpu_busy_percentage | tr -dc 0-9)"; fs="$fs $(( $(cat $K/gpuclk)/1000000 ))"; sleep 0.5; done
snap > /data/local/tmp/hp.b
echo "gpu busy%:$bs"
echo "gpu MHz:$fs (max $(( $(cat $K/max_gpuclk)/1000000 )))"
echo "temp: $(cat /sys/class/thermal/thermal_zone*/type 2>/dev/null | paste - /dev/null | head -0)$(for z in /sys/class/thermal/thermal_zone*; do case $(cat $z/type) in *gpu*) echo -n "$(cat $z/type)=$(( $(cat $z/temp)/1000 )) ";; esac; done)"
awk 'NR==FNR{a[$1" "$2]=$4; n[$1" "$2]=$3; next} {k=$1" "$2; d=$4-a[k]; if(d>0) print d, $3, $1}' /data/local/tmp/hp.a /data/local/tmp/hp.b | sort -rn | head -14 | awk -v D=$D '{printf "  %5.1f%% cpu  %s (pid %s)\n", $1/D, $2, $3}'
