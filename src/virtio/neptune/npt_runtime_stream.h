/* Runtime-owned D3D11 transport. HANDLEs are runtime callback handles,
 * never D3DKMT_HANDLEs. The owner outlives all rings/reapers and renderer. */
#ifndef NPT_RUNTIME_STREAM_H
#define NPT_RUNTIME_STREAM_H
#include <windows.h>
/* d3dumddi.h relies on the official D3D9 prerequisite types.  The NPT
 * transport headers may already supply this one shared POD type; honor
 * the SDK's documented guard instead of defining a second typedef. */
#if defined(NPT_PROTOCOL_DIRECTX_H) && !defined(D3DCOLORVALUE_DEFINED)
#define D3DCOLORVALUE_DEFINED
#endif
#include <d3d9types.h>
#include <d3dumddi.h>
struct npt_renderer;
struct npt_runtime_stream {
   HANDLE adapter;
   HANDLE device;
   HANDLE context;
   CRITICAL_SECTION *context_lock;
   D3DDDI_DEVICECALLBACKS callbacks;
   PFND3DDDI_QUERYADAPTERINFOCB query_adapter_info;
   CRITICAL_SECTION *write_lock;
   void *write_owner;
   HRESULT (*collect_writes)(void *,D3DKMT_HANDLE *,UINT,UINT *);
   void (*submitted_writes)(void *);
   /* Only explicit synchronous DDI reply/getter failure, never worker SetLost. */
   void (*report_reply_error)(void *);
};
void npt_runtime_owner_join_release(void *owner);
void npt_runtime_owner_publish(void *owner);
int npt_runtime_owner_publish_checked(void *owner);
void npt_runtime_owner_maintenance(void *owner);
unsigned npt_runtime_owner_context_id(void *owner);
int npt_runtime_owner_publisher_v1(void *owner);
struct npt_renderer *npt_renderer_create_runtime_stream(
   const struct npt_runtime_stream *stream);
#endif
