// sampler.exe <processname> <ms>: suspend/GetThreadContext sampling (~1 kHz) of every thread of the first process with
// that image name; prints per thread with >= 20 samples the top modules (+ export symbol via dbghelp when known).
#include <windows.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <dbghelp.h>
#include <stdio.h>
#include <stdlib.h>
#pragma comment(lib, "dbghelp.lib")
#pragma comment(lib, "winmm.lib")
typedef struct { DWORD tid; HANDLE h; int n; DWORD64 *pc; } T;
typedef struct { char name[160]; int n; } E;
static int cmpe(const void *a, const void *b) { return ((E *)b)->n - ((E *)a)->n; }
int main(int argc, char **argv) {
  if (argc < 3) { printf("sampler <exe> <ms>\n"); return 1; }
  DWORD pid = 0; PROCESSENTRY32 pe = { sizeof pe }; HANDLE s = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  for (BOOL ok = Process32First(s, &pe); ok; ok = Process32Next(s, &pe)) if (!_stricmp(pe.szExeFile, argv[1])) { pid = pe.th32ProcessID; break; }
  CloseHandle(s); if (!pid) { printf("niet gevonden\n"); return 1; }
  HANDLE hp = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
  T t[256]; int nt = 0; THREADENTRY32 te = { sizeof te }; s = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  int ms = atoi(argv[2]), cap = ms + 100;
  for (BOOL ok = Thread32First(s, &te); ok && nt < 256; ok = Thread32Next(s, &te)) if (te.th32OwnerProcessID == pid) {
    HANDLE h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, te.th32ThreadID);
    if (h) { t[nt].tid = te.th32ThreadID; t[nt].h = h; t[nt].n = 0; t[nt].pc = calloc(cap, sizeof(DWORD64)); nt++; } }
  CloseHandle(s);
  timeBeginPeriod(1);
  DWORD end = GetTickCount() + ms;
  while (GetTickCount() < end) {
    for (int i = 0; i < nt; i++) {
      if (SuspendThread(t[i].h) == (DWORD)-1) continue;
      CONTEXT c = { 0 }; c.ContextFlags = CONTEXT_CONTROL;
      if (GetThreadContext(t[i].h, &c) && t[i].n < cap) t[i].pc[t[i].n++] = c.Pc;
      ResumeThread(t[i].h);
    }
    Sleep(1);
  }
  SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
  SymInitialize(hp, NULL, TRUE);
  for (int i = 0; i < nt; i++) {
    E *e = calloc(t[i].n + 1, sizeof(E)); int ne = 0, wait = 0;
    for (int k = 0; k < t[i].n; k++) {
      char buf[sizeof(SYMBOL_INFO) + 128]; SYMBOL_INFO *si = (SYMBOL_INFO *)buf; si->SizeOfStruct = sizeof(SYMBOL_INFO); si->MaxNameLen = 127;
      IMAGEHLP_MODULE64 mi = { sizeof mi }; char name[160]; DWORD64 disp = 0;
      const char *mod = SymGetModuleInfo64(hp, t[i].pc[k], &mi) ? mi.ModuleName : "?";
      if (SymFromAddr(hp, t[i].pc[k], &disp, si)) _snprintf_s(name, sizeof name, _TRUNCATE, "%s!%s", mod, si->Name);
      else _snprintf_s(name, sizeof name, _TRUNCATE, "%s+0x%llx", mod, mi.BaseOfImage ? t[i].pc[k] - mi.BaseOfImage : t[i].pc[k]);
      if (!getenv("ALLES") && (strstr(name, "NtWaitFor") || strstr(name, "NtRemoveIoCompletion") || strstr(name, "NtDelayExecution") || strstr(name, "ZwWaitFor") || strstr(name, "NtUserMsgWait") || strstr(name, "NtAlpcSend") || strstr(name, "NtWaitForAlertByThreadId") || strstr(name, "NtUserGetMessage") || strstr(name, "NtUserMsgWaitForMultipleObjects") || strstr(name, "NtDxgkWaitForVerticalBlankEvent") || strstr(name, "NtGdiDdDDIWaitForVerticalBlankEvent"))) { wait++; continue; }
      int j; for (j = 0; j < ne; j++) if (!strcmp(e[j].name, name)) { e[j].n++; break; }
      if (j == ne) { strcpy_s(e[ne].name, sizeof e[ne].name, name); e[ne].n = 1; ne++; }
    }
    int busy = t[i].n - wait;
    if (busy >= 20 && (!getenv("THREAD") || t[i].tid == (DWORD)atoi(getenv("THREAD")))) {
      qsort(e, ne, sizeof(E), cmpe);
      printf("thread %u: %d samples, %d busy (%.0f%%)\n", t[i].tid, t[i].n, busy, 100.0 * busy / (t[i].n ? t[i].n : 1));
      for (int j = 0; j < ne && j < 14; j++) printf("   %5d  %s\n", e[j].n, e[j].name);
    }
    free(e);
  }
  return 0;
}
