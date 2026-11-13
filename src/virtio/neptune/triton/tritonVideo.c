/*
 * Copyright 2026 Turing Software LLC
 * SPDX-License-Identifier: MIT
 *
 * Triton video DDI (D3D11.1 / WDDM 2.0 / 2.1 video device function tables).
 *
 * Every call is forwarded to the host's ID3D11VideoDevice / ID3D11VideoContext
 * through Neptune (DXVK on the host decodes with Android MediaCodec).
 *
 * Decoder buffers: the runtime creates them as resources with a
 * DecoderBufferType and maps them for the app.  They never reach the host as
 * resources: tritonCreateResource gives them guest memory (tritonVideo*
 * helpers below), and SubmitBuffers packs the used ranges into one blob sent
 * through DecoderExtension(TRITON_NPT_DXVA_SUBMIT) -- the host's own
 * GetDecoderBuffer pointer means nothing in the guest.  Blob layout is ABI
 * with dxvk src/d3d11/d3d11_video_mc.h (NptDxvaSubmitHeader/Entry).
 */

#include "triton.h"
#include "triton_log.h"
#include "tritonVideo.h"

#define TRITON_NPT_DXVA_SUBMIT  0x4e505644u /* 'NPVD' */
#define TRITON_NPT_DXVA_MAGIC   0x31565044u /* 'DPV1' */

typedef struct TRITON_VDECODER {
    ID3D11VideoDecoder            *pDecoder;
    D3D11_VIDEO_DECODER_DESC       Desc;
    BYTE                          *pBlob;
    UINT                           BlobCap;
} TRITON_VDECODER, *PTRITON_VDECODER;

typedef struct TRITON_VDOV {
    ID3D11VideoDecoderOutputView  *pView;
} TRITON_VDOV, *PTRITON_VDOV;

typedef struct TRITON_VPENUM {
    ID3D11VideoProcessorEnumerator *pEnum;
} TRITON_VPENUM, *PTRITON_VPENUM;

typedef struct TRITON_VP {
    ID3D11VideoProcessor          *pVP;
} TRITON_VP, *PTRITON_VP;

typedef struct TRITON_VPIV {
    ID3D11VideoProcessorInputView *pView;
} TRITON_VPIV, *PTRITON_VPIV;

typedef struct TRITON_VPOV {
    ID3D11VideoProcessorOutputView *pView;
} TRITON_VPOV, *PTRITON_VPOV;

#define TR_DEV(h)   ((PTRITON_DEVICE)(h).pDrvPrivate)

static BOOL
trVideoEnsure(PTRITON_DEVICE pD)
{
    if (!pD)
        return FALSE;
    if (pD->pVidDev && pD->pVidCtx)
        return TRUE;
    if (pD->bVidFailed)
        return FALSE;
    HRESULT hr = ID3D11Device1_QueryInterface(pD->pDev1, &IID_ID3D11VideoDevice, (void **)&pD->pVidDev);
    if (SUCCEEDED(hr))
        hr = ID3D11DeviceContext1_QueryInterface(pD->pCtx1, &IID_ID3D11VideoContext, (void **)&pD->pVidCtx);
    if (FAILED(hr)) {
        TR_LOG("video: host has no ID3D11VideoDevice/Context (0x%08lx)", hr);
        if (pD->pVidDev) { ID3D11VideoDevice_Release(pD->pVidDev); pD->pVidDev = NULL; }
        pD->bVidFailed = TRUE;
        return FALSE;
    }
    TR_LOG("video: host video device ready");
    return TRUE;
}

void
tritonVideoDestroyDevice(PTRITON_DEVICE pD)
{
    if (pD->pVidCtx) { ID3D11VideoContext_Release(pD->pVidCtx); pD->pVidCtx = NULL; }
    if (pD->pVidDev) { ID3D11VideoDevice_Release(pD->pVidDev); pD->pVidDev = NULL; }
}

/* ------------------------------------------------------------------ */
/* Decoder buffers (guest memory)                                      */
/* ------------------------------------------------------------------ */

BOOL
tritonVideoCreateDecoderBuffer(PTRITON_RESOURCE r, UINT size, UINT type)
{
    r->pSysMem = calloc(1, size ? size : 1);
    r->SysMemSize = size;
    r->DecoderBufferType = type;
    return r->pSysMem != NULL;
}

/* ------------------------------------------------------------------ */
/* Decoder                                                             */
/* ------------------------------------------------------------------ */

static void APIENTRY
trGetVideoDecoderProfileCount(D3D10DDI_HDEVICE hDevice, UINT *pCount)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    *pCount = trVideoEnsure(pD) ? ID3D11VideoDevice_GetVideoDecoderProfileCount(pD->pVidDev) : 0;
    TR_LOG("video: %u decoder profiles", *pCount);
}

static void APIENTRY
trGetVideoDecoderProfile(D3D10DDI_HDEVICE hDevice, UINT Index, GUID *pGuid)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    if (!trVideoEnsure(pD) || FAILED(ID3D11VideoDevice_GetVideoDecoderProfile(pD->pVidDev, Index, pGuid)))
        memset(pGuid, 0, sizeof(*pGuid));
}

static void APIENTRY
trCheckVideoDecoderFormat(D3D10DDI_HDEVICE hDevice, const GUID *pGuid, DXGI_FORMAT Format, BOOL *pSupported)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    *pSupported = FALSE;
    if (trVideoEnsure(pD))
        ID3D11VideoDevice_CheckVideoDecoderFormat(pD->pVidDev, pGuid, Format, pSupported);
}

static void APIENTRY
trGetVideoDecoderConfigCount(D3D10DDI_HDEVICE hDevice, const D3D11_1DDI_VIDEO_DECODER_DESC *pDesc, UINT *pCount)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    *pCount = 0;
    if (trVideoEnsure(pD))
        ID3D11VideoDevice_GetVideoDecoderConfigCount(pD->pVidDev, (const D3D11_VIDEO_DECODER_DESC *)pDesc, pCount);
}

static void APIENTRY
trGetVideoDecoderConfig(D3D10DDI_HDEVICE hDevice, const D3D11_1DDI_VIDEO_DECODER_DESC *pDesc, UINT Index,
                        D3D11_1DDI_VIDEO_DECODER_CONFIG *pConfig)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    if (!trVideoEnsure(pD) ||
        FAILED(ID3D11VideoDevice_GetVideoDecoderConfig(pD->pVidDev, (const D3D11_VIDEO_DECODER_DESC *)pDesc,
                                                       Index, (D3D11_VIDEO_DECODER_CONFIG *)pConfig)))
        memset(pConfig, 0, sizeof(*pConfig));
}

static const D3D11_1DDI_VIDEO_DECODER_BUFFER_TYPE trBufferTypes[] = {
    D3D11_1DDI_VIDEO_DECODER_BUFFER_PICTURE_PARAMETERS,
    D3D11_1DDI_VIDEO_DECODER_BUFFER_INVERSE_QUANTIZATION_MATRIX,
    D3D11_1DDI_VIDEO_DECODER_BUFFER_SLICE_CONTROL,
    D3D11_1DDI_VIDEO_DECODER_BUFFER_BITSTREAM,
};

