#!/system/bin/sh
# gpu-vloer.sh start|stop|status - warm the GPU/CPU chain while the Windows VM is on screen AND active.
# Adreno DCVS and the CPU governors keep clocks low for the bursty, low-average load of a composited desktop, so the
# first frames of an animation (and every blur frame) miss the refresh. Measured 16-11 (effects on, 60 Hz):
#   GPU floor 902: scrolling 51 -> 59 fps, video drops 27 -> 1 %, flyout 47 -> 57 fps;
#   + CPU floors (policy0 1.8 GHz, policy6 2.5 GHz): Start animation 33-42 -> 45-50 fps.
# Loop every 50 ms while crosvm runs and a panel is lit: when crosvm's CPU time grows faster than IDLE_TICKS per 50 ms
# (input, animation, video) the boost (GPU min BOOST_GPU MHz, CPU min floors) holds until 10 s after the last
# activity; otherwise GPU min = BASE_GPU and CPU mins are restored. Something on the phone resets the GPU floor at
# times; the loop re-applies it. Samsung's thermal limit still caps the MAXIMUM clocks.
# Off: gpu-vloer.sh stop (restores boot floors). windows-vm.sh calls start/stop. Log: gpu-vloer.log
HERE=/data/adb/fold-vm; K=/sys/class/kgsl/kgsl-3d0; C=/sys/devices/system/cpu/cpufreq
BASE_GPU=${BASE_GPU:-422}; BOOST_GPU=${BOOST_GPU:-902}; CPU0_BOOST=${CPU0_BOOST:-1804800}; CPU6_BOOST=${CPU6_BOOST:-2496000}
IDLE_TICKS=${IDLE_TICKS:-2}; HOLD_MS=${HOLD_MS:-10000}
PIDF=$HERE/gpu-vloer.pid; LOG=$HERE/gpu-vloer.log; AAN=$HERE/gpu-vloer.aan; ORIG=$HERE/gpu-vloer.orig
log() { echo "$(date '+%F %T') $*" >> $LOG; }
lit() { for b in /sys/class/backlight/panel*-backlight/brightness; do [ "$(cat $b 2>/dev/null)" -gt 0 ] 2>/dev/null && return 0; done; return 1; }
put() { [ "$(cat $1 2>/dev/null)" = "$2" ] || echo $2 > $1 2>/dev/null; }
ticks() { local s=0 t; for p in $(pidof crosvm); do t=$(cut -d' ' -f14,15 /proc/$p/stat 2>/dev/null); set -- $t; s=$((s + ${1:-0} + ${2:-0})); done; echo $s; }
restore() { put $K/min_clock_mhz $(sed -n 1p $ORIG); put $C/policy0/scaling_min_freq $(sed -n 2p $ORIG); put $C/policy6/scaling_min_freq $(sed -n 3p $ORIG); }
case $1 in
  start)
    touch $AAN
    if [ -f $PIDF ] && kill -0 $(cat $PIDF) 2>/dev/null; then echo "draait al (pid $(cat $PIDF))"; exit 0; fi
    { [ -f $ORIG ] && [ $(wc -l < $ORIG) -ge 3 ]; } || printf '422\n%s\n%s\n' $(cat $C/policy0/scaling_min_freq) $(cat $C/policy6/scaling_min_freq) > $ORIG
    setsid sh $0 lus </dev/null >/dev/null 2>&1 &
    echo $! > $PIDF; log "gestart (pid $!, basis $BASE_GPU, boost $BOOST_GPU + cpu $CPU0_BOOST/$CPU6_BOOST)"; echo "gestart (pid $!)";;
  lus)
    state=uit; last=$(ticks); hold=0; n=0
    while [ -f $AAN ]; do
      if pidof crosvm >/dev/null && lit; then
        now=$(ticks); d=$((now - last)); last=$now
        [ $d -gt $IDLE_TICKS ] && hold=$((HOLD_MS / 50))
        if [ $hold -gt 0 ]; then
          hold=$((hold - 1))
          [ $state = boost ] || { state=boost; n=$((n + 1)); }
          put $K/min_clock_mhz $BOOST_GPU; put $C/policy0/scaling_min_freq $CPU0_BOOST; put $C/policy6/scaling_min_freq $CPU6_BOOST
        else
          [ $state = basis ] || { state=basis; [ $((n % 200)) = 1 ] && log "boosts tot nu: $n"; }
          put $K/min_clock_mhz $BASE_GPU; put $C/policy0/scaling_min_freq $(sed -n 2p $ORIG); put $C/policy6/scaling_min_freq $(sed -n 3p $ORIG)
        fi
        usleep 50000
      else
        [ $state = uit ] || { state=uit; restore; log "VM niet op scherm: alles terug"; }
        last=$(ticks); sleep 2
      fi
    done
    restore; log "gestopt, alles terug ($n boosts)"; rm -f $PIDF
    ;;
  stop) rm -f $AAN; echo "stopt binnen 2 s";;
  status) echo "aan=$([ -f $AAN ] && echo ja || echo nee) pid=$(cat $PIDF 2>/dev/null) gpu-min=$(cat $K/min_clock_mhz) gpu=$(( $(cat $K/gpuclk) / 1000000 )) cpu0-min=$(cat $C/policy0/scaling_min_freq) cpu6-min=$(cat $C/policy6/scaling_min_freq) thermal=$(cat $K/thermal_pwrlevel)"; tail -3 $LOG;;
  *) echo "gpu-vloer.sh start|stop|status"; exit 2;;
esac
