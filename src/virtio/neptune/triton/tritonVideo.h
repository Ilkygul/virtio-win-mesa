/*
 * Copyright 2026 Turing Software LLC
 * SPDX-License-Identifier: MIT
 */
#ifndef TRITON_VIDEO_H_INCLUDED
#define TRITON_VIDEO_H_INCLUDED

#include "triton.h"

HRESULT APIENTRY tritonRetrieveSubObject(D3D10DDI_HDEVICE hDevice, UINT32 SubDeviceID, SIZE_T ParamSize,
                                         void *pParams, SIZE_T OutputParamSize, void *pOutput);
void tritonVideoDestroyDevice(PTRITON_DEVICE pD);
BOOL tritonVideoCreateDecoderBuffer(PTRITON_RESOURCE r, UINT size, UINT type);

#endif
