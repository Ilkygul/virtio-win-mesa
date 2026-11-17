# modereset.ps1: re-apply the current display mode with CDS_RESET (forces a full mode set at the same size/rate)
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class MR {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DM {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string n; public short sv, dv, sz, ex; public int f;
    public int px, py, ori, fo; public short c, d, y, t, col; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string fn;
    public short lp; public int bpp, w, h, df, hz; public int a, b, c2, d2, e, g, pw, ph; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettings(string d, int m, ref DM dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int ChangeDisplaySettingsEx(string d, ref DM dm, IntPtr h, int f, IntPtr p);
  public static string Bump() { DM cur = new DM(); cur.sz = (short)Marshal.SizeOf(typeof(DM)); EnumDisplaySettings(null, -1, ref cur);
    DM tmp = cur; tmp.w = (cur.w == 1024) ? 1920 : 1024; tmp.h = (cur.w == 1024) ? 1080 : 768; tmp.f = 0x80000 | 0x100000;
    int r1 = ChangeDisplaySettingsEx(null, ref tmp, IntPtr.Zero, 0, IntPtr.Zero); System.Threading.Thread.Sleep(1500);
    cur.f = 0x80000 | 0x100000 | 0x400000; int r2 = ChangeDisplaySettingsEx(null, ref cur, IntPtr.Zero, 0, IntPtr.Zero);
    return cur.w + "x" + cur.h + "@" + cur.hz + " via " + tmp.w + "x" + tmp.h + " r=" + r1 + "/" + r2; }
  public static string Go(int flags) { DM dm = new DM(); dm.sz = (short)Marshal.SizeOf(typeof(DM));
    EnumDisplaySettings(null, -1, ref dm); dm.f = 0x80000 | 0x100000 | 0x400000;
    int r = ChangeDisplaySettingsEx(null, ref dm, IntPtr.Zero, flags, IntPtr.Zero); return dm.w + "x" + dm.h + "@" + dm.hz + " r=" + r; } }
'@
# Windows sometimes boots with DWM's backdrop (Start/acrylic) fully transparent; only a mode change to another SIZE
# clears it (same-mode reset, DWM/Explorer/Start restart do not). Briefly switch to 1024x768 and back, not saved.
$r = [MR]::Bump()
"$(Get-Date -f s) modereset $r" | Add-Content C:\Users\Public\win-opt\startfix.log
