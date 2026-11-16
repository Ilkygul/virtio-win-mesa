Add-Type -Name C -Namespace M -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);'
for ($i = 0; $i -lt 20; $i++) { [M.C]::mouse_event(0x8001, 30000 + $i * 100, 30000, 0, [IntPtr]::Zero); Start-Sleep -m 20 }
