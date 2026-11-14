# Defines a read-only helper; no desktop, session, RDP, process or configuration changes.
# Windows 11 target: WTS_SESSIONSTATE_UNLOCK=1. No usernames/client addresses returned.
function Get-C11ConsoleState {
    param([int]$BenchmarkProcessId=0)
    if (-not ('C11ConsoleNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class C11ConsoleNative {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct LevelOne {
        public uint SessionId; public int SessionState; public int SessionFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=33)] public string Station;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=21)] public string User;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=18)] public string Domain;
        public long LogonTime, ConnectTime, DisconnectTime, LastInputTime, CurrentTime;
        public uint IncomingBytes, OutgoingBytes, IncomingFrames, OutgoingFrames;
        public uint IncomingCompressedBytes, OutgoingCompressedBytes;
    }
    [StructLayout(LayoutKind.Sequential)] struct InfoEx { public uint Level; public LevelOne Data; }
    [StructLayout(LayoutKind.Sequential)] struct Session { public uint Id; public IntPtr Station; public int State; }
    public class Result {
        public uint ConsoleSessionId;
        public int State, Flags;
        public ushort Protocol;
        public uint[] ActiveRemoteSessions;
    }
    [DllImport("kernel32.dll")] static extern uint WTSGetActiveConsoleSessionId();
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)] static extern bool WTSQuerySessionInformationW(IntPtr server, uint id, int info, out IntPtr buffer, out uint bytes);
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)] static extern bool WTSEnumerateSessionsW(IntPtr server, uint reserved, uint version, out IntPtr buffer, out uint count);
    [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr buffer);
    static ushort Protocol(uint id) {
        IntPtr buffer; uint bytes;
        if(!WTSQuerySessionInformationW(IntPtr.Zero,id,16,out buffer,out bytes)) throw new Win32Exception();
        try { if(bytes<2) throw new InvalidOperationException("Short WTS protocol result"); return (ushort)Marshal.ReadInt16(buffer); }
        finally { WTSFreeMemory(buffer); }
    }
    public static Result Read() {
        uint id=WTSGetActiveConsoleSessionId();
        if(id==0xffffffff) throw new InvalidOperationException("No attached physical console");
        IntPtr buffer; uint bytes;
        if(!WTSQuerySessionInformationW(IntPtr.Zero,id,25,out buffer,out bytes)) throw new Win32Exception();
        InfoEx info;
        try {
            if(bytes<Marshal.SizeOf(typeof(InfoEx))) throw new InvalidOperationException("Short WTSINFOEX result");
            info=(InfoEx)Marshal.PtrToStructure(buffer,typeof(InfoEx));
            if(info.Level!=1||info.Data.SessionId!=id) throw new InvalidOperationException("Unexpected WTSINFOEX identity");
        } finally { WTSFreeMemory(buffer); }
        ushort protocol=Protocol(id);
        uint count; IntPtr sessions;
        if(!WTSEnumerateSessionsW(IntPtr.Zero,0,1,out sessions,out count)) throw new Win32Exception();
        List<uint> remote=new List<uint>();
        try {
            int size=Marshal.SizeOf(typeof(Session));
            if(count>128) throw new InvalidOperationException("Unexpected session count");
            for(int i=0;i<(int)count;i++) {
                Session s=(Session)Marshal.PtrToStructure(IntPtr.Add(sessions,i*size),typeof(Session));
                if(s.State==0&&Protocol(s.Id)!=0) remote.Add(s.Id);
            }
        } finally { WTSFreeMemory(sessions); }
        if(WTSGetActiveConsoleSessionId()!=id) throw new InvalidOperationException("Console changed during query");
        return new Result {ConsoleSessionId=id,State=info.Data.SessionState,Flags=info.Data.SessionFlags,Protocol=protocol,ActiveRemoteSessions=remote.ToArray()};
    }
}
'@
    }
    $native=[C11ConsoleNative]::Read()
    $benchmark=$null
    if($BenchmarkProcessId -gt 0){
        $process=Get-Process -Id $BenchmarkProcessId -ErrorAction Stop
        $benchmark=[ordered]@{id=$process.Id;name=$process.ProcessName;sessionId=$process.SessionId;startUtc=$process.StartTime.ToUniversalTime().ToString('o')}
    }
    [ordered]@{observedUtc=[DateTime]::UtcNow.ToString('o');consoleSessionId=$native.ConsoleSessionId;connectState=$native.State;sessionFlags=$native.Flags;protocolType=$native.Protocol;activeRemoteSessions=@($native.ActiveRemoteSessions);benchmark=$benchmark;interpretation='Physical console identity, WTSActive=0, UNLOCK=1 and protocol0 required. Root separately confirms native phone view.'}
}
