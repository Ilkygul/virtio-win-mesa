// gltest.exe <seconds> <outfile>: WGL context, report GL_RENDERER/VERSION and fps of 2000 triangles per frame.
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#pragma comment(lib, "opengl32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "winmm.lib")
#include <mmsystem.h>
int WINAPI WinMain(HINSTANCE hi, HINSTANCE p, LPSTR cmd, int show) {
  if (GetEnvironmentVariableA("GLTEST_TIMER1", NULL, 0)) timeBeginPeriod(1);
  int secs = 8; char out[MAX_PATH] = "C:\\Users\\Public\\meet\\gltest.txt";
  if (cmd && *cmd) sscanf(cmd, "%d %259s", &secs, out);
  WNDCLASSA wc = {0}; wc.lpfnWndProc = DefWindowProcA; wc.hInstance = hi; wc.lpszClassName = "gltest"; wc.style = CS_OWNDC;
  RegisterClassA(&wc);
  HWND w = CreateWindowA("gltest", "gltest (OpenGL)", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 300, 150, 800, 600, 0, 0, hi, 0);
  HDC dc = GetDC(w);
  PIXELFORMATDESCRIPTOR pfd = { sizeof(pfd), 1, PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER, PFD_TYPE_RGBA, 32 };
  pfd.cDepthBits = 24; SetPixelFormat(dc, ChoosePixelFormat(dc, &pfd), &pfd);
  HGLRC rc = wglCreateContext(dc); wglMakeCurrent(dc, rc);
  const char *ren = (const char *)glGetString(GL_RENDERER), *ver = (const char *)glGetString(GL_VERSION);
  LARGE_INTEGER fq, t0, t; QueryPerformanceFrequency(&fq); QueryPerformanceCounter(&t0); long frames = 0; MSG m;
  for (;;) {
    while (PeekMessageA(&m, 0, 0, 0, PM_REMOVE)) DispatchMessageA(&m);
    glClearColor(0.1f, 0.15f, 0.25f, 1); glClear(GL_COLOR_BUFFER_BIT);
    glBegin(GL_TRIANGLES);
    for (int i = 0; i < 2000; i++) {
      float x = -0.95f + 1.9f * ((i * 37 + frames * 2) % 200) / 200.f, y = -0.95f + 1.9f * ((i * 53) % 200) / 200.f;
      glColor3f(0.9f, 0.5f + 0.4f * (i % 2), 0.1f); glVertex2f(x, y + 0.02f); glVertex2f(x + 0.015f, y - 0.015f); glVertex2f(x - 0.015f, y - 0.015f);
    }
    glEnd(); SwapBuffers(dc); ++frames;
    QueryPerformanceCounter(&t); double s = (double)(t.QuadPart - t0.QuadPart) / fq.QuadPart;
    if (s >= secs) {
      FILE *o = fopen(out, "w");
      if (o) { fprintf(o, "renderer=%s | version=%s | frames=%ld secs=%.2f fps=%.1f\n", ren ? ren : "?", ver ? ver : "?", frames, s, frames / s); fclose(o); }
      return 0;
    }
  }
}

