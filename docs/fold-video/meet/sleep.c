// sleep.exe x0 y0 x1 y1 ms: left-button drag from (x0,y0) to (x1,y1) in ms milliseconds with a mouse move
// every 2 ms (QPC-timed, like a 500 Hz mouse), then back. Coordinates in screen pixels.
#include <windows.h>
#include <stdlib.h>
static int W, H;
static void at(int x, int y, DWORD f) { mouse_event(MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | f, x * 65535 / (W - 1), y * 65535 / (H - 1), 0, 0); }
int WINAPI WinMain(HINSTANCE a, HINSTANCE b, LPSTR c, int d) {
  SetProcessDPIAware(); timeBeginPeriod(1);
  W = GetSystemMetrics(SM_CXSCREEN); H = GetSystemMetrics(SM_CYSCREEN);
  int v[5] = {1300, 112, 1800, 400, 2500}; char *p = c;
  for (int i = 0; i < 5 && *p; i++) v[i] = strtol(p, &p, 10);
  LARGE_INTEGER fq, t0, t; QueryPerformanceFrequency(&fq);
  at(v[0], v[1], 0); Sleep(100); at(v[0], v[1], MOUSEEVENTF_LEFTDOWN);
  QueryPerformanceCounter(&t0); LONGLONG next = 0, step = fq.QuadPart / 500;
  for (;;) {
    QueryPerformanceCounter(&t); LONGLONG e = t.QuadPart - t0.QuadPart;
    double f = (double)e / fq.QuadPart * 1000.0 / v[4]; if (f > 1) break;
    if (e >= next) { at(v[0] + (int)((v[2] - v[0]) * f), v[1] + (int)((v[3] - v[1]) * f), 0); next += step; }
    else if (next - e > fq.QuadPart / 1000) Sleep(1);
  }
  at(v[2], v[3], MOUSEEVENTF_LEFTUP); Sleep(100);
  at(v[2], v[3], MOUSEEVENTF_LEFTDOWN); at(v[0], v[1], 0); at(v[0], v[1], MOUSEEVENTF_LEFTUP);
  return 0;
}