static void APIENTRY
trGetVideoDecoderBufferTypeCount(D3D10DDI_HDEVICE hDevice, const D3D11_1DDI_VIDEO_DECODER_DESC *pDesc, UINT *pCount)
{
    (void)hDevice; (void)pDesc;
    *pCount = ARRAYSIZE(trBufferTypes);
}

static void APIENTRY
trGetVideoDecoderBufferInfo(D3D10DDI_HDEVICE hDevice, const D3D11_1DDI_VIDEO_DECODER_DESC *pDesc, UINT Index,
                            D3D11_1DDI_VIDEO_DECODER_BUFFER_INFO *pInfo)
{
    (void)hDevice;
    memset(pInfo, 0, sizeof(*pInfo));
    if (Index >= ARRAYSIZE(trBufferTypes))
        return;
    pInfo->Type = trBufferTypes[Index];
    switch (pInfo->Type) {
    case D3D11_1DDI_VIDEO_DECODER_BUFFER_BITSTREAM: {
        UINT px = pDesc ? pDesc->SampleWidth * pDesc->SampleHeight : 0;
        pInfo->Size = px > (2u << 20) ? px : (2u << 20);
        break;
    }
    case D3D11_1DDI_VIDEO_DECODER_BUFFER_SLICE_CONTROL:
        pInfo->Size = 256u << 10;
        break;
    default:
        pInfo->Size = 16u << 10;
        break;
    }
    pInfo->Usage = D3D10_DDI_USAGE_STAGING;
}

static SIZE_T APIENTRY
trCalcPrivateVideoDecoderSize(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEODECODER *pArgs)
{
    (void)hDevice; (void)pArgs;
    return sizeof(TRITON_VDECODER);
}

static HRESULT APIENTRY
trCreateVideoDecoder(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEODECODER *pArgs,
                     D3D11_1DDI_HDECODE hDecode, D3D11_1DDI_HRTDECODE hRTDecode)
{
    (void)hRTDecode;
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VDECODER d = (PTRITON_VDECODER)hDecode.pDrvPrivate;
    memset(d, 0, sizeof(*d));
    if (!trVideoEnsure(pD))
        return E_FAIL;
    memcpy(&d->Desc, &pArgs->Desc, sizeof(d->Desc));
    HRESULT hr = ID3D11VideoDevice_CreateVideoDecoder(pD->pVidDev, (const D3D11_VIDEO_DECODER_DESC *)&pArgs->Desc,
                                                     (const D3D11_VIDEO_DECODER_CONFIG *)&pArgs->Config, &d->pDecoder);
    TR_LOG("video: CreateVideoDecoder %08lx %ux%u fmt=%u raw=%u -> 0x%08lx",
           pArgs->Desc.Guid.Data1, pArgs->Desc.SampleWidth, pArgs->Desc.SampleHeight,
           (UINT)pArgs->Desc.OutputFormat, pArgs->Config.ConfigBitstreamRaw, hr);
    return hr;
}

static void APIENTRY
trDestroyVideoDecoder(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HDECODE hDecode)
{
    (void)hDevice;
    PTRITON_VDECODER d = (PTRITON_VDECODER)hDecode.pDrvPrivate;
    if (d->pDecoder)
        ID3D11VideoDecoder_Release(d->pDecoder);
    free(d->pBlob);
    memset(d, 0, sizeof(*d));
}

static HRESULT APIENTRY
trVideoDecoderExtension(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HDECODE hDecode,
                        const D3D11_1DDIARG_VIDEODECODEREXTENSION *pArgs)
{
    (void)hDevice; (void)hDecode; (void)pArgs;
    TR_STUB("VideoDecoderExtension");
    return E_NOTIMPL;
}

static HRESULT APIENTRY
trVideoDecoderBeginFrame(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HDECODE hDecode,
                         const D3D11_1DDIARG_VIDEODECODERBEGINFRAME *pArgs)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VDECODER d = (PTRITON_VDECODER)hDecode.pDrvPrivate;
    PTRITON_VDOV v = (PTRITON_VDOV)pArgs->hOutputView.pDrvPrivate;
    if (!d->pDecoder || !v || !v->pView || !trVideoEnsure(pD))
        return E_INVALIDARG;
    return ID3D11VideoContext_DecoderBeginFrame(pD->pVidCtx, d->pDecoder, v->pView, 0, NULL);
}

static void APIENTRY
trVideoDecoderEndFrame(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HDECODE hDecode)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VDECODER d = (PTRITON_VDECODER)hDecode.pDrvPrivate;
    if (d->pDecoder && trVideoEnsure(pD)) {
        HRESULT hr = ID3D11VideoContext_DecoderEndFrame(pD->pVidCtx, d->pDecoder);
        if (FAILED(hr)) {
            static LONG n;
            if (InterlockedIncrement(&n) <= 10)
                TR_LOG("video: DecoderEndFrame 0x%08lx", hr);
        }
    }
}

/* Packs [header][entries][data...] and sends it inline. */
static HRESULT
trSubmit(PTRITON_DEVICE pD, PTRITON_VDECODER d, UINT count,
         const D3D10DDI_HRESOURCE *phRes, const UINT *pType, const UINT *pOff, const UINT *pSize)
{
    if (!d->pDecoder || !trVideoEnsure(pD))
        return E_INVALIDARG;
    UINT need = 8 + count * 16;
    for (UINT i = 0; i < count; i++)
        need += (pSize[i] + 15u) & ~15u;
    if (need > d->BlobCap) {
        BYTE *nb = (BYTE *)realloc(d->pBlob, need);
        if (!nb)
            return E_OUTOFMEMORY;
        d->pBlob = nb;
        d->BlobCap = need;
    }
    UINT *hdr = (UINT *)d->pBlob;
    hdr[0] = TRITON_NPT_DXVA_MAGIC;
    hdr[1] = count;
    UINT dataOff = 8 + count * 16, n = 0;
    for (UINT i = 0; i < count; i++) {
        PTRITON_RESOURCE r = (PTRITON_RESOURCE)phRes[i].pDrvPrivate;
        if (!r || !r->pSysMem || (UINT64)pOff[i] + pSize[i] > r->SysMemSize) {
            TR_LOG("video: SubmitBuffers: buffer %u type %u not a decoder buffer (off %u size %u)",
                   i, pType[i], pOff[i], pSize[i]);
            continue;
        }
        UINT *e = (UINT *)(d->pBlob + 8 + n * 16);
        /* D3D11_1DDI_VIDEO_DECODER_BUFFER_TYPE has UNKNOWN = 0 in front;
         * the blob carries the API enum (D3D11_VIDEO_DECODER_BUFFER_TYPE). */
        e[0] = pType[i] ? pType[i] - 1 : 0;
        e[1] = dataOff;
        e[2] = pSize[i];
        e[3] = 0;
        memcpy(d->pBlob + dataOff, (BYTE *)r->pSysMem + pOff[i], pSize[i]);
        dataOff += (pSize[i] + 15u) & ~15u;
        n++;
    }
    hdr[1] = n;  /* skipped entries leave unused slots; offsets are explicit */

    D3D11_VIDEO_DECODER_EXTENSION ext;
    memset(&ext, 0, sizeof(ext));
    ext.Function = TRITON_NPT_DXVA_SUBMIT;
    ext.pPrivateInputData = d->pBlob;
    ext.PrivateInputDataSize = dataOff;
    return ID3D11VideoContext_DecoderExtension(pD->pVidCtx, d->pDecoder, &ext);
}

