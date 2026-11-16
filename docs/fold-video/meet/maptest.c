// maptest.exe: cost of one Map/Unmap of a small texture per map type/usage on the default adapter.
// Rows: usage (DYNAMIC/STAGING), format, size, map type -> median and p90 microseconds per Map+Unmap,
// with a CopyResource of the texture into a default texture after each map (as D2D does) and one Flush per 8 maps.
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
#include <stdlib.h>
#pragma comment(lib, "d3d11.lib")
static int cmp(const void *a, const void *b) { double x = *(double *)a, y = *(double *)b; return x < y ? -1 : x > y; }
static ID3D11Device *dev; static ID3D11DeviceContext *ctx; static LARGE_INTEGER fq;
static void run(const char *name, D3D11_USAGE usage, UINT cpu, DXGI_FORMAT fmt, UINT w, UINT h, D3D11_MAP mt) {
  D3D11_TEXTURE2D_DESC d = { w, h, 1, 1, fmt, { 1, 0 }, usage, usage == D3D11_USAGE_DYNAMIC ? D3D11_BIND_SHADER_RESOURCE : 0, cpu, 0 };
  ID3D11Texture2D *t = NULL, *g = NULL;
  if (FAILED(ID3D11Device_CreateTexture2D(dev, &d, NULL, &t))) { printf("%-34s create failed\n", name); return; }
  D3D11_TEXTURE2D_DESC gd = d; gd.Usage = D3D11_USAGE_DEFAULT; gd.CPUAccessFlags = 0; gd.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  ID3D11Device_CreateTexture2D(dev, &gd, NULL, &g);
  enum { N = 120 }; double us[N];
  for (int i = 0; i < N; i++) {
    LARGE_INTEGER a, b; QueryPerformanceCounter(&a);
    D3D11_MAPPED_SUBRESOURCE m;
    if (FAILED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)t, 0, mt, 0, &m))) { printf("%-34s map failed\n", name); goto out; }
    for (UINT y = 0; y < h; y++) memset((char *)m.pData + y * m.RowPitch, i & 0xff, w * (fmt == DXGI_FORMAT_A8_UNORM ? 1 : 4));
    ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)t, 0);
    QueryPerformanceCounter(&b);
    if (g) ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)g, (ID3D11Resource *)t);
    if ((i & 7) == 7) ID3D11DeviceContext_Flush(ctx);
    us[i] = (b.QuadPart - a.QuadPart) * 1e6 / fq.QuadPart;
  }
  qsort(us, N, sizeof us[0], cmp);
  printf("%-34s median %8.0f us  p90 %8.0f us  max %8.0f us\n", name, us[N / 2], us[N * 9 / 10], us[N - 1]);
out:
  if (g) ID3D11Texture2D_Release(g);
  ID3D11Texture2D_Release(t);
}
int main(void) {
  QueryPerformanceFrequency(&fq);
  D3D_FEATURE_LEVEL fl;
  if (FAILED(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx))) { printf("geen device\n"); return 1; }
  run("staging A8 38x38 MAP_WRITE", D3D11_USAGE_STAGING, D3D11_CPU_ACCESS_WRITE, DXGI_FORMAT_A8_UNORM, 38, 38, D3D11_MAP_WRITE);
  run("staging A8 66x66 MAP_WRITE", D3D11_USAGE_STAGING, D3D11_CPU_ACCESS_WRITE, DXGI_FORMAT_A8_UNORM, 66, 66, D3D11_MAP_WRITE);
  run("staging BGRA 256x256 MAP_WRITE", D3D11_USAGE_STAGING, D3D11_CPU_ACCESS_WRITE, DXGI_FORMAT_B8G8R8A8_UNORM, 256, 256, D3D11_MAP_WRITE);
  run("staging A8 66x66 MAP_READ_WRITE", D3D11_USAGE_STAGING, D3D11_CPU_ACCESS_WRITE | D3D11_CPU_ACCESS_READ, DXGI_FORMAT_A8_UNORM, 66, 66, D3D11_MAP_READ_WRITE);
  run("dynamic A8 66x66 WRITE_DISCARD", D3D11_USAGE_DYNAMIC, D3D11_CPU_ACCESS_WRITE, DXGI_FORMAT_A8_UNORM, 66, 66, D3D11_MAP_WRITE_DISCARD);
  run("dynamic BGRA 256x256 WRITE_DISCARD", D3D11_USAGE_DYNAMIC, D3D11_CPU_ACCESS_WRITE, DXGI_FORMAT_B8G8R8A8_UNORM, 256, 256, D3D11_MAP_WRITE_DISCARD);
  return 0;
}
