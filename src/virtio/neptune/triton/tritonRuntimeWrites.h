/* Per-operation potential writes. This is Windows submission metadata,
 * NOT an external image ownership grant. Included only after triton.h. */
#ifndef TRITON_RUNTIME_WRITES_H
#define TRITON_RUNTIME_WRITES_H
#include "npt_runtime_stream.h"
#define TRITON_RUNTIME_RESOURCE_DISPLAYABLE 0x4454504eu /* NPTD */
#define TRITON_RUNTIME_RESOURCE_ORDINARY    0x4e54504eu /* NPTN */
/* Only tuple metadata is locked across mutation. No host call/wait is
 * made until TupleDone releases it; view replay then restores fresh refs. */
static inline void trRuntimeSharedBackingBegin(PTRITON_DEVICE p)
{
    if (!p->RuntimeStreamActive) return;
    EnterCriticalSection(&p->RuntimeWriteLock);
    if (InterlockedExchange(&p->RuntimeSharedChanging,1)) {
        InterlockedExchange(&p->RuntimeWriteFailed,1);
        InterlockedOr(&p->SharedDirty,TRITON_SHARED_STRICT);
    }
    for (UINT i=0;i<8;++i)
        if (p->RuntimeRtv[i].sharedDirty) p->RuntimeRtv[i].sharedDirty |= TRITON_SHARED_STRICT;
    if (p->RuntimeDsv.sharedDirty) p->RuntimeDsv.sharedDirty |= TRITON_SHARED_STRICT;
    for (UINT i=0;i<64;++i) {
        if (p->RuntimeOmUav[i].sharedDirty) p->RuntimeOmUav[i].sharedDirty |= TRITON_SHARED_STRICT;
        if (p->RuntimeCsUav[i].sharedDirty) p->RuntimeCsUav[i].sharedDirty |= TRITON_SHARED_STRICT;
    }
    p->OmSharedNeedsWriteSync=TRUE;
}
static inline void trRuntimeSharedBackingTupleDone(PTRITON_DEVICE p)
{
    if (p->RuntimeStreamActive) LeaveCriticalSection(&p->RuntimeWriteLock);
}
static inline void trRuntimeSharedBackingEnd(PTRITON_DEVICE p)
{
    if (!p->RuntimeStreamActive) return;
    EnterCriticalSection(&p->RuntimeWriteLock);
    InterlockedExchange(&p->RuntimeSharedChanging,0);
    LeaveCriticalSection(&p->RuntimeWriteLock);
}
static inline TRITON_RUNTIME_WRITE_REF trRuntimeWriteRef(PTRITON_DEVICE p, PTRITON_RESOURCE r)
{
    TRITON_RUNTIME_WRITE_REF v = {0};
    if (p->RuntimeStreamActive) EnterCriticalSection(&p->RuntimeWriteLock);
    if (r) {
        v.classification = r->RuntimeWriteClass;
        if (r->IsShared || r->IsPresentable || r->pPresentCompanion)
            v.sharedDirty = tritonLocalPresentBacking(r) ?
                TRITON_SHARED_QUALIFIED : TRITON_SHARED_STRICT;
        v.allocation = r->RuntimeOpenedAllocation ? r->RuntimeOpenedAllocation : r->hKMAllocation;
        if (v.classification == 1 && !v.allocation) v.classification = 2;
    }
    if (v.sharedDirty && p->RuntimeSharedChanging) v.sharedDirty |= TRITON_SHARED_STRICT;
    if (p->RuntimeStreamActive) LeaveCriticalSection(&p->RuntimeWriteLock);
    return v;
}
static inline BOOL trRuntimeUniqueAdd(D3DKMT_HANDLE *a, UINT *n, D3DKMT_HANDLE h)
{
    for (UINT i=0; i<*n; ++i) if (a[i]==h) return TRUE;
    if (*n == D3DDDI_MAX_WRITTEN_PRIMARIES) return FALSE;
    a[(*n)++] = h;
    return TRUE;
}
static inline BOOL trRuntimeWriteBegin(PTRITON_DEVICE p, const TRITON_RUNTIME_WRITE_REF *refs, UINT count)
{
    if (!p->RuntimeStreamActive) return TRUE;
    EnterCriticalSection(&p->RuntimeWriteLock);
    /* A complete operation owns the lock across encoding/autopublish. */
    if (InterlockedCompareExchange(&p->RuntimeWriteFailed,0,0) || p->RuntimeActiveWriteCount) goto unsupported;
    D3DKMT_HANDLE combined[D3DDDI_MAX_WRITTEN_PRIMARIES];
    UINT n = p->RuntimePendingWriteCount;
    LONG dirty = 0;
    memcpy(combined, p->RuntimePendingWrites, n*sizeof(*combined));
    for (UINT i=0; i<count; ++i) {
        if (refs[i].classification == 2) goto unsupported;
        dirty |= refs[i].sharedDirty;
        if (refs[i].classification == 1) {
            if (!refs[i].allocation || !trRuntimeUniqueAdd(combined,&n,refs[i].allocation) ||
                !trRuntimeUniqueAdd(p->RuntimeActiveWrites,&p->RuntimeActiveWriteCount,refs[i].allocation))
                goto unsupported;
        }
    }
    if (dirty) {
        if (dirty != TRITON_SHARED_QUALIFIED || p->RuntimeSharedChanging ||
            !npt_runtime_owner_publisher_v1(p->RuntimeTransportOwner) ||
            tritonSwitch("triton-presentwritesync")) dirty |= TRITON_SHARED_STRICT;
        /* Reassert under the operation lock BEFORE encoding. A premark may
         * have been consumed by an earlier boundary before this write began. */
        InterlockedOr(&p->SharedDirty,dirty);
    }
    return TRUE;
unsupported:
    InterlockedExchange(&p->RuntimeWriteFailed,1);
    p->RuntimeActiveWriteCount=0;
    LeaveCriticalSection(&p->RuntimeWriteLock);
    TR_LOG("RUNTIME_WRITE unsupported/unknown allocation or primary set exceeds SDK capacity; no operation executed");
    tritonSetError(p,D3DDDIERR_DEVICEREMOVED);
    return FALSE;
}
static inline void trRuntimeWriteEnd(PTRITON_DEVICE p)
{
    if (!p->RuntimeStreamActive) return;
    for (UINT i=0;i<p->RuntimeActiveWriteCount;++i)
        if (!trRuntimeUniqueAdd(p->RuntimePendingWrites,&p->RuntimePendingWriteCount,p->RuntimeActiveWrites[i])) {
            /* Begin checked the union under this same lock. */
            TR_LOG("RUNTIME_WRITE invariant failed; retaining callback storage");
            for (;;) Sleep(1000);
        }
    p->RuntimeActiveWriteCount=0;
    LeaveCriticalSection(&p->RuntimeWriteLock);
}
static inline HRESULT trRuntimeCollectWrites(void *cookie,D3DKMT_HANDLE *out,UINT cap,UINT *count)
{
    PTRITON_DEVICE p=cookie;
    UINT n=0;
    *count=0;
    if(InterlockedCompareExchange(&p->RuntimeWriteFailed,0,0)) {
        TR_LOG("RUNTIME_COLLECT_FAIL reason=latched tid=%lu cap=%u pending=%u active=%u",(unsigned long)GetCurrentThreadId(),cap,p->RuntimePendingWriteCount,p->RuntimeActiveWriteCount);
        return D3DDDIERR_DEVICEREMOVED;
    }
    if (cap<D3DDDI_MAX_WRITTEN_PRIMARIES) {
        TR_LOG("RUNTIME_COLLECT_FAIL reason=capacity tid=%lu cap=%u required=%u pending=%u active=%u",(unsigned long)GetCurrentThreadId(),cap,(unsigned)D3DDDI_MAX_WRITTEN_PRIMARIES,p->RuntimePendingWriteCount,p->RuntimeActiveWriteCount);
        return E_INVALIDARG;
    }
    for (UINT i=0;i<p->RuntimePendingWriteCount;++i)
        if(!trRuntimeUniqueAdd(out,&n,p->RuntimePendingWrites[i])) {
            TR_LOG("RUNTIME_COLLECT_FAIL reason=pending-union tid=%lu cap=%u pending=%u active=%u index=%u accumulated=%u",(unsigned long)GetCurrentThreadId(),cap,p->RuntimePendingWriteCount,p->RuntimeActiveWriteCount,i,n);
            return E_FAIL;
        }
    for (UINT i=0;i<p->RuntimeActiveWriteCount;++i)
        if(!trRuntimeUniqueAdd(out,&n,p->RuntimeActiveWrites[i])) {
            TR_LOG("RUNTIME_COLLECT_FAIL reason=active-union tid=%lu cap=%u pending=%u active=%u index=%u accumulated=%u",(unsigned long)GetCurrentThreadId(),cap,p->RuntimePendingWriteCount,p->RuntimeActiveWriteCount,i,n);
            return E_FAIL;
        }
    *count=n; return S_OK;
}
static inline void trRuntimeSubmittedWrites(void *cookie)
{
    PTRITON_DEVICE p=cookie;
    p->RuntimePendingWriteCount=0; /* active set survives every automatic notify */
}
static inline BOOL trRuntimeWriteResourceBegin(PTRITON_DEVICE p,PTRITON_RESOURCE r)
{
    if (p->RuntimeStreamActive) EnterCriticalSection(&p->RuntimeWriteLock);
    TRITON_RUNTIME_WRITE_REF ref=trRuntimeWriteRef(p,r);
    BOOL ok=trRuntimeWriteBegin(p,&ref,1);
    if (p->RuntimeStreamActive) LeaveCriticalSection(&p->RuntimeWriteLock);
    return ok;
}
static inline BOOL trRuntimeDrawWriteBegin(PTRITON_DEVICE p,BOOL compute)
{
    if (!p->RuntimeStreamActive) return TRUE;
    EnterCriticalSection(&p->RuntimeWriteLock);
    TRITON_RUNTIME_WRITE_REF refs[73]; UINT n=0;
    if (compute) { for(UINT i=0;i<64;++i) refs[n++]=p->RuntimeCsUav[i]; }
    else {
        for(UINT i=0;i<8;++i) refs[n++]=p->RuntimeRtv[i];
        refs[n++]=p->RuntimeDsv;
        for(UINT i=0;i<64;++i) refs[n++]=p->RuntimeOmUav[i];
    }
    /* A shared OM with no positive cached shared-write snapshot is unknown,
     * never a positive qualification inferred from current OM flags alone. */
    if (!compute && p->OmShared) {
        BOOL known=FALSE;
        for (UINT i=0;i<n;++i) if (refs[i].sharedDirty) known=TRUE;
        if (!known) InterlockedOr(&p->SharedDirty,TRITON_SHARED_STRICT);
    }
    BOOL ok=trRuntimeWriteBegin(p,refs,n);
    LeaveCriticalSection(&p->RuntimeWriteLock);
    return ok;
}
static inline void trRuntimePublishBeforeReuse(PTRITON_DEVICE p)
{
    if (!p->RuntimeStreamActive) return;
    EnterCriticalSection(&p->RuntimeWriteLock);
    /* Flush is a real encoded boundary, not a GPU/CPU completion shortcut. */
    if (p->pCtx1) ID3D11DeviceContext1_Flush(p->pCtx1);
    npt_runtime_owner_publish(p->RuntimeTransportOwner);
    if (p->RuntimePendingWriteCount || p->RuntimeActiveWriteCount) {
        TR_LOG("RUNTIME_WRITE unpublished snapshot at backing reuse; retaining owner");
        for (;;) Sleep(1000);
    }
    LeaveCriticalSection(&p->RuntimeWriteLock);
}
#endif
