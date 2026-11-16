#!/system/bin/sh
# paden-verhuis.sh heen|terug: production host paths out of the codex-* names (register stap 4, 16-11-2026).
#   usr/codex-c37-gpu-poll-r1 -> usr/host-c37 (virglrenderer C37), npt/codex-c33-minfp32-r1 -> npt/dxvk-c33
#   (DXVK C33 + shader cache), inactive trace paths -> npt/trace/. Root, with crosvm stopped (pool may stay).
set -e
A=/data/data/cn.classfun.droidvm; N=/data/adb/fold-vm/npt; B=/data/adb/fold-vm/backup-paden-20261116
ctx=$(ls -Z $A/files/vms.json | cut -d' ' -f1)
pidof crosvm >/dev/null && { echo "crosvm draait nog" >&2; exit 1; }
for p in $(pidof app_process64); do tr '\0' ' ' < /proc/$p/cmdline | grep -q droidvm.daemon.Daemon && kill -9 $p; done
am force-stop cn.classfun.droidvm; sleep 2
case "$1" in
  heen)
    mkdir -p $B; [ -f $B/vms-voor.json ] || cp -p $A/files/vms.json $B/vms-voor.json
    mv $A/usr/codex-c37-gpu-poll-r1 $A/usr/host-c37
    mv $N/codex-c33-minfp32-r1 $N/dxvk-c33
    mkdir -p $N/trace; [ ! -d $N/codex-c25-ps-program-r1 ] || mv $N/codex-c25-ps-program-r1 $N/trace/ps-program
    new=/data/local/tmp/vms-nieuw.json ;;
  terug)
    mv $A/usr/host-c37 $A/usr/codex-c37-gpu-poll-r1
    mv $N/dxvk-c33 $N/codex-c33-minfp32-r1
    new=$B/vms-voor.json ;;
  *) echo "gebruik: $0 heen|terug" >&2; exit 2 ;;
esac
cp "$new" $A/files/vms.json.new
chown 10524:10524 $A/files/vms.json.new; chmod 600 $A/files/vms.json.new; chcon "$ctx" $A/files/vms.json.new
mv -f $A/files/vms.json.new $A/files/vms.json; sync
echo "paden $1: $(grep -c codex $A/files/vms.json) codex-verwijzingen in vms.json"
