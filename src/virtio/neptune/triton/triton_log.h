/*
 * Copyright 2026 Turing Software LLC
 * SPDX-License-Identifier: MIT
 *
 * Logging and DDI-entry macros.
 *
 *   TR_LOG(fmt, ...)  - OutputDebugStringA debug print.
 *   TR_LOG_HOT        - per-call trace, compiled out unless TRITON_HOT_LOG.
 *   TR_LOG_HR(hr, ..) - logs on failure; on success only as TR_LOG_HOT.
 *   TR_STUB(name)     - logs "Triton: STUB <name>" once per thunk.
 */

#ifndef TRITON_LOG_H_INCLUDED
#define TRITON_LOG_H_INCLUDED

#include <windows.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef NPT_LOG_FILE
/* npt_log_win32.c: C:\Users\Public\neptune.log + OutputDebugString */
void npt_log_write(const char *line);
#endif

static inline void triton_log_raw(const char *line)
{
#ifdef NPT_LOG_FILE
    npt_log_write(line);
#else
    OutputDebugStringA(line);
#endif
}

#define TR_LOG(fmt, ...) do {                                         \
        char _trbuf[512];                                             \
        _snprintf_s(_trbuf, sizeof(_trbuf), _TRUNCATE,                \
                    "Triton: " fmt "\n", ##__VA_ARGS__);              \
        triton_log_raw(_trbuf);                                       \
    } while (0)


/* Per-DDI-call trace: compiled OUT by default.  OutputDebugStringA is a
 * RaiseException + global DBWIN handshake per call; at draw/list rates it
 * dominates real work: a loading thread can spend minutes parked
 * inside ODS.  Define TRITON_HOT_LOG to re-enable when tracing a
 * specific run. */
#ifdef TRITON_HOT_LOG
#define TR_LOG_HOT TR_LOG
#else
#define TR_LOG_HOT(fmt, ...) do { } while (0)
#endif

/* Object-create trace: a failure always logs, a success only under
 * TRITON_HOT_LOG.  A title creates thousands of resources, shaders and
 * pipelines while loading, and one ODS line per create stalls every
 * loading thread behind a DBWIN reader for minutes. */
#define TR_LOG_HR(hr, fmt, ...) do {                                  \
        if (FAILED(hr))                                               \
            TR_LOG(fmt, ##__VA_ARGS__);                               \
        else                                                          \
            TR_LOG_HOT(fmt, ##__VA_ARGS__);                           \
    } while (0)

/* Trace for single-channel / alpha / block-compressed formats (A8, R8*, R8G8,
 * BC*): rate-limited to the first 200 lines per process.  Used to chase the
 * "text renders as white boxes" problem (A8 glyph masks). */
extern volatile LONG g_tritonFmtLogCount;
static inline BOOL triton_fmt_traced(UINT f)
{
    return f == 65 /*A8_UNORM*/ || (f >= 60 && f <= 64) /*R8_*/ ||
           (f >= 48 && f <= 52) /*R8G8_**/ || (f >= 70 && f <= 84) /*BC1..BC5*/ ||
           (f >= 94 && f <= 99) /*BC6H,BC7*/;
}
#define TR_FMT_LOG(fmt, ...) do {                                     \
        if (InterlockedIncrement(&g_tritonFmtLogCount) <= 200)        \
            TR_LOG("FMT " fmt, ##__VA_ARGS__);                        \
    } while (0)

#define TR_STUB(name) do {                                            \
        static LONG _seen = 0;                                        \
        if (InterlockedExchange(&_seen, 1) == 0)                      \
            TR_LOG("STUB %s", (name));                                \
    } while (0)

#ifdef __cplusplus
}
#endif

#endif /* TRITON_LOG_H_INCLUDED */
