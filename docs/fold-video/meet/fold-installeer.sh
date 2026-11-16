#!/bin/bash
# fold-installeer.sh - install UMD, KMD and/or crosvm on the Fold's Windows VM in one go, with a health
# check after the restart and automatic rollback when it fails. Runs on the Mac (adb + guest SSH relay).
#   fold-installeer.sh [--umd neptune_umd.dll neptune_umd_ec.dll] [--kmd viogpu3d-nativejob.sys] [--crosvm crosvm]
#   fold-installeer.sh --terug        restore the previous versions of the last install (+ restart)
# Safety nets: (1) health check here -> rollback; (2) guest task fold-install-wacht: the third boot without a
# confirmed install restores the previous files itself; (3) crosvm: previous binary as crosvm.vorige.
# Not covered: a KMD that crashes Windows before the scheduled tasks run (then restore by hand, see register).
# Test switch: FAAL=1 makes the health check fail (exercises the rollback).
# (no set -u: bash 3.2 treats empty arrays as unbound)
S=${S:-R3GL60E8R2K}; G="ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=6 USER@127.0.0.1"
A() { adb -s $S shell "su -c \"$*\""; }
HERE=$(cd "$(dirname "$0")" && pwd); GD='C:\Users\Public\fold-install'; GDS='C:/Users/Public/fold-install'
VMID=552e0e49-1003-49d4-8199-c5d38942f549; U=/data/data/cn.classfun.droidvm/usr/bin; FI=/data/adb/fold-vm/fold-install
umd=() kmd='' crosvm='' terug=0
while [ $# -gt 0 ]; do case $1 in
  --umd) umd=("$2" "$3"); shift 3;; --kmd) kmd=$2; shift 2;; --crosvm) crosvm=$2; shift 2;; --terug) terug=1; shift;;
  *) echo "onbekend: $1" >&2; exit 2;; esac; done
log() { echo "$(date +%H:%M:%S) $*"; }
ps1() { $G "powershell -NoProfile -ExecutionPolicy Bypass -File $GD\\fold-install.ps1 $*"; }

herstart() {   # $1 = 1 when crosvm changed (VM process restart, memory pool stays), else a Windows restart
  if [ "$1" = 1 ]; then
    $G 'shutdown /s /t 0' >/dev/null 2>&1; for i in $(seq 1 60); do $G 'exit 0' 2>/dev/null || break; sleep 3; done; sleep 12
    A "sh /data/local/tmp/vmreq.sh vm_stop '\\\"vm_id\\\":\\\"$VMID\\\"'" >/dev/null
    A "for i in \\\$(seq 1 30); do pidof crosvm >/dev/null || break; sleep 2; done; sh /data/adb/fold-vm/windows-vm.sh start; sleep 3; sh /data/adb/fold-vm/windows-vm.sh openen 0" | tail -2
  else
    $G 'shutdown /r /t 2' >/dev/null 2>&1; sleep 25
  fi
}
gezond() {   # guest back within 4 min, GPU OK, DWM running, D3D11 draws on the GPU (drawbench 50 draws > 100 fps)
  local t=0; until $G 'exit 0' 2>/dev/null; do sleep 5; t=$((t+5)); [ $t -ge 240 ] && { log "gast niet terug binnen 240 s"; return 1; }; done
  until [ "$($G '[int]((Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds' | tr -dc 0-9)" -gt 60 ]; do sleep 5; done
  local st; st=$($G '$v=Get-CimInstance Win32_VideoController | ?{ $_.Name -like "*VirtIO GPU*" }; "$($v.Status) $((Get-PnpDevice -InstanceId $v.PNPDeviceID).Problem) dwm=$(@(Get-Process dwm -EA 0).Count)"' | tr -d '\r')
  log "gpu: $st"; case $st in "OK CM_PROB_NONE dwm=1"*|"OK 0 dwm=1"*) ;; *) return 1;; esac
  local fps; fps=$($G "Set-Content C:\\Users\\Public\\meet\\bench.txt '50 3'; Set-Content C:\\Users\\Public\\meet\\mode.txt bench; Start-ScheduledTask meethulp; Start-Sleep 2; while((Get-ScheduledTask meethulp).State -eq 'Running'){Start-Sleep -m 500}; Get-Content C:\\Users\\Public\\meet\\out.txt" | sed -n 's/.*fps=\([0-9]*\).*/\1/p')
  log "drawbench 50 draws: ${fps:-?} fps"; [ "${fps:-0}" -gt 100 ] || return 1
  [ "${FAAL:-0}" = 1 ] && [ "${NA:-0}" = 1 ] && { log "FAAL=1: gezondheidscontrole geforceerd mislukt"; return 1; }
  return 0
}
crosvm_terug() { A "[ -f $FI/crosvm.voor ] && cp $FI/crosvm.voor $U/crosvm.nieuw && chown 10524:10524 $U/crosvm.nieuw && chmod 755 $U/crosvm.nieuw && chcon u:object_r:app_data_file:s0:c12,c258,c512,c768 $U/crosvm.nieuw && mv -f $U/crosvm.nieuw $U/crosvm && echo crosvm-terug"; }

