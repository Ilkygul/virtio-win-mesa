// gpumem.exe: what Windows reports about GPU memory, per adapter.
//  - DXGI: DedicatedVideoMemory / DedicatedSystemMemory / SharedSystemMemory, and QueryVideoMemoryInfo
//    (LOCAL = "dedicated", NON_LOCAL = "shared") budget + usage for this process.
//  - D3DKMTQueryStatistics: per segment the size, commit limit, bytes committed/resident and the aperture flag
//    (what Task Manager sums: non-aperture segments = dedicated, aperture + system = shared).
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <dxgi1_4.h>
#include <d3dkmthk.h>
#include <stdio.h>
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "gdi32.lib")
#define MB(x) ((double)(x) / 1048576.0)

static void kmt(LUID luid) {
  D3DKMT_OPENADAPTERFROMLUID o = { 0 }; o.AdapterLuid = luid;
  if (D3DKMTOpenAdapterFromLuid(&o)) { printf("  kmt: open failed\n"); return; }
  D3DKMT_QUERYSTATISTICS q = { 0 }; q.Type = D3DKMT_QUERYSTATISTICS_ADAPTER; q.AdapterLuid = luid;
  if (D3DKMTQueryStatistics(&q)) { printf("  kmt: adapter stats failed\n"); goto out; }
  UINT n = q.QueryResult.AdapterInformation.NbSegments;
  printf("  kmt: %u segments\n", n);
  for (UINT i = 0; i < n; i++) {
    D3DKMT_QUERYSTATISTICS s = { 0 }; s.Type = D3DKMT_QUERYSTATISTICS_SEGMENT; s.AdapterLuid = luid;
    s.QuerySegment.SegmentId = i;
    if (D3DKMTQueryStatistics(&s)) { printf("  seg %u: query failed\n", i); continue; }
    D3DKMT_QUERYSTATISTICS_SEGMENT_INFORMATION *g = &s.QueryResult.SegmentInformation;
    printf("  seg %u: commitlimit %.0f MB, committed %.1f MB, resident %.1f MB, aperture %u, systeemgeheugen %u\n",
           i + 1, MB(g->CommitLimit), MB(g->BytesCommitted),
           MB(g->BytesResident), g->Aperture, (UINT)g->SegmentProperties.SystemMemory);
  }
out:;
  D3DKMT_CLOSEADAPTER c = { o.hAdapter }; D3DKMTCloseAdapter(&c);
}

int main(void) {
  IDXGIFactory4 *f = NULL;
  if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory4, (void **)&f))) { printf("geen DXGI\n"); return 1; }
  IDXGIAdapter1 *a1 = NULL;
  for (UINT i = 0; IDXGIFactory4_EnumAdapters1(f, i, &a1) != DXGI_ERROR_NOT_FOUND; i++) {
    DXGI_ADAPTER_DESC1 d; IDXGIAdapter1_GetDesc1(a1, &d);
    printf("adapter %u: %ls luid %08lx:%08lx flags %u\n", i, d.Description, d.AdapterLuid.HighPart, d.AdapterLuid.LowPart, d.Flags);
    printf("  dxgi: DedicatedVideoMemory %.0f MB, DedicatedSystemMemory %.0f MB, SharedSystemMemory %.0f MB\n",
           MB(d.DedicatedVideoMemory), MB(d.DedicatedSystemMemory), MB(d.SharedSystemMemory));
    IDXGIAdapter3 *a3 = NULL;
    if (SUCCEEDED(IDXGIAdapter1_QueryInterface(a1, &IID_IDXGIAdapter3, (void **)&a3))) {
      DXGI_QUERY_VIDEO_MEMORY_INFO l = { 0 }, n = { 0 };
      IDXGIAdapter3_QueryVideoMemoryInfo(a3, 0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &l);
      IDXGIAdapter3_QueryVideoMemoryInfo(a3, 0, DXGI_MEMORY_SEGMENT_GROUP_NON_LOCAL, &n);
      printf("  dxgi budget: local %.0f MB (proces gebruikt %.1f), non-local %.0f MB (proces gebruikt %.1f)\n",
             MB(l.Budget), MB(l.CurrentUsage), MB(n.Budget), MB(n.CurrentUsage));
      IDXGIAdapter3_Release(a3);
    }
    if (!(d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) kmt(d.AdapterLuid);
    IDXGIAdapter1_Release(a1);
  }
  IDXGIFactory4_Release(f);
  return 0;
}
