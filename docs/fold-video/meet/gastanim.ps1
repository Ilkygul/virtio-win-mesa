# gastanim.ps1 (interactive, via meethulp mode 'gastanim'): open and close the Start menu 3 times with SendInput-level
# key events (works while the phone screen is off); the caller records a WPR GPU trace around it.
Add-Type 'using System; using System.Runtime.InteropServices; public static class K { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, IntPtr e); }'
for ($r = 1; $r -le 3; $r++) {
  Start-Sleep -m 1000; [K]::keybd_event(0x5B, 0, 0, [IntPtr]::Zero); [K]::keybd_event(0x5B, 0, 2, [IntPtr]::Zero)
  Start-Sleep -m 1500; [K]::keybd_event(0x1B, 0, 0, [IntPtr]::Zero); [K]::keybd_event(0x1B, 0, 2, [IntPtr]::Zero) }
'ok'
