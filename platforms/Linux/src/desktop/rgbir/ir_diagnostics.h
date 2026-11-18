#pragma once
#include "camera.h"
#include "hiface/hiface_rgbir.h"
#include <cstdio>

namespace hiface_linux_demo::rgbir {
// Statistics from the decoded IR frame used by this result, without retaining pixels.
void reportIrDiagnostic(std::FILE* output, const RawCameraFrame& raw, const CameraFrame& frame,
                        const HiFaceSearchInfraredResultV1& ir, HiFaceSearchEndReasonV1 end_reason,
                        float threshold) noexcept;
}