scp -q -P 2222 -o BatchMode=yes "$HERE/fold-install.ps1" USER@127.0.0.1:$GDS/fold-install.ps1 2>/dev/null || {
  $G "New-Item -ItemType Directory -Force $GD | Out-Null" && scp -q -P 2222 -o BatchMode=yes "$HERE/fold-install.ps1" USER@127.0.0.1:$GDS/fold-install.ps1; } || { log "gast onbereikbaar"; exit 1; }

if [ $terug = 1 ]; then
  ps1 -Actie terug -Reden handmatig; c=$(A "[ -f $FI/laatste-crosvm ] && echo 1"); [ "$c" = 1 ] && crosvm_terug
  herstart "${c:-0}"; gezond && log "terug en gezond" || log "LET OP: ook na terugzetten niet gezond"; exit 0
fi

delen=(); [ ${#umd[@]} -gt 0 ] && delen+=(umd); [ -n "$kmd" ] && delen+=(kmd)
[ ${#delen[@]} -gt 0 ] || [ -n "$crosvm" ] || { echo "niets te installeren" >&2; exit 2; }
gezond >/dev/null || { log "huidige stand is niet gezond: eerst herstellen, niets geïnstalleerd"; exit 1; }
log "installeer: ${delen[*]} ${crosvm:+crosvm}"
d=$(IFS=,; echo "${delen[*]}"); ps1 -Actie voorbereiden -Delen "'${d:-geen}'" || exit 1
[ ${#umd[@]} -gt 0 ] && { scp -q -P 2222 -o BatchMode=yes "${umd[0]}" USER@127.0.0.1:$GDS/nieuw/neptune_umd.dll && scp -q -P 2222 -o BatchMode=yes "${umd[1]}" USER@127.0.0.1:$GDS/nieuw/neptune_umd_ec.dll || exit 1; }
[ -n "$kmd" ] && { scp -q -P 2222 -o BatchMode=yes "$kmd" USER@127.0.0.1:$GDS/nieuw/viogpu3d-nativejob.sys || exit 1; }
ps1 -Actie installeer || { ps1 -Actie terug -Reden plaatsen-mislukt; exit 1; }
c=0
if [ -n "$crosvm" ]; then
  adb -s $S push "$crosvm" /data/local/tmp/crosvm.fold-install >/dev/null || exit 1
  A "mkdir -p $FI && cp $U/crosvm $FI/crosvm.voor && touch $FI/laatste-crosvm && cp /data/local/tmp/crosvm.fold-install $U/crosvm.nieuw && chown 10524:10524 $U/crosvm.nieuw && chmod 755 $U/crosvm.nieuw && chcon u:object_r:app_data_file:s0:c12,c258,c512,c768 $U/crosvm.nieuw && mv -f $U/crosvm.nieuw $U/crosvm && rm /data/local/tmp/crosvm.fold-install && sha256sum $U/crosvm | cut -c1-8" || exit 1
  c=1
else A "rm -f $FI/laatste-crosvm"; fi
log "herstart"; herstart $c; NA=1
if gezond; then ps1 -Actie bevestig; log "KLAAR: nieuwe versie gezond"; exit 0; fi
log "NIET GEZOND: terugzetten"
[ $c = 1 ] && crosvm_terug
$G 'exit 0' 2>/dev/null && ps1 -Actie terug -Reden gezondheidscontrole
NA=0; herstart $c
gezond && log "teruggezet en gezond" || log "LET OP: ook na terugzetten niet gezond (waakhond in de gast zet na 3 boots zelf terug)"
exit 1
