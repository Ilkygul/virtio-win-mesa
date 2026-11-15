/* C13: defer only known asynchronous direct D3D11 writes, on the GLOBAL
 * ordered ring, not TLS stages. Unknown/control/reply/Wait commands are barriers.
 * No time/size pacing threshold: normal barriers or actual ring pressure publish.
 */
#ifndef NPT_PUBLISHER_BATCH_H
#define NPT_PUBLISHER_BATCH_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "neptune-protocol/npt_protocol_defs.h"
#include "neptune-protocol/npt_protocol_transport.h"
/* The generated Context1 constant-buffer range setters share this exact
 * wire shape: UINT slot/count, then three uint64-counted arrays (handles,
 * optional first-constant, optional constant-count). They only bind state;
 * retaining global ring order through the next required boundary is enough.
 * No other Context1 method, reply, malformed shape or unknown data is batched.
 */
static inline bool
npt_publisher_batch_cb_ranges(const void *data, size_t size)
{
   const size_t hsize = sizeof(struct npt_command_header);
   if (size < hsize + 2 * sizeof(uint32_t))
      return false;
   const uint8_t *bytes = data;
   uint32_t start, count;
   memcpy(&start, bytes + hsize, sizeof(start));
   memcpy(&count, bytes + hsize + sizeof(start), sizeof(count));
   /* D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT is 14. */
   if (start > 14u || count > 14u - start)
      return false;
   size_t offset = hsize + 2 * sizeof(uint32_t);
   for (unsigned array = 0; array < 3; ++array) {
      if (size - offset < sizeof(uint64_t))
         return false;
      uint64_t elements;
      memcpy(&elements, bytes + offset, sizeof(elements));
      offset += sizeof(elements);
      /* The actual encoder distinguishes a present zero-length optional
       * UINT pointer with UINT64_MAX. The handle array does not use it. */
      if (array && !count && elements == UINT64_MAX)
         elements = 0;
      else if (elements && elements != count)
         return false;
      const size_t width = array ? sizeof(uint32_t) : sizeof(uint64_t);
      if (elements > (size - offset) / width)
         return false;
      offset += (size_t)elements * width;
   }
   return offset == size;
}
static inline bool
npt_publisher_batch_method(const void *data, size_t size, size_t reply_size,
                           uint32_t direct_size)
{
   if (!data || reply_size || size < sizeof(struct npt_command_header) || size > direct_size)
      return false;
   struct npt_command_header h;
   memcpy(&h, data, sizeof(h));
   if (h.cmd_size != size || h.cmd_flags || h.reserved || !h.object_id ||
       (h.cmd_type >> 24) != 255)
      return false;
   const uint32_t iface = (h.cmd_type >> 8) & 0xffffu;
   if (iface == NPT_IFACE_ID_ID3D11DeviceContext1) {
      switch (h.cmd_type & 0xffu) {
      case NPT_METHOD_ID3D11DeviceContext1_VSSetConstantBuffers1:
      case NPT_METHOD_ID3D11DeviceContext1_HSSetConstantBuffers1:
      case NPT_METHOD_ID3D11DeviceContext1_DSSetConstantBuffers1:
      case NPT_METHOD_ID3D11DeviceContext1_GSSetConstantBuffers1:
      case NPT_METHOD_ID3D11DeviceContext1_PSSetConstantBuffers1:
      case NPT_METHOD_ID3D11DeviceContext1_CSSetConstantBuffers1:
         return npt_publisher_batch_cb_ranges(data, size);
      default:
         return false;
      }
   }
   if (iface != NPT_IFACE_ID_ID3D11DeviceContext)
      return false;
   /* Fixed scalar draw shapes must be exact, not a partial command. Variable
    * array setters use the actual encoder's cmd_size; the host still validates
    * the full typed payload exactly as before. */
   const uint32_t method = h.cmd_type & 0xffu;
   if (method == NPT_METHOD_ID3D11DeviceContext_Draw && size != sizeof(h) + 8)
      return false;
   if (method == NPT_METHOD_ID3D11DeviceContext_DrawIndexed && size != sizeof(h) + 12)
      return false;
   switch (method) {
   case NPT_METHOD_ID3D11DeviceContext_VSSetConstantBuffers:
   case NPT_METHOD_ID3D11DeviceContext_PSSetShaderResources:
   case NPT_METHOD_ID3D11DeviceContext_PSSetShader:
   case NPT_METHOD_ID3D11DeviceContext_PSSetSamplers:
   case NPT_METHOD_ID3D11DeviceContext_VSSetShader:
   case NPT_METHOD_ID3D11DeviceContext_DrawIndexed:
   case NPT_METHOD_ID3D11DeviceContext_Draw:
   case NPT_METHOD_ID3D11DeviceContext_PSSetConstantBuffers:
   case NPT_METHOD_ID3D11DeviceContext_IASetInputLayout:
   case NPT_METHOD_ID3D11DeviceContext_IASetVertexBuffers:
   case NPT_METHOD_ID3D11DeviceContext_IASetIndexBuffer:
   case NPT_METHOD_ID3D11DeviceContext_DrawIndexedInstanced:
   case NPT_METHOD_ID3D11DeviceContext_DrawInstanced:
   case NPT_METHOD_ID3D11DeviceContext_GSSetConstantBuffers:
   case NPT_METHOD_ID3D11DeviceContext_GSSetShader:
   case NPT_METHOD_ID3D11DeviceContext_IASetPrimitiveTopology:
   case NPT_METHOD_ID3D11DeviceContext_VSSetShaderResources:
   case NPT_METHOD_ID3D11DeviceContext_VSSetSamplers:
   case NPT_METHOD_ID3D11DeviceContext_GSSetShaderResources:
   case NPT_METHOD_ID3D11DeviceContext_GSSetSamplers:
   case NPT_METHOD_ID3D11DeviceContext_OMSetRenderTargets:
   case NPT_METHOD_ID3D11DeviceContext_OMSetRenderTargetsAndUnorderedAccessViews:
   case NPT_METHOD_ID3D11DeviceContext_OMSetBlendState:
   case NPT_METHOD_ID3D11DeviceContext_OMSetDepthStencilState:
   case NPT_METHOD_ID3D11DeviceContext_SOSetTargets:
   case NPT_METHOD_ID3D11DeviceContext_DrawAuto:
   case NPT_METHOD_ID3D11DeviceContext_DrawIndexedInstancedIndirect:
   case NPT_METHOD_ID3D11DeviceContext_DrawInstancedIndirect:
   case NPT_METHOD_ID3D11DeviceContext_Dispatch:
   case NPT_METHOD_ID3D11DeviceContext_DispatchIndirect:
   case NPT_METHOD_ID3D11DeviceContext_RSSetState:
   case NPT_METHOD_ID3D11DeviceContext_RSSetViewports:
   case NPT_METHOD_ID3D11DeviceContext_RSSetScissorRects:
   case NPT_METHOD_ID3D11DeviceContext_CopySubresourceRegion:
   case NPT_METHOD_ID3D11DeviceContext_CopyResource:
   case NPT_METHOD_ID3D11DeviceContext_CopyStructureCount:
   case NPT_METHOD_ID3D11DeviceContext_ClearRenderTargetView:
   case NPT_METHOD_ID3D11DeviceContext_ClearUnorderedAccessViewUint:
   case NPT_METHOD_ID3D11DeviceContext_ClearUnorderedAccessViewFloat:
   case NPT_METHOD_ID3D11DeviceContext_ClearDepthStencilView:
   case NPT_METHOD_ID3D11DeviceContext_GenerateMips:
   case NPT_METHOD_ID3D11DeviceContext_SetResourceMinLOD:
   case NPT_METHOD_ID3D11DeviceContext_ResolveSubresource:
   case NPT_METHOD_ID3D11DeviceContext_HSSetShaderResources:
   case NPT_METHOD_ID3D11DeviceContext_HSSetShader:
   case NPT_METHOD_ID3D11DeviceContext_HSSetSamplers:
   case NPT_METHOD_ID3D11DeviceContext_HSSetConstantBuffers:
   case NPT_METHOD_ID3D11DeviceContext_DSSetShaderResources:
   case NPT_METHOD_ID3D11DeviceContext_DSSetShader:
   case NPT_METHOD_ID3D11DeviceContext_DSSetSamplers:
   case NPT_METHOD_ID3D11DeviceContext_DSSetConstantBuffers:
   case NPT_METHOD_ID3D11DeviceContext_CSSetShaderResources:
   case NPT_METHOD_ID3D11DeviceContext_CSSetUnorderedAccessViews:
   case NPT_METHOD_ID3D11DeviceContext_CSSetShader:
   case NPT_METHOD_ID3D11DeviceContext_CSSetSamplers:
   case NPT_METHOD_ID3D11DeviceContext_CSSetConstantBuffers:
      return true;
   default:
      return false; /* notably Map/Unmap/GetData/Begin/End/Flush/ExecuteList */
   }
}
static inline bool
npt_publisher_batch_update(const void *header, uint32_t header_size,
                           uint32_t payload_size, uint32_t padded_size,
                           uint32_t direct_size)
{
   if (!header || header_size != sizeof(struct npt_cmd_resource_update) ||
       !payload_size || payload_size > padded_size || padded_size > direct_size ||
       header_size > direct_size - padded_size)
      return false;
   struct npt_cmd_resource_update u;
   memcpy(&u, header, sizeof(u));
   return u.header.cmd_type == NPT_TRANSPORT_CMD_TYPE(NPT_TRANSPORT_SUBGROUP_RESOURCE,
                                                     NPT_TRANSPORT_RESOURCE_UPDATE) &&
      !u.header.cmd_flags && !u.header.reserved && u.header.object_id &&
      u.header.cmd_size == header_size + padded_size && u.byte_size &&
      u.byte_size <= UINT32_MAX - 7u && padded_size == ((u.byte_size + 7u) & ~7u) &&
      payload_size == u.byte_size && u.has_box <= 1 && !u.pad;
}
#endif
