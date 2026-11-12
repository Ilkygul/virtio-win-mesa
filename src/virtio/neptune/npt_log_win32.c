/*
 * SPDX-License-Identifier: MIT
 *
 * File logging for the native Windows (non-Wine) Neptune UMD.
 *
 * The UMD is loaded into arbitrary processes (dwm, games, test tools) that
 * have no usable stderr and often no debugger, so every npt_log / TR_LOG
 * line is appended to C:\Users\Public\neptune.log (world-writable on
 * Windows) and mirrored to OutputDebugString.  Each line carries the tick
 * count, process id and the process image name.  The file is capped
 * (NPT_LOG_MAX_BYTES) so a runaway loop cannot fill the disk.
 */

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "npt_common.h"

#define NPT_LOG_PATH      L"C:\\Users\\Public\\neptune.log"
#define NPT_LOG_MAX_BYTES (32ll << 20)

static CRITICAL_SECTION g_log_cs;
static volatile LONG g_log_cs_state; /* 0 no, 1 initializing, 2 ready */
static char g_log_prefix[80];

static void
npt_log_lock(void)
{
   if (g_log_cs_state != 2) {
      if (InterlockedCompareExchange(&g_log_cs_state, 1, 0) == 0) {
         InitializeCriticalSection(&g_log_cs);
         char path[MAX_PATH] = "?";
         GetModuleFileNameA(NULL, path, sizeof(path));
         const char *base = strrchr(path, '\\');
         snprintf(g_log_prefix, sizeof(g_log_prefix), "[pid %lu %s] ",
                  GetCurrentProcessId(), base ? base + 1 : path);
         MemoryBarrier();
         g_log_cs_state = 2;
      } else {
         while (g_log_cs_state != 2)
            SwitchToThread();
      }
   }
   EnterCriticalSection(&g_log_cs);
}

void
npt_log_write(const char *line)
{
   OutputDebugStringA(line);

   npt_log_lock();
   HANDLE h = CreateFileW(NPT_LOG_PATH, FILE_APPEND_DATA,
                          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                          NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
   if (h != INVALID_HANDLE_VALUE) {
      LARGE_INTEGER size;
      if (GetFileSizeEx(h, &size) && size.QuadPart < NPT_LOG_MAX_BYTES) {
         char buf[1200];
         int n = snprintf(buf, sizeof(buf), "%10lu %s%s", GetTickCount(),
                          g_log_prefix, line);
         if (n > 0) {
            if ((size_t)n >= sizeof(buf))
               n = (int)sizeof(buf) - 1;
            if (buf[n - 1] != '\n' && n < (int)sizeof(buf) - 1)
               buf[n++] = '\n';
            DWORD written;
            WriteFile(h, buf, (DWORD)n, &written, NULL);
         }
      }
      CloseHandle(h);
   }
   LeaveCriticalSection(&g_log_cs);
}

void
npt_log_impl(const char *fmt, ...)
{
   char buf[1024];
   va_list ap;
   va_start(ap, fmt);
   int len = vsnprintf(buf, sizeof(buf), fmt, ap);
   va_end(ap);
   if (len <= 0)
      return;
   if ((size_t)len >= sizeof(buf))
      len = (int)sizeof(buf) - 1;
   buf[len] = '\0';
   npt_log_write(buf);
}