static HRESULT APIENTRY
trVideoDecoderSubmitBuffers(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HDECODE hDecode, UINT Count,
                            const D3D11_1DDI_VIDEO_DECODER_BUFFER_DESC *pDescs)
{
    D3D10DDI_HRESOURCE res[16];
    UINT type[16], off[16], size[16];
    if (Count > 16)
        return E_INVALIDARG;
    for (UINT i = 0; i < Count; i++) {
        res[i] = pDescs[i].hResource;
        type[i] = pDescs[i].BufferType;
        off[i] = pDescs[i].DataOffset;
        size[i] = pDescs[i].DataSize;
    }
    return trSubmit(TR_DEV(hDevice), (PTRITON_VDECODER)hDecode.pDrvPrivate, Count, res, type, off, size);
}

static HRESULT APIENTRY
trVideoDecoderSubmitBuffers1(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HDECODE hDecode, UINT Count,
                             const D3DWDDM2_0DDI_VIDEO_DECODER_BUFFER_DESC1 *pDescs)
{
    D3D10DDI_HRESOURCE res[16];
    UINT type[16], off[16], size[16];
    if (Count > 16)
        return E_INVALIDARG;
    for (UINT i = 0; i < Count; i++) {
        res[i] = pDescs[i].hResource;
        type[i] = pDescs[i].BufferType;
        off[i] = pDescs[i].DataOffset;
        size[i] = pDescs[i].DataSize;
    }
    return trSubmit(TR_DEV(hDevice), (PTRITON_VDECODER)hDecode.pDrvPrivate, Count, res, type, off, size);
}

static HRESULT APIENTRY
trVideoDecoderGetHandle(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HDECODE hDecode, HANDLE *pHandle)
{
    (void)hDevice; (void)hDecode;
    if (pHandle)
        *pHandle = NULL;
    return S_OK;
}

static SIZE_T APIENTRY
trCalcPrivateVideoDecoderOutputViewSize(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEODECODEROUTPUTVIEW *pArgs)
{
    (void)hDevice; (void)pArgs;
    return sizeof(TRITON_VDOV);
}

static HRESULT APIENTRY
trCreateVideoDecoderOutputView(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEODECODEROUTPUTVIEW *pArgs,
                               D3D11_1DDI_HVIDEODECODEROUTPUTVIEW hView, D3D11_1DDI_HRTVIDEODECODEROUTPUTVIEW hRT)
{
    (void)hRT;
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VDOV v = (PTRITON_VDOV)hView.pDrvPrivate;
    PTRITON_RESOURCE r = (PTRITON_RESOURCE)pArgs->hDrvResource.pDrvPrivate;
    v->pView = NULL;
    if (!r || !r->pResource || !trVideoEnsure(pD))
        return E_INVALIDARG;
    D3D11_VIDEO_DECODER_OUTPUT_VIEW_DESC desc;
    memset(&desc, 0, sizeof(desc));
    desc.DecodeProfile = pArgs->DecodeProfile;
    desc.ViewDimension = D3D11_VDOV_DIMENSION_TEXTURE2D;
    desc.Texture2D.ArraySlice = pArgs->FirstArraySlice;
    HRESULT hr = ID3D11VideoDevice_CreateVideoDecoderOutputView(pD->pVidDev, r->pResource, &desc, &v->pView);
    if (FAILED(hr))
        TR_LOG("video: CreateVideoDecoderOutputView slice %u -> 0x%08lx", pArgs->FirstArraySlice, hr);
    return hr;
}

static void APIENTRY
trDestroyVideoDecoderOutputView(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEODECODEROUTPUTVIEW hView)
{
    (void)hDevice;
    PTRITON_VDOV v = (PTRITON_VDOV)hView.pDrvPrivate;
    if (v->pView)
        ID3D11VideoDecoderOutputView_Release(v->pView);
    v->pView = NULL;
}

/* ------------------------------------------------------------------ */
/* Video processor                                                     */
/* ------------------------------------------------------------------ */

static SIZE_T APIENTRY
trCalcPrivateVideoProcessorEnumSize(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEOPROCESSORENUM *pArgs)
{
    (void)hDevice; (void)pArgs;
    return sizeof(TRITON_VPENUM);
}

static HRESULT APIENTRY
trCreateVideoProcessorEnum(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEOPROCESSORENUM *pArgs,
                           D3D11_1DDI_HVIDEOPROCESSORENUM hEnum, D3D11_1DDI_HRTVIDEOPROCESSORENUM hRT)
{
    (void)hRT;
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VPENUM e = (PTRITON_VPENUM)hEnum.pDrvPrivate;
    e->pEnum = NULL;
    if (!trVideoEnsure(pD))
        return E_FAIL;
    return ID3D11VideoDevice_CreateVideoProcessorEnumerator(pD->pVidDev,
        (const D3D11_VIDEO_PROCESSOR_CONTENT_DESC *)&pArgs->Desc, &e->pEnum);
}

static void APIENTRY
trDestroyVideoProcessorEnum(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORENUM hEnum)
{
    (void)hDevice;
    PTRITON_VPENUM e = (PTRITON_VPENUM)hEnum.pDrvPrivate;
    if (e->pEnum)
        ID3D11VideoProcessorEnumerator_Release(e->pEnum);
    e->pEnum = NULL;
}

static void APIENTRY
trCheckVideoProcessorFormat(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORENUM hEnum, DXGI_FORMAT Format, UINT *pFlags)
{
    (void)hDevice;
    PTRITON_VPENUM e = (PTRITON_VPENUM)hEnum.pDrvPrivate;
    *pFlags = 0;
    if (e->pEnum)
        ID3D11VideoProcessorEnumerator_CheckVideoProcessorFormat(e->pEnum, Format, pFlags);
}

static void APIENTRY
trGetVideoProcessorCaps(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORENUM hEnum, D3D11_1DDI_VIDEO_PROCESSOR_CAPS *pCaps)
{
    (void)hDevice;
    PTRITON_VPENUM e = (PTRITON_VPENUM)hEnum.pDrvPrivate;
    memset(pCaps, 0, sizeof(*pCaps));
    if (e->pEnum)
        ID3D11VideoProcessorEnumerator_GetVideoProcessorCaps(e->pEnum, (D3D11_VIDEO_PROCESSOR_CAPS *)pCaps);
}

static void APIENTRY
trGetVideoProcessorRateConversionCaps(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORENUM hEnum, UINT Index,
                                      D3D11_1DDI_VIDEO_PROCESSOR_RATE_CONVERSION_CAPS *pCaps)
{
    (void)hDevice;
    PTRITON_VPENUM e = (PTRITON_VPENUM)hEnum.pDrvPrivate;
    memset(pCaps, 0, sizeof(*pCaps));
    if (e->pEnum)
        ID3D11VideoProcessorEnumerator_GetVideoProcessorRateConversionCaps(e->pEnum, Index,
            (D3D11_VIDEO_PROCESSOR_RATE_CONVERSION_CAPS *)pCaps);
}

