// curtest.exe <seconds> [invert]: a topmost window (0,0)-(screen) whose cursor is a masked-color cursor
// (colour bitmap without alpha + AND mask). With "invert" a few pixels have AND=1 and colour != 0 (XOR).
#include <windows.h>
#include <stdlib.h>
#include <string.h>
static HCURSOR cur;
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l) {
  if (m == WM_SETCURSOR) { SetCursor(cur); return TRUE; }
  if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcA(h, m, w, l);
}
int WINAPI WinMain(HINSTANCE hi, HINSTANCE p, LPSTR cmd, int show) {
  int secs = atoi(cmd); if (secs <= 0) secs = 8; int inv = strstr(cmd, "invert") != NULL;
  BITMAPINFO bi = {0}; bi.bmiHeader.biSize = sizeof bi.bmiHeader; bi.bmiHeader.biWidth = 32; bi.bmiHeader.biHeight = -32;
  bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32;
  DWORD *px; HDC dc = GetDC(NULL); HBITMAP col = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, (void **)&px, NULL, 0); ReleaseDC(NULL, dc);
  BYTE mask[32 * 4];
  for (int y = 0; y < 32; y++) { DWORD m = 0;
    for (int x = 0; x < 32; x++) {
      int in = x < 24 && y < 24 && x >= y / 2;                       // a wedge-shaped arrow
      int edge = in && (x == y / 2 || x == 23 || y == 23 || y == 0);
      px[y * 32 + x] = in ? (edge ? 0x00FFFFFF : 0x00D02020) : 0;     // white edge, red fill, no alpha
      if (!in) m |= 0x80000000u >> x;                                 // AND=1 outside: transparent
      if (inv && y >= 26 && y < 30 && x < 12) { m |= 0x80000000u >> x; px[y * 32 + x] = 0x00FFFFFF; }  // XOR bar
    }
    mask[y * 4] = (BYTE)(m >> 24); mask[y * 4 + 1] = (BYTE)(m >> 16); mask[y * 4 + 2] = (BYTE)(m >> 8); mask[y * 4 + 3] = (BYTE)m; }
  HBITMAP msk = CreateBitmap(32, 32, 1, 1, mask);
  ICONINFO ii = { FALSE, 1, 1, msk, col }; cur = CreateIconIndirect(&ii);
  WNDCLASSA wc = {0}; wc.lpfnWndProc = wp; wc.hInstance = hi; wc.lpszClassName = "curtest"; wc.hbrBackground = (HBRUSH)GetStockObject(GRAY_BRUSH);
  RegisterClassA(&wc);
  HWND w = CreateWindowExA(WS_EX_TOPMOST, "curtest", "curtest", WS_POPUP | WS_VISIBLE, 0, 0, GetSystemMetrics(0), GetSystemMetrics(1), 0, 0, hi, 0);
  SetForegroundWindow(w); SetTimer(w, 1, secs * 1000, NULL);
  MSG msg; while (GetMessageA(&msg, 0, 0, 0) > 0) { if (msg.message == WM_TIMER && msg.hwnd == w && msg.wParam == 1) DestroyWindow(w); DispatchMessageA(&msg); }
  return 0;
}
