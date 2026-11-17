#!/bin/bash
# flips.sh [n]: last n fliplog/fliphist lines of this boot's KMD registry log (HKLM\...\Services\VioGpu3D\DbgLog<DbgLogSeq>)
G="ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=6 USER@127.0.0.1"
$G '$k=Get-Item HKLM:\SYSTEM\CurrentControlSet\Services\VioGpu3D; [Text.Encoding]::ASCII.GetString($k.GetValue("DbgLog"+$k.GetValue("DbgLogSeq")))' | tr -d '\r' | grep -E "fliplog|fliphist" | tail -${1:-4}