static void APIENTRY
trGetVideoProcessorCustomRate(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORENUM hEnum, UINT Caps, UINT Index,
                              D3D11_1DDI_VIDEO_PROCESSOR_CUSTOM_RATE *pRate)
{
    (void)hDevice; (void)hEnum; (void)Caps; (void)Index;
    memset(pRate, 0, sizeof(*pRate));
}

static void APIENTRY
trGetVideoProcessorFilterRange(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORENUM hEnum,
                               D3D11_1DDI_VIDEO_PROCESSOR_FILTER Filter, D3D11_1DDI_VIDEO_PROCESSOR_FILTER_RANGE *pRange)
{
    (void)hDevice;
    PTRITON_VPENUM e = (PTRITON_VPENUM)hEnum.pDrvPrivate;
    memset(pRange, 0, sizeof(*pRange));
    if (e->pEnum)
        ID3D11VideoProcessorEnumerator_GetVideoProcessorFilterRange(e->pEnum, (D3D11_VIDEO_PROCESSOR_FILTER)Filter,
            (D3D11_VIDEO_PROCESSOR_FILTER_RANGE *)pRange);
}

static SIZE_T APIENTRY
trCalcPrivateVideoProcessorSize(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEOPROCESSOR *pArgs)
{
    (void)hDevice; (void)pArgs;
    return sizeof(TRITON_VP);
}

static HRESULT APIENTRY
trCreateVideoProcessor(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEOPROCESSOR *pArgs,
                       D3D11_1DDI_HVIDEOPROCESSOR hVP, D3D11_1DDI_HRTVIDEOPROCESSOR hRT)
{
    (void)hRT;
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VP p = (PTRITON_VP)hVP.pDrvPrivate;
    PTRITON_VPENUM e = (PTRITON_VPENUM)pArgs->hVideoProcessorEnum.pDrvPrivate;
    p->pVP = NULL;
    if (!e || !e->pEnum || !trVideoEnsure(pD))
        return E_INVALIDARG;
    return ID3D11VideoDevice_CreateVideoProcessor(pD->pVidDev, e->pEnum, pArgs->RateConversionCapsIndex, &p->pVP);
}

static void APIENTRY
trDestroyVideoProcessor(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP)
{
    (void)hDevice;
    PTRITON_VP p = (PTRITON_VP)hVP.pDrvPrivate;
    if (p->pVP)
        ID3D11VideoProcessor_Release(p->pVP);
    p->pVP = NULL;
}

#define TR_VP_PRE                                                    \
    PTRITON_DEVICE pD = TR_DEV(hDevice);                             \
    PTRITON_VP p = (PTRITON_VP)hVP.pDrvPrivate;                      \
    if (!p->pVP || !trVideoEnsure(pD)) return

static void APIENTRY
trVPSetOutputTargetRect(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, BOOL Enable, const RECT *pRect)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetOutputTargetRect(pD->pVidCtx, p->pVP, Enable, pRect);
}

static void APIENTRY
trVPSetOutputBackgroundColor(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, BOOL YCbCr,
                             const D3D11_1DDI_VIDEO_COLOR *pColor)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetOutputBackgroundColor(pD->pVidCtx, p->pVP, YCbCr, (const D3D11_VIDEO_COLOR *)pColor);
}

static void APIENTRY
trVPSetOutputColorSpace(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP,
                        const D3D11_1DDI_VIDEO_PROCESSOR_COLOR_SPACE *pCS)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetOutputColorSpace(pD->pVidCtx, p->pVP, (const D3D11_VIDEO_PROCESSOR_COLOR_SPACE *)pCS);
}

static void APIENTRY
trVPSetOutputAlphaFillMode(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP,
                           D3D11_1DDI_VIDEO_PROCESSOR_ALPHA_FILL_MODE Mode, UINT Stream)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetOutputAlphaFillMode(pD->pVidCtx, p->pVP, (D3D11_VIDEO_PROCESSOR_ALPHA_FILL_MODE)Mode, Stream);
}

static void APIENTRY
trVPSetOutputConstriction(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, BOOL Enable, SIZE Size)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetOutputConstriction(pD->pVidCtx, p->pVP, Enable, Size);
}

static void APIENTRY
trVPSetOutputStereoMode(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, BOOL Enable)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetOutputStereoMode(pD->pVidCtx, p->pVP, Enable);
}

static HRESULT APIENTRY
trVPOutputExtension(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, const GUID *pGuid, UINT Size, void *pData)
{
    (void)hDevice; (void)hVP; (void)pGuid; (void)Size; (void)pData;
    return E_NOTIMPL;
}

static void APIENTRY
trVPSetStreamFrameFormat(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream,
                         D3D11_1DDI_VIDEO_FRAME_FORMAT Format)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamFrameFormat(pD->pVidCtx, p->pVP, Stream, (D3D11_VIDEO_FRAME_FORMAT)Format);
}

static void APIENTRY
trVPSetStreamColorSpace(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream,
                        const D3D11_1DDI_VIDEO_PROCESSOR_COLOR_SPACE *pCS)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamColorSpace(pD->pVidCtx, p->pVP, Stream, (const D3D11_VIDEO_PROCESSOR_COLOR_SPACE *)pCS);
}

static void APIENTRY
trVPSetStreamOutputRate(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream,
                        D3D11_1DDI_VIDEO_PROCESSOR_OUTPUT_RATE Rate, BOOL Repeat, const DXGI_RATIONAL *pCustom)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamOutputRate(pD->pVidCtx, p->pVP, Stream, (D3D11_VIDEO_PROCESSOR_OUTPUT_RATE)Rate,
                                                         Repeat, pCustom);
}

static void APIENTRY
trVPSetStreamSourceRect(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, BOOL Enable, const RECT *pRect)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamSourceRect(pD->pVidCtx, p->pVP, Stream, Enable, pRect);
}

static void APIENTRY
trVPSetStreamDestRect(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, BOOL Enable, const RECT *pRect)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamDestRect(pD->pVidCtx, p->pVP, Stream, Enable, pRect);
}

static void APIENTRY
trVPSetStreamAlpha(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, BOOL Enable, FLOAT Alpha)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamAlpha(pD->pVidCtx, p->pVP, Stream, Enable, Alpha);
}

static void APIENTRY
trVPSetStreamPalette(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, UINT Count, const UINT *pEntries)
{
    (void)hDevice; (void)hVP; (void)Stream; (void)Count; (void)pEntries;
}

static void APIENTRY
trVPSetStreamPixelAspectRatio(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, BOOL Enable,
                              const DXGI_RATIONAL *pSrc, const DXGI_RATIONAL *pDst)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamPixelAspectRatio(pD->pVidCtx, p->pVP, Stream, Enable, pSrc, pDst);
}

static void APIENTRY
trVPSetStreamLumaKey(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, BOOL Enable, FLOAT Lo, FLOAT Hi)
{
    (void)hDevice; (void)hVP; (void)Stream; (void)Enable; (void)Lo; (void)Hi;
}

