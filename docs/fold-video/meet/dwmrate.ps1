# dwmrate.ps1: DWM composition timing (refresh rate/period and frames composed over 2 s while the mouse drags)
Add-Type @'
using System; using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, Pack = 1)] public struct UNSIGNED_RATIO { public uint n, d; }
[StructLayout(LayoutKind.Sequential, Pack = 1)] public struct DWM_TIMING_INFO {
  public uint cbSize; public UNSIGNED_RATIO rateRefresh; public ulong qpcRefreshPeriod; public UNSIGNED_RATIO rateCompose;
  public ulong qpcVBlank, cRefresh; public uint cDXRefresh; public ulong qpcCompose, cFrame; public uint cDXPresent;
  public ulong cRefreshFrame, cFrameSubmitted; public uint cDXPresentSubmitted; public ulong cFrameConfirmed; public uint cDXPresentConfirmed;
  public ulong cRefreshConfirmed; public uint cDXRefreshConfirmed; public ulong cFramesLate; public uint cFramesOutstanding;
  public ulong cFrameDisplayed, qpcFrameDisplayed, cRefreshFrameDisplayed, cFrameComplete, qpcFrameComplete, cFramePending, qpcFramePending;
  public ulong cFramesDisplayed, cFramesComplete, cFramesPending, cFramesAvailable, cFramesDropped, cFramesMissed, cRefreshNextDisplayed, cRefreshNextPresented;
  public ulong cRefreshesDisplayed, cRefreshesPresented, cRefreshStarted, cPixelsReceived, cPixelsDrawn, cBuffersEmpty; }
public static class Dw { [DllImport("dwmapi.dll")] public static extern int DwmGetCompositionTimingInfo(IntPtr h, ref DWM_TIMING_INFO t);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e); }
'@
function T { $t = New-Object DWM_TIMING_INFO; $t.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($t); $hr = [Dw]::DwmGetCompositionTimingInfo([IntPtr]::Zero, [ref]$t); $t }
$a = T; $sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt 2000) { $f = $sw.ElapsedMilliseconds / 2000; [Dw]::mouse_event(0x8001, [int](20000 + 20000 * $f), 30000, 0, [IntPtr]::Zero); Start-Sleep -m 2 }
$b = T
"refresh $($a.rateRefresh.n)/$($a.rateRefresh.d) periode-qpc $($a.qpcRefreshPeriod) refreshes/2s $($b.cRefresh - $a.cRefresh) frames/2s $($b.cFrame - $a.cFrame)" | Set-Content C:\Users\Public\meet\dwmrate.txt
