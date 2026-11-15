// drawbench: N small draws per frame straight into a flip-model swapchain back buffer; reports fps.
// drawbench.exe <draws> <seconds> <outfile> [mode]
// mode: upd = UpdateSubresource per draw (default), none = draws only (offset from SV_VertexID),
//       map = Map(WRITE_DISCARD) per draw, set = VSSetConstantBuffers1 offsets into one big buffer
#include <windows.h>
#include <d3d11_1.h>
#include <dxgi1_2.h>
#include <d3dcompiler.h>
#include <cstdio>
#include <cstdlib>
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")
#pragma comment(lib, "user32.lib")
static const char *kShader =
  "cbuffer C : register(b0) { float4 off; };"
  "float4 vs(uint id : SV_VertexID) : SV_Position {"
  "  float2 p[3] = { float2(0,0.04), float2(0.03,-0.03), float2(-0.03,-0.03) };"
  "  return float4(p[id] + off.xy, 0, 1); }"
  "float4 ps() : SV_Target { return float4(0.9, 0.5, 0.1, 1); }";
int WINAPI WinMain(HINSTANCE hi, HINSTANCE, LPSTR, int) {
  int argc; LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  int draws = argc > 1 ? _wtoi(argv[1]) : 400, secs = argc > 2 ? _wtoi(argv[2]) : 10;
  const wchar_t *out = argc > 3 ? argv[3] : L"C:\\Users\\Public\\meet\\drawbench.txt";
  const wchar_t *mode = argc > 4 ? argv[4] : L"upd";
  int M = !wcscmp(mode, L"none") ? 1 : !wcscmp(mode, L"map") ? 2 : !wcscmp(mode, L"set") ? 3 : 0;
  WNDCLASSW wc = {}; wc.lpfnWndProc = DefWindowProcW; wc.hInstance = hi; wc.lpszClassName = L"drawbench";
  RegisterClassW(&wc);
  HWND w = CreateWindowW(L"drawbench", L"drawbench", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 200, 100, 900, 700, 0, 0, hi, 0);
  ID3D11Device *dev; ID3D11DeviceContext *ctx; D3D_FEATURE_LEVEL fl;
  if (FAILED(D3D11CreateDevice(0, D3D_DRIVER_TYPE_HARDWARE, 0, 0, 0, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx))) return 1;
  IDXGIDevice *xd; dev->QueryInterface(__uuidof(IDXGIDevice), (void **)&xd);
  IDXGIAdapter *ad; xd->GetAdapter(&ad); IDXGIFactory2 *f; ad->GetParent(__uuidof(IDXGIFactory2), (void **)&f);
  DXGI_ADAPTER_DESC adesc; ad->GetDesc(&adesc);
  DXGI_SWAP_CHAIN_DESC1 sd = {}; sd.Width = 880; sd.Height = 660; sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  sd.SampleDesc.Count = 1; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount = 2;
  sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  IDXGISwapChain1 *sc; if (FAILED(f->CreateSwapChainForHwnd(dev, w, &sd, 0, 0, &sc))) return 2;
  ID3DBlob *vb, *pb, *err;
  D3DCompile(kShader, strlen(kShader), 0, 0, 0, "vs", "vs_4_0", 0, 0, &vb, &err);
  D3DCompile(kShader, strlen(kShader), 0, 0, 0, "ps", "ps_4_0", 0, 0, &pb, &err);
  ID3D11VertexShader *vs; ID3D11PixelShader *ps;
  dev->CreateVertexShader(vb->GetBufferPointer(), vb->GetBufferSize(), 0, &vs);
  dev->CreatePixelShader(pb->GetBufferPointer(), pb->GetBufferSize(), 0, &ps);
  D3D11_BUFFER_DESC bd = {}; bd.ByteWidth = 16; bd.Usage = M == 2 ? D3D11_USAGE_DYNAMIC : D3D11_USAGE_DEFAULT;
  bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER; bd.CPUAccessFlags = M == 2 ? D3D11_CPU_ACCESS_WRITE : 0;
  ID3D11Buffer *cb; dev->CreateBuffer(&bd, 0, &cb);
  ID3D11DeviceContext1 *ctx1 = 0; ctx->QueryInterface(__uuidof(ID3D11DeviceContext1), (void **)&ctx1);
  D3D11_BUFFER_DESC bb2 = {}; bb2.ByteWidth = 256 * 4096; bb2.Usage = D3D11_USAGE_DYNAMIC; bb2.BindFlags = D3D11_BIND_CONSTANT_BUFFER; bb2.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
  ID3D11Buffer *big; dev->CreateBuffer(&bb2, 0, &big);
  D3D11_VIEWPORT vp = {0, 0, 880, 660, 0, 1};
  LARGE_INTEGER fq, t0, t; QueryPerformanceFrequency(&fq); QueryPerformanceCounter(&t0);
  long frames = 0; MSG m;
  for (;;) {
    while (PeekMessageW(&m, 0, 0, 0, PM_REMOVE)) DispatchMessageW(&m);
    ID3D11Texture2D *bb; sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&bb);
    ID3D11RenderTargetView *rtv; dev->CreateRenderTargetView(bb, 0, &rtv);
    float clr[4] = {0.1f, 0.2f, 0.3f, 1};
    ctx->ClearRenderTargetView(rtv, clr); ctx->OMSetRenderTargets(1, &rtv, 0); ctx->RSSetViewports(1, &vp);
    ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST); ctx->VSSetShader(vs, 0, 0); ctx->PSSetShader(ps, 0, 0);
    ctx->VSSetConstantBuffers(0, 1, &cb);
    if (M == 3) { // one Map of a big buffer, then per draw only a constant-buffer offset
      D3D11_MAPPED_SUBRESOURCE ms; ctx->Map(big, 0, D3D11_MAP_WRITE_DISCARD, 0, &ms);
      for (int i = 0; i < draws && i < 4096; ++i) { float *o = (float *)((char *)ms.pData + i * 256);
        o[0] = -0.9f + 1.8f * ((i * 37 + frames * 3) % 100) / 100.f; o[1] = -0.9f + 1.8f * ((i * 53) % 100) / 100.f; o[2] = o[3] = 0; }
      ctx->Unmap(big, 0);
    }
    for (int i = 0; i < draws; ++i) {
      float o[4] = { -0.9f + 1.8f * ((i * 37 + frames * 3) % 100) / 100.f, -0.9f + 1.8f * ((i * 53) % 100) / 100.f, 0, 0 };
      if (M == 0) ctx->UpdateSubresource(cb, 0, 0, o, 0, 0);
      else if (M == 2) { D3D11_MAPPED_SUBRESOURCE ms; ctx->Map(cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &ms); memcpy(ms.pData, o, 16); ctx->Unmap(cb, 0); }
      else if (M == 3 && ctx1) { UINT first = i * 16, num = 16; ctx1->VSSetConstantBuffers1(0, 1, &big, &first, &num); }
      ctx->Draw(3, 0);
    }
    sc->Present(0, 0); rtv->Release(); bb->Release(); ++frames;
    QueryPerformanceCounter(&t);
    double s = double(t.QuadPart - t0.QuadPart) / fq.QuadPart;
    if (s >= secs) {
      FILE *o = _wfopen(out, L"w");
      if (o) { fwprintf(o, L"mode=%s draws=%d frames=%ld secs=%.2f fps=%.1f adapter=%s\n", mode, draws, frames, s, frames / s, adesc.Description); fclose(o); }
      return 0;
    }
  }
}