static void APIENTRY
trVPSetStreamStereoFormat(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, BOOL Enable,
                          D3D11_1DDI_VIDEO_PROCESSOR_STEREO_FORMAT Format, BOOL LeftFirst, BOOL RightFirst,
                          D3D11_1DDI_VIDEO_PROCESSOR_STEREO_FLIP_MODE Flip, int Offset)
{
    (void)hDevice; (void)hVP; (void)Stream; (void)Enable; (void)Format; (void)LeftFirst; (void)RightFirst; (void)Flip; (void)Offset;
}

static void APIENTRY
trVPSetStreamAutoProcessingMode(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, BOOL Enable)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamAutoProcessingMode(pD->pVidCtx, p->pVP, Stream, Enable);
}

static void APIENTRY
trVPSetStreamFilter(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream,
                    D3D11_1DDI_VIDEO_PROCESSOR_FILTER Filter, BOOL Enable, int Level)
{
    (void)hDevice; (void)hVP; (void)Stream; (void)Filter; (void)Enable; (void)Level;
}

static void APIENTRY
trVPSetStreamRotation(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, BOOL Enable,
                      D3D11_1DDI_VIDEO_PROCESSOR_ROTATION Rotation)
{
    TR_VP_PRE;
    ID3D11VideoContext_VideoProcessorSetStreamRotation(pD->pVidCtx, p->pVP, Stream, Enable, (D3D11_VIDEO_PROCESSOR_ROTATION)Rotation);
}

static HRESULT APIENTRY
trVPStreamExtension(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, const GUID *pGuid,
                    UINT Size, void *pData)
{
    (void)hDevice; (void)hVP; (void)Stream; (void)pGuid; (void)Size; (void)pData;
    return E_NOTIMPL;
}

static ID3D11VideoProcessorInputView *
trVPIV(D3D11_1DDI_HVIDEOPROCESSORINPUTVIEW h)
{
    PTRITON_VPIV v = (PTRITON_VPIV)h.pDrvPrivate;
    return v ? v->pView : NULL;
}

static HRESULT APIENTRY
trVideoProcessorBlt(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, D3D11_1DDI_HVIDEOPROCESSOROUTPUTVIEW hOut,
                    UINT OutputFrame, UINT StreamCount, const D3D11_1DDI_VIDEO_PROCESSOR_STREAM *pStreams)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VP p = (PTRITON_VP)hVP.pDrvPrivate;
    PTRITON_VPOV o = (PTRITON_VPOV)hOut.pDrvPrivate;
    if (!p->pVP || !o || !o->pView || !trVideoEnsure(pD) || StreamCount > 8)
        return E_INVALIDARG;

    D3D11_VIDEO_PROCESSOR_STREAM s[8];
    ID3D11VideoProcessorInputView *past[8][4], *future[8][4];
    memset(s, 0, sizeof(s));
    for (UINT i = 0; i < StreamCount; i++) {
        const D3D11_1DDI_VIDEO_PROCESSOR_STREAM *in = &pStreams[i];
        s[i].Enable = in->Enable;
        s[i].OutputIndex = in->OutputIndex;
        s[i].InputFrameOrField = in->InputFrameOrField;
        s[i].PastFrames = in->PastFrames < 4 ? in->PastFrames : 4;
        s[i].FutureFrames = in->FutureFrames < 4 ? in->FutureFrames : 4;
        for (UINT k = 0; k < s[i].PastFrames; k++)
            past[i][k] = trVPIV(in->pPastSurfaces[k]);
        for (UINT k = 0; k < s[i].FutureFrames; k++)
            future[i][k] = trVPIV(in->pFutureSurfaces[k]);
        s[i].ppPastSurfaces = s[i].PastFrames ? past[i] : NULL;
        s[i].ppFutureSurfaces = s[i].FutureFrames ? future[i] : NULL;
        s[i].pInputSurface = trVPIV(in->hInputSurface);
        s[i].pInputSurfaceRight = NULL;
    }
    return ID3D11VideoContext_VideoProcessorBlt(pD->pVidCtx, p->pVP, o->pView, OutputFrame, StreamCount, s);
}

static SIZE_T APIENTRY
trCalcPrivateVPIVSize(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEOPROCESSORINPUTVIEW *pArgs)
{
    (void)hDevice; (void)pArgs;
    return sizeof(TRITON_VPIV);
}

static HRESULT APIENTRY
trCreateVPIV(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEOPROCESSORINPUTVIEW *pArgs,
             D3D11_1DDI_HVIDEOPROCESSORINPUTVIEW hView, D3D11_1DDI_HRTVIDEOPROCESSORINPUTVIEW hRT)
{
    (void)hRT;
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VPIV v = (PTRITON_VPIV)hView.pDrvPrivate;
    PTRITON_RESOURCE r = (PTRITON_RESOURCE)pArgs->hDrvResource.pDrvPrivate;
    PTRITON_VPENUM e = (PTRITON_VPENUM)pArgs->hDrvVideoProcessorEnum.pDrvPrivate;
    v->pView = NULL;
    if (!r || !r->pResource || !e || !e->pEnum || !trVideoEnsure(pD))
        return E_INVALIDARG;
    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC desc;
    memset(&desc, 0, sizeof(desc));
    desc.FourCC = pArgs->FourCC;
    desc.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
    desc.Texture2D.MipSlice = pArgs->MipSlice;
    desc.Texture2D.ArraySlice = pArgs->FirstArraySlice;
    return ID3D11VideoDevice_CreateVideoProcessorInputView(pD->pVidDev, r->pResource, e->pEnum, &desc, &v->pView);
}

static void APIENTRY
trDestroyVPIV(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORINPUTVIEW hView)
{
    (void)hDevice;
    PTRITON_VPIV v = (PTRITON_VPIV)hView.pDrvPrivate;
    if (v->pView)
        ID3D11VideoProcessorInputView_Release(v->pView);
    v->pView = NULL;
}

static SIZE_T APIENTRY
trCalcPrivateVPOVSize(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEOPROCESSOROUTPUTVIEW *pArgs)
{
    (void)hDevice; (void)pArgs;
    return sizeof(TRITON_VPOV);
}

static HRESULT APIENTRY
trCreateVPOV(D3D10DDI_HDEVICE hDevice, const D3D11_1DDIARG_CREATEVIDEOPROCESSOROUTPUTVIEW *pArgs,
             D3D11_1DDI_HVIDEOPROCESSOROUTPUTVIEW hView, D3D11_1DDI_HRTVIDEOPROCESSOROUTPUTVIEW hRT)
{
    (void)hRT;
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    PTRITON_VPOV v = (PTRITON_VPOV)hView.pDrvPrivate;
    PTRITON_RESOURCE r = (PTRITON_RESOURCE)pArgs->hDrvResource.pDrvPrivate;
    PTRITON_VPENUM e = (PTRITON_VPENUM)pArgs->hDrvVideoProcessorEnum.pDrvPrivate;
    v->pView = NULL;
    if (!r || !r->pResource || !e || !e->pEnum || !trVideoEnsure(pD))
        return E_INVALIDARG;
    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC desc;
    memset(&desc, 0, sizeof(desc));
    if (pArgs->ArraySize > 1 || pArgs->FirstArraySlice) {
        desc.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2DARRAY;
        desc.Texture2DArray.MipSlice = pArgs->MipSlice;
        desc.Texture2DArray.FirstArraySlice = pArgs->FirstArraySlice;
        desc.Texture2DArray.ArraySize = pArgs->ArraySize ? pArgs->ArraySize : 1;
    } else {
        desc.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
        desc.Texture2D.MipSlice = pArgs->MipSlice;
    }
    return ID3D11VideoDevice_CreateVideoProcessorOutputView(pD->pVidDev, r->pResource, e->pEnum, &desc, &v->pView);
}

