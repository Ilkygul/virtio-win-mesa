# Guest helper for meet.sh (runs in the interactive session via scheduled task "meethulp").
# Mode in C:\Users\Public\meet\mode.txt: explorer | edge | video | quality | close
$ErrorActionPreference = 'SilentlyContinue'
$d = 'C:\Users\Public\meet'
$mode = (Get-Content "$d\mode.txt" -Raw).Trim()
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
}
'@
$ScrW = [W]::GetSystemMetrics(0); $ScrH = [W]::GetSystemMetrics(1)   # screen size in this process's coordinates
function Place($h) { [W]::ShowWindow($h, 9) | Out-Null; [W]::SetWindowPos($h, [IntPtr]::Zero, 200, 100, 1400, 850, 0x40) | Out-Null; [W]::SetForegroundWindow($h) | Out-Null }
function WaitWin($name, $title) {
  for ($i = 0; $i -lt 40; $i++) {
    $p = Get-Process $name | ?{ $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like $title } | select -First 1
    if ($p) { return $p.MainWindowHandle }; Start-Sleep -Milliseconds 250 }
}
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$eargs = "--user-data-dir=$d\edge --remote-debugging-port=9333 --no-first-run --window-position=200,100 --window-size=1400,850 --autoplay-policy=no-user-gesture-required"
switch ($mode) {
  'explorer' { Start-Process explorer.exe 'C:\Windows\System32'; $h = WaitWin explorer '*System32*'; if ($h) { Place $h; 'ok' } else { 'geen venster' } }
  'edge'     { Start-Process $edge "$eargs https://en.wikipedia.org/wiki/Microsoft_Windows"; Start-Sleep 5; $h = WaitWin msedge '*'; if ($h) { Place $h; 'ok' } }
  'video'    { Start-Process $edge "$eargs --start-maximized https://www.youtube.com/watch?v=$((Get-Content "$d\video.txt" -Raw).Trim())"; Start-Sleep 5; $h = WaitWin msedge '*'; if ($h) { [W]::ShowWindow($h, 3) | Out-Null; [W]::SetForegroundWindow($h) | Out-Null; 'ok' } }
  { $_ -in 'quality','play' } {
    # getVideoPlaybackQuality() of the first <video> via the DevTools protocol
    $t = (Invoke-RestMethod http://127.0.0.1:9333/json) | ?{ $_.type -eq 'page' -and $_.url -like '*youtube*' } | select -First 1
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.ConnectAsync([Uri]$t.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
    $q = if (Test-Path "$d\quality.txt") { (Get-Content "$d\quality.txt" -Raw).Trim() } else { 'hd1080' }
    $js = if ($mode -eq 'play') { "(()=>{for(const b of document.querySelectorAll('button')){if(/reject all|alles afwijzen/i.test(b.innerText)){b.click()}};const p=document.getElementById('movie_player');if(p&&p.setPlaybackQualityRange){p.setPlaybackQualityRange('QQQ','QQQ')};const v=document.querySelector('video');if(v){v.muted=true;v.play()};return 'play '+(v?v.videoHeight:-1)})()".Replace('QQQ', $q) } else { "(()=>{const v=document.querySelector('video');const q=v.getVideoPlaybackQuality();return JSON.stringify({t:v.currentTime,paused:v.paused,total:q.totalVideoFrames,dropped:q.droppedVideoFrames,w:v.videoWidth,h:v.videoHeight})})()" }
    $msg = '{"id":1,"method":"Runtime.evaluate","params":{"expression":' + (ConvertTo-Json $js) + ',"returnByValue":true}}'
    $b = [Text.Encoding]::UTF8.GetBytes($msg)
    $ws.SendAsync([ArraySegment[byte]]$b, 'Text', $true, [Threading.CancellationToken]::None).Wait()
    $buf = New-Object byte[] 65536; $r = $ws.ReceiveAsync([ArraySegment[byte]]$buf, [Threading.CancellationToken]::None); $r.Wait()
    $j = [Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count) | ConvertFrom-Json
    $j.result.result.value
  }
  'cursor'   { # move the mouse (no buttons; absolute moves also unhide the cursor after touch): 3 s across the screen in 4 ms steps
    Add-Type -Name C -Namespace M -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 3000) { $f = $sw.ElapsedMilliseconds / 3000; [M.C]::mouse_event(0x8001, [int](65535 * (300 + 1800 * $f) / $ScrW), [int](65535 * (500 + 300 * $f) / $ScrH), 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 4 }
    'ok' }
  'drag'     { # drag of the test window's title bar (empty tab-strip area at 1300,112) to 1800,400 in 2.5 s and back:
               # sleep.exe moves the mouse every 2 ms on a QPC clock (a PowerShell sleep loop only manages ~64 moves/s)
    Start-Process "$d\sleep.exe" -ArgumentList '1300 112 1800 400 2500' -Wait; 'ok' }
  'apps'     { # visual check: Task Manager, Explorer and Windows Terminal side by side
    Start-Process taskmgr.exe; Start-Process conhost.exe 'cmd.exe /k dir C:\'; Start-Process explorer.exe 'C:\Users'; Start-Process 'shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App'
    Start-Sleep 5
    $t = WaitWin Taskmgr '*'; if ($t) { [W]::ShowWindow($t, 9) | Out-Null; [W]::SetWindowPos($t, [IntPtr]::Zero, 20, 20, 900, 700, 0x40) | Out-Null }
    $e = WaitWin explorer '*Users*'; if ($e) { [W]::SetWindowPos($e, [IntPtr]::Zero, 940, 20, 800, 520, 0x40) | Out-Null }
    $w = WaitWin WindowsTerminal '*'; if ($w) { [W]::SetWindowPos($w, [IntPtr]::Zero, 940, 560, 800, 480, 0x40) | Out-Null }
    'ok' }
  'appsclose' { Get-Process Taskmgr, WindowsTerminal | Stop-Process -Force; (New-Object -ComObject Shell.Application).Windows() | %{ $_.Quit() }; 'ok' }
  'bench'    { # drawbench.exe <draws> <seconds>: N draws per frame straight into a flip swapchain
    $a = (Get-Content "$d\bench.txt" -Raw).Trim() -split ' '
    Remove-Item "$d\drawbench.txt" -EA 0
    Start-Process "$d\drawbench.exe" -ArgumentList (@($a[0], $a[1], "$d\drawbench.txt") + @($a | Select -Skip 2)) -Wait
    Get-Content "$d\drawbench.txt" }
  'fx'       { # visual effects on/off (animations, transparency, ...) in this interactive session: fx.txt = 1 | 0
               & 'C:\Users\Public\win-opt\effects.ps1' -on:([bool][int]((Get-Content "$d\fx.txt" -Raw).Trim())); 'fx ' + (Get-Content "$d\fx.txt" -Raw).Trim() }
  'minmax'   { # minimise and restore the System32 Explorer test window (window animation), once
               $h = WaitWin explorer '*System32*'; if (-not $h) { 'geen venster'; break }
               [W]::ShowWindow($h, 6) | Out-Null; Start-Sleep -Milliseconds 1500; [W]::ShowWindow($h, 9) | Out-Null; [W]::SetForegroundWindow($h) | Out-Null; 'ok' }
  'gastanim' { & "$d\gastanim.ps1" }
  'close'    { Get-Process msedge | ?{ $_.Path -and (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -like "*$d\edge*" } | Stop-Process -Force
               (New-Object -ComObject Shell.Application).Windows() | ?{ $_.LocationURL -like '*System32*' } | %{ $_.Quit() }; 'ok' }
}
