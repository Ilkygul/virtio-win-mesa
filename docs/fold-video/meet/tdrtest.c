// tdrtest.exe [type]: force a GPU timeout-detection-and-recovery on every adapter through D3DKMTEscape
// (D3DKMT_ESCAPE_TDRDBGCTRL, the route dxcap -forcetdr uses). type 0 = FORCETDR (default), 8 = ENGINETDR.
// Needs administrator rights and TdrDebugMode 2 (recover) in GraphicsDrivers.
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
typedef UINT D3DKMT_HANDLE;
typedef struct { D3DKMT_HANDLE hAdapter; LUID AdapterLuid; ULONG NumOfSources; BOOL bPrecisePresentRegionsPreferred; } ADAPTERINFO;
typedef struct { ULONG NumAdapters; ADAPTERINFO *pAdapters; } ENUMADAPTERS2;
typedef struct { D3DKMT_HANDLE hAdapter; D3DKMT_HANDLE hDevice; UINT Type; UINT Flags; void *pPrivateDriverData; UINT PrivateDriverDataSize; D3DKMT_HANDLE hContext; } ESCAPE;
typedef struct { D3DKMT_HANDLE hAdapter; } CLOSEADAPTER;
typedef struct { D3DKMT_HANDLE hAdapter; UINT Type; void *pData; UINT Size; } QAI;
typedef struct { WCHAR Adapter[MAX_PATH], Bios[MAX_PATH], Dac[MAX_PATH], Chip[MAX_PATH]; } REGINFO;
typedef LONG (APIENTRY *PFN)(void *);
int main(int argc, char **argv) {
  int hang = argc > 1 && argv[1][0] == 'h';   // "hang": VIOGPU_TEST_HANG private escape (F94, TestHangEscape=1)
  UINT ctl = argc > 1 && !hang ? (UINT)atoi(argv[1]) : 0;
  static BYTE priv[4096]; *(USHORT *)priv = 0x0F0; *(USHORT *)(priv + 2) = 4;
  HMODULE g = LoadLibraryA("gdi32.dll");
  PFN qa = (PFN)GetProcAddress(g, "D3DKMTQueryAdapterInfo"); PFN en = (PFN)GetProcAddress(g, "D3DKMTEnumAdapters2"), es = (PFN)GetProcAddress(g, "D3DKMTEscape"), cl = (PFN)GetProcAddress(g, "D3DKMTCloseAdapter");
  ADAPTERINFO a[16]; ENUMADAPTERS2 e = { 16, a };
  LONG st = en(&e); printf("EnumAdapters2 0x%08lx, %lu adapters\n", st, e.NumAdapters);
  for (ULONG i = 0; i < e.NumAdapters; i++) {
    REGINFO r = {0}; QAI q = { a[i].hAdapter, 8 /* KMTQAITYPE_ADAPTERREGISTRYINFO */, &r, sizeof r }; LONG qs = qa(&q);
    printf("adapter %lu luid %08lx:%08lx q 0x%08lx '%ls' '%ls'\n", i, a[i].AdapterLuid.HighPart, a[i].AdapterLuid.LowPart, qs, r.Adapter, r.Chip);
    if (wcsstr(r.Adapter, L"Vio") || wcsstr(r.Adapter, L"VIO") || wcsstr(r.Adapter, L"VIRTIO") || wcsstr(r.Chip, L"Vio")) {   // the virtio GPU only
      ESCAPE x = { a[i].hAdapter, 0, 2 /* D3DKMT_ESCAPE_TDRDBGCTRL */, 0, &ctl, sizeof ctl, 0 };
      if (hang) { x.Type = 0 /* D3DKMT_ESCAPE_DRIVERPRIVATE */; x.pPrivateDriverData = priv; x.PrivateDriverDataSize = sizeof priv; }
      SYSTEMTIME t; GetLocalTime(&t);
      st = es(&x); printf("%02d:%02d:%02d.%03d Escape %s %u -> 0x%08lx\n", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds, hang ? "TEST_HANG" : "TDRDBGCTRL", ctl, st);
    }
    CLOSEADAPTER c = { a[i].hAdapter }; cl(&c);
  }
  return 0;
}