static void APIENTRY
trDestroyVPOV(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOROUTPUTVIEW hView)
{
    (void)hDevice;
    PTRITON_VPOV v = (PTRITON_VPOV)hView.pDrvPrivate;
    if (v->pView)
        ID3D11VideoProcessorOutputView_Release(v->pView);
    v->pView = NULL;
}

static void APIENTRY
trVPIVReadAfterWriteHazard(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORINPUTVIEW hView, D3D10DDI_HRESOURCE hRes)
{
    (void)hDevice; (void)hView; (void)hRes;
}

/* ------------------------------------------------------------------ */
/* Content protection: none                                            */
/* ------------------------------------------------------------------ */

static HRESULT APIENTRY trVidStubHr(void) { return E_NOTIMPL; }
static void APIENTRY trVidStubV(void) { }
static SIZE_T APIENTRY trVidStubSize(void) { return 16; }

static HRESULT APIENTRY
trGetContentProtectionCaps(D3D10DDI_HDEVICE hDevice, const GUID *pCrypto, const GUID *pProfile,
                           D3D11_1DDI_VIDEO_CONTENT_PROTECTION_CAPS *pCaps)
{
    (void)hDevice; (void)pCrypto; (void)pProfile;
    if (pCaps)
        memset(pCaps, 0, sizeof(*pCaps));
    return E_NOTIMPL;
}

/* ------------------------------------------------------------------ */
/* WDDM 2.0 additions                                                  */
/* ------------------------------------------------------------------ */

static void APIENTRY
trQueryVideoCapabilities(D3D10DDI_HDEVICE hDevice, D3DWDDM2_0DDI_VIDEO_CAPABILITY_QUERY Query, UINT Size, void *pData)
{
    PTRITON_DEVICE pD = TR_DEV(hDevice);
    switch (Query) {
    case D3DWDDM2_0DDI_VIDEO_CAPABILITY_QUERY_DECODER_CAPS:
        if (Size >= sizeof(D3DWDDM2_0DDI_VIDEO_CAPABILITY_DECODER_CAPS)) {
            D3DWDDM2_0DDI_VIDEO_CAPABILITY_DECODER_CAPS *c = pData;
            BOOL ok = FALSE;
            if (trVideoEnsure(pD))
                ID3D11VideoDevice_CheckVideoDecoderFormat(pD->pVidDev, &c->DecodeProfile, DXGI_FORMAT_NV12, &ok);
            c->Caps = ok ? 0 : D3DWDDM2_0DDI_VIDEO_DECODER_CAP_UNSUPPORTED;
        }
        break;
    case D3DWDDM2_0DDI_VIDEO_CAPABILITY_QUERY_DECODER_DOWNSAMPLING:
        if (Size >= sizeof(D3DWDDM2_0DDI_VIDEO_CAPABILITY_DECODER_DOWNSAMPLING)) {
            D3DWDDM2_0DDI_VIDEO_CAPABILITY_DECODER_DOWNSAMPLING *c = pData;
            c->Supported = FALSE;
            c->RealTime = FALSE;
        }
        break;
    case D3DWDDM2_0DDI_VIDEO_CAPABILITY_QUERY_DECODER_DOWNSAMPLE_OUTPUT_FORMAT:
        if (Size >= sizeof(D3DWDDM2_0DDI_VIDEO_CAPABILITY_DECODER_DOWNSAMPLE_OUTPUT_FORMAT))
            ((D3DWDDM2_0DDI_VIDEO_CAPABILITY_DECODER_DOWNSAMPLE_OUTPUT_FORMAT *)pData)->Supported = FALSE;
        break;
    default:
        break;
    }
}

static void APIENTRY
trCheckVideoProcessorFormatConversion(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSORENUM hEnum,
                                      D3DWDDM2_0DDI_CHECK_VIDEO_PROCESSOR_FORMAT_CONVERSION *pConv)
{
    UINT inFlags = 0, outFlags = 0;
    trCheckVideoProcessorFormat(hDevice, hEnum, pConv->InputFormat, &inFlags);
    trCheckVideoProcessorFormat(hDevice, hEnum, pConv->OutputFormat, &outFlags);
    pConv->Supported = (inFlags & D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT) &&
                       (outFlags & D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_OUTPUT);
}

/* DXGI color space -> D3D11.0 VP color space (the host has no VideoContext1) */
static D3D11_VIDEO_PROCESSOR_COLOR_SPACE
trColorSpace(D3DDDI_COLOR_SPACE_TYPE cs)
{
    D3D11_VIDEO_PROCESSOR_COLOR_SPACE c;
    memset(&c, 0, sizeof(c));
    switch ((int)cs) {
    case DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709:
    case DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709:
        c.RGB_Range = 0;
        break;
    case DXGI_COLOR_SPACE_RGB_STUDIO_G22_NONE_P709:
        c.RGB_Range = 1;
        break;
    case DXGI_COLOR_SPACE_YCBCR_FULL_G22_NONE_P709_X601:
        c.YCbCr_Matrix = 0;
        c.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_0_255;
        break;
    case DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P601:
        c.YCbCr_Matrix = 0;
        c.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_16_235;
        break;
    case DXGI_COLOR_SPACE_YCBCR_FULL_G22_LEFT_P601:
        c.YCbCr_Matrix = 0;
        c.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_0_255;
        break;
    case DXGI_COLOR_SPACE_YCBCR_FULL_G22_LEFT_P709:
        c.YCbCr_Matrix = 1;
        c.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_0_255;
        break;
    default: /* studio 709 and friends */
        c.YCbCr_Matrix = 1;
        c.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_16_235;
        break;
    }
    return c;
}

static void APIENTRY
trVPSetOutputColorSpace1(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, D3DDDI_COLOR_SPACE_TYPE cs)
{
    TR_VP_PRE;
    D3D11_VIDEO_PROCESSOR_COLOR_SPACE c = trColorSpace(cs);
    ID3D11VideoContext_VideoProcessorSetOutputColorSpace(pD->pVidCtx, p->pVP, &c);
}

static void APIENTRY
trVPSetStreamColorSpace1(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT Stream, D3DDDI_COLOR_SPACE_TYPE cs)
{
    TR_VP_PRE;
    D3D11_VIDEO_PROCESSOR_COLOR_SPACE c = trColorSpace(cs);
    ID3D11VideoContext_VideoProcessorSetStreamColorSpace(pD->pVidCtx, p->pVP, Stream, &c);
}

