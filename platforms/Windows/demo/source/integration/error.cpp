#include "hiface/error.hpp"
namespace hiface {
namespace {
const char* statusName(HiFaceStatus status) {
    switch (status) {
        case HIFACE_STATUS_INVALID_ARGUMENT: return "invalid argument";
        case HIFACE_STATUS_INVALID_STATE: return "invalid SDK state; see diagnostic log";
        case HIFACE_STATUS_MODEL_LOAD_FAILED: return "model load failed; check models and diagnostic log";
        case HIFACE_STATUS_UNSUPPORTED_FORMAT: return "unsupported image or camera format";
        case HIFACE_STATUS_RESOURCE_EXHAUSTED: return "insufficient resources";
        case HIFACE_STATUS_BUSY: return "SDK busy";
        case HIFACE_STATUS_DATABASE_ERROR: return "database error; check write permission and diagnostic log";
        case HIFACE_STATUS_ALREADY_EXISTS: return "person ID already exists; choose another ID";
        case HIFACE_STATUS_NOT_FOUND: return "record not found";
        case HIFACE_STATUS_IMAGE_NO_FACE: return "no face in image";
        case HIFACE_STATUS_IMAGE_FACE_TOO_SMALL: return "face too small; move closer";
        case HIFACE_STATUS_LICENSE_MISSING: return "SDK authorization missing; update the SDK or contact support";
        case HIFACE_STATUS_LICENSE_INVALID: return "SDK authorization invalid; check the application package and contact support";
        case HIFACE_STATUS_LICENSE_NOT_YET_VALID: return "SDK authorization not yet valid; check the system date or contact support";
        case HIFACE_STATUS_LICENSE_EXPIRED: return "SDK authorization expired; update the SDK or contact support";
        case HIFACE_STATUS_LICENSE_FEATURE_DENIED: return "feature not included in SDK authorization";
        case HIFACE_STATUS_LICENSE_CLOCK_INVALID: return "device time invalid; check the system clock and contact support if the error persists";
        default: return "see diagnostic log";
    }
}
}
Error::Error(HiFaceStatus value, const std::string& operation)
    : std::runtime_error(operation + ": " + statusName(value) + " (HiFace " + std::to_string(value) + ")"), status(value) {}
void check(HiFaceStatus status, const char* operation) {
    if (status != HIFACE_STATUS_OK) throw Error(status, operation);
}

}