static HRESULT APIENTRY
trVPGetBehaviorHints(D3D10DDI_HDEVICE hDevice, D3D11_1DDI_HVIDEOPROCESSOR hVP, UINT W, UINT H, DXGI_FORMAT Fmt,
                     UINT Count, const D3DWDDM2_0DDI_VIDEO_PROCESSOR_STREAM_BEHAVIOR_HINT *pStreams, UINT *pHints)
{
    (void)hDevice; (void)hVP; (void)W; (void)H; (void)Fmt; (void)Count; (void)pStreams;
    if (pHints)
        *pHints = 0;
    return S_OK;
}

/* ------------------------------------------------------------------ */
/* Tables                                                              */
/* ------------------------------------------------------------------ */

static void
trFill11_1(D3D11_1DDI_VIDEODEVICEFUNCS *f)
{
    memset(f, 0, sizeof(*f));
    f->pfnGetVideoDecoderProfileCount = trGetVideoDecoderProfileCount;
    f->pfnGetVideoDecoderProfile = trGetVideoDecoderProfile;
    f->pfnCheckVideoDecoderFormat = trCheckVideoDecoderFormat;
    f->pfnGetVideoDecoderConfigCount = trGetVideoDecoderConfigCount;
    f->pfnGetVideoDecoderConfig = trGetVideoDecoderConfig;
    f->pfnGetVideoDecoderBufferTypeCount = trGetVideoDecoderBufferTypeCount;
    f->pfnGetVideoDecoderBufferInfo = trGetVideoDecoderBufferInfo;
    f->pfnCalcPrivateVideoDecoderSize = trCalcPrivateVideoDecoderSize;
    f->pfnCreateVideoDecoder = trCreateVideoDecoder;
    f->pfnDestroyVideoDecoder = trDestroyVideoDecoder;
    f->pfnVideoDecoderExtension = trVideoDecoderExtension;
    f->pfnVideoDecoderBeginFrame = trVideoDecoderBeginFrame;
    f->pfnVideoDecoderEndFrame = trVideoDecoderEndFrame;
    f->pfnVideoDecoderSubmitBuffers = trVideoDecoderSubmitBuffers;
    f->pfnCalcPrivateVideoProcessorEnumSize = trCalcPrivateVideoProcessorEnumSize;
    f->pfnCreateVideoProcessorEnum = trCreateVideoProcessorEnum;
    f->pfnDestroyVideoProcessorEnum = trDestroyVideoProcessorEnum;
    f->pfnCheckVideoProcessorFormat = trCheckVideoProcessorFormat;
    f->pfnGetVideoProcessorCaps = trGetVideoProcessorCaps;
    f->pfnGetVideoProcessorRateConversionCaps = trGetVideoProcessorRateConversionCaps;
    f->pfnGetVideoProcessorCustomRate = trGetVideoProcessorCustomRate;
    f->pfnGetVideoProcessorFilterRange = trGetVideoProcessorFilterRange;
    f->pfnCalcPrivateVideoProcessorSize = trCalcPrivateVideoProcessorSize;
    f->pfnCreateVideoProcessor = trCreateVideoProcessor;
    f->pfnDestroyVideoProcessor = trDestroyVideoProcessor;
    f->pfnVideoProcessorSetOutputTargetRect = trVPSetOutputTargetRect;
    f->pfnVideoProcessorSetOutputBackgroundColor = trVPSetOutputBackgroundColor;
    f->pfnVideoProcessorSetOutputColorSpace = trVPSetOutputColorSpace;
    f->pfnVideoProcessorSetOutputAlphaFillMode = trVPSetOutputAlphaFillMode;
    f->pfnVideoProcessorSetOutputConstriction = trVPSetOutputConstriction;
    f->pfnVideoProcessorSetOutputStereoMode = trVPSetOutputStereoMode;
    f->pfnVideoProcessorSetOutputExtension = trVPOutputExtension;
    f->pfnVideoProcessorGetOutputExtension = trVPOutputExtension;
    f->pfnVideoProcessorSetStreamFrameFormat = trVPSetStreamFrameFormat;
    f->pfnVideoProcessorSetStreamColorSpace = trVPSetStreamColorSpace;
    f->pfnVideoProcessorSetStreamOutputRate = trVPSetStreamOutputRate;
    f->pfnVideoProcessorSetStreamSourceRect = trVPSetStreamSourceRect;
    f->pfnVideoProcessorSetStreamDestRect = trVPSetStreamDestRect;
    f->pfnVideoProcessorSetStreamAlpha = trVPSetStreamAlpha;
    f->pfnVideoProcessorSetStreamPalette = trVPSetStreamPalette;
    f->pfnVideoProcessorSetStreamPixelAspectRatio = trVPSetStreamPixelAspectRatio;
    f->pfnVideoProcessorSetStreamLumaKey = trVPSetStreamLumaKey;
    f->pfnVideoProcessorSetStreamStereoFormat = trVPSetStreamStereoFormat;
    f->pfnVideoProcessorSetStreamAutoProcessingMode = trVPSetStreamAutoProcessingMode;
    f->pfnVideoProcessorSetStreamFilter = trVPSetStreamFilter;
    f->pfnVideoProcessorSetStreamExtension = trVPStreamExtension;
    f->pfnVideoProcessorGetStreamExtension = trVPStreamExtension;
    f->pfnVideoProcessorBlt = trVideoProcessorBlt;
    f->pfnCalcPrivateVideoDecoderOutputViewSize = trCalcPrivateVideoDecoderOutputViewSize;
    f->pfnCreateVideoDecoderOutputView = trCreateVideoDecoderOutputView;
    f->pfnDestroyVideoDecoderOutputView = trDestroyVideoDecoderOutputView;
    f->pfnCalcPrivateVideoProcessorInputViewSize = trCalcPrivateVPIVSize;
    f->pfnCreateVideoProcessorInputView = trCreateVPIV;
    f->pfnDestroyVideoProcessorInputView = trDestroyVPIV;
    f->pfnCalcPrivateVideoProcessorOutputViewSize = trCalcPrivateVPOVSize;
    f->pfnCreateVideoProcessorOutputView = trCreateVPOV;
    f->pfnDestroyVideoProcessorOutputView = trDestroyVPOV;
    f->pfnVideoProcessorInputViewReadAfterWriteHazard = trVPIVReadAfterWriteHazard;
    f->pfnGetContentProtectionCaps = trGetContentProtectionCaps;
    f->pfnGetCryptoKeyExchangeType = (PFND3D11_1DDI_GETCRYPTOKEYEXCHANGETYPE)trVidStubHr;
    f->pfnCalcPrivateCryptoSessionSize = (PFND3D11_1DDI_CALCPRIVATECRYPTOSESSIONSIZE)trVidStubSize;
    f->pfnCreateCryptoSession = (PFND3D11_1DDI_CREATECRYPTOSESSION)trVidStubHr;
    f->pfnDestroyCryptoSession = (PFND3D11_1DDI_DESTROYCRYPTOSESSION)trVidStubV;
    f->pfnGetCertificateSize = (PFND3D11_1DDI_GETCERTIFICATESIZE)trVidStubHr;
    f->pfnGetCertificate = (PFND3D11_1DDI_GETCERTIFICATE)trVidStubHr;
    f->pfnNegotiateCryptoSessionKeyExchange = (PFND3D11_1DDI_NEGOTIATECRYPTOSESSIONKEYESCHANGE)trVidStubHr;
    f->pfnEncryptionBlt = (PFND3D11_1DDI_ENCRYPTIONBLT)trVidStubV;
    f->pfnDecryptionBlt = (PFND3D11_1DDI_DECRYPTIONBLT)trVidStubV;
    f->pfnStartSessionKeyRefresh = (PFND3D11_1DDI_STARTSESSIONKEYREFRESH)trVidStubV;
    f->pfnFinishSessionKeyRefresh = (PFND3D11_1DDI_FINISHSESSIONKEYREFRESH)trVidStubV;
    f->pfnGetEncryptionBltKey = (PFND3D11_1DDI_GETENCRYPTIONBLTKEY)trVidStubHr;
    f->pfnCalcPrivateAuthenticatedChannelSize = (PFND3D11_1DDI_CALCPRIVATEAUTHENTICATEDCHANNELSIZE)trVidStubSize;
    f->pfnCreateAuthenticatedChannel = (PFND3D11_1DDI_CREATEAUTHENTICATEDCHANNEL)trVidStubHr;
    f->pfnDestroyAuthenticatedChannel = (PFND3D11_1DDI_DESTROYAUTHENTICATEDCHANNEL)trVidStubV;
    f->pfnNegotiateAuthenticatedChannelKeyExchange = (PFND3D11_1DDI_NEGOTIATEAUTHENTICATEDCHANNELKEYEXCHANGE)trVidStubHr;
    f->pfnQueryAuthenticatedChannel = (PFND3D11_1DDI_QUERYAUTHENTICATEDCHANNEL)trVidStubHr;
    f->pfnConfigureAuthenticatedChannel = (PFND3D11_1DDI_CONFIGUREAUTHENTICATEDCHANNEL)trVidStubHr;
    f->pfnVideoDecoderGetHandle = trVideoDecoderGetHandle;
    f->pfnCryptoSessionGetHandle = (PFND3D11_1DDI_CRYPTOSESSIONGETHANDLE)trVidStubHr;
    f->pfnVideoProcessorSetStreamRotation = trVPSetStreamRotation;
    f->pfnGetCaptureHandle = (PFND3D11_1DDI_GETCAPTUREHANDLE)trVidStubV;
}

/* The 2.0 and 2.1 tables extend the 11.1 one: same members in the same order
 * (checked against the WDK headers), new ones appended. */
static void
trFill2_0(D3DWDDM2_0DDI_VIDEODEVICEFUNCS *f)
{
    trFill11_1((D3D11_1DDI_VIDEODEVICEFUNCS *)f);
    f->pfnGetDataForNewHardwareKey = (PFND3DWDDM2_0DDI_GETDATAFORNEWHARDWAREKEY)trVidStubHr;
    f->pfnCheckCryptoSessionStatus = (PFND3DWDDM2_0DDI_CHECKCRYPTOSESSIONSTATUS)trVidStubV;
    f->pfnVideoDecoderSubmitBuffers1 = trVideoDecoderSubmitBuffers1;
    f->pfnQueryVideoCapabilities = trQueryVideoCapabilities;
    f->pfnCheckVideoProcessorFormatConversion = trCheckVideoProcessorFormatConversion;
    f->pfnVideoDecoderEnableDownsampling = (PFND3DWDDM2_0DDI_VIDEODECODERENABLEDOWNSAMPLING)trVidStubHr;
    f->pfnVideoDecoderUpdateDownsampling = (PFND3DWDDM2_0DDI_VIDEODECODERUPDATEDOWNSAMPLING)trVidStubHr;
    f->pfnVideoProcessorSetStreamMirror = (PFND3DWDDM2_0DDI_VIDEOPROCESSORSETSTREAMMIRROR)trVidStubV;
    f->pfnVideoProcessorSetOutputColorSpace1 = trVPSetOutputColorSpace1;
    f->pfnVideoProcessorSetStreamColorSpace1 = trVPSetStreamColorSpace1;
    f->pfnVideoProcessorSetOutputShaderUsage = (PFND3DWDDM2_0DDI_VIDEOPROCESSORSETOUTPUTSHADERUSAGE)trVidStubV;
    f->pfnVideoProcessorGetBehaviorHints = trVPGetBehaviorHints;
    f->pfnGetCryptoSessionPrivateDataSize = (PFND3DWDDM2_0DDI_GETCRYPTOSESSIONPRIVATEDATASIZE)trVidStubV;
}

static void
trFill2_1(D3DWDDM2_1DDI_VIDEODEVICEFUNCS *f)
{
    trFill2_0((D3DWDDM2_0DDI_VIDEODEVICEFUNCS *)f);
    f->pfnVideoProcessorSetOutputHDRMetaData = (PFND3DWDDM2_1DDI_VIDEOPROCESSORSETOUTPUTHDRMETADATA)trVidStubV;
    f->pfnVideoProcessorSetStreamHDRMetaData = (PFND3DWDDM2_1DDI_VIDEOPROCESSORSETSTREAMHDRMETADATA)trVidStubV;
}

HRESULT APIENTRY
tritonRetrieveSubObject(D3D10DDI_HDEVICE hDevice, UINT32 SubDeviceID, SIZE_T ParamSize, void *pParams,
                        SIZE_T OutputParamSize, void *pOutput)
{
    (void)hDevice; (void)OutputParamSize; (void)pOutput;
    if (getenv("TRITON_NOVIDEO")) {
        TR_LOG("video: RetrieveSubObject(%u) refused (TRITON_NOVIDEO)", SubDeviceID);
        return E_NOTIMPL;
    }
    switch (SubDeviceID) {
    case D3D11_1DDI_VIDEO_FUNCTIONS:
        if (ParamSize < sizeof(D3D11_1DDI_VIDEO_INPUT) || !pParams)
            return E_INVALIDARG;
        trFill11_1(((D3D11_1DDI_VIDEO_INPUT *)pParams)->p11VideoDeviceFuncs);
        break;
    case D3DWDDM2_0DDI_VIDEO_FUNCTIONS:
        if (ParamSize < sizeof(D3DWDDM2_0DDI_VIDEO_INPUT) || !pParams)
            return E_INVALIDARG;
        trFill2_0(((D3DWDDM2_0DDI_VIDEO_INPUT *)pParams)->pWDDM2_0VideoDeviceFuncs);
        break;
    case D3DWDDM2_1DDI_VIDEO_FUNCTIONS:
        if (ParamSize < sizeof(D3DWDDM2_1DDI_VIDEO_INPUT) || !pParams)
            return E_INVALIDARG;
        trFill2_1(((D3DWDDM2_1DDI_VIDEO_INPUT *)pParams)->pWDDM2_1VideoDeviceFuncs);
        break;
    default:
        TR_LOG("video: RetrieveSubObject(%u) not supported", SubDeviceID);
        return E_NOTIMPL;
    }
    TR_LOG("video: RetrieveSubObject(%u) -> video function table", SubDeviceID);
    return S_OK;
}
