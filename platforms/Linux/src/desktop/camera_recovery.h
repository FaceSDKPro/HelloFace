#ifndef HIFACE_DEMO_CAMERA_RECOVERY_H
#define HIFACE_DEMO_CAMERA_RECOVERY_H
#include <cstdint>

namespace hiface_linux_demo {
// Three reopen attempts with 2/4/8 second delays, then a one-minute cooldown.
// Real fresh frames, never image brightness, determine camera health.
class CameraRecovery {
public:
    void reset() { attempts_ = 0; next_ = healthy_since_ = -1; cooldown_ = 0; }
    bool retry(int64_t now, bool healthy) {
        if (healthy) {
            if (healthy_since_ < 0) healthy_since_ = now;
            if (now - healthy_since_ >= 30000) { attempts_ = 0; cooldown_ = 0; }
            next_ = -1;
            return false;
        }
        healthy_since_ = -1;
        if (next_ < 0) next_ = now + 2000;
        if (now < next_ || now < cooldown_) return false;
        if (attempts_ == 3) attempts_ = 0;
        ++attempts_;
        next_ = now + (2000LL << attempts_);
        if (attempts_ == 3) cooldown_ = now + 60000;
        return true;
    }
    unsigned attempt() const { return attempts_; }
private:
    unsigned attempts_ = 0;
    int64_t next_ = -1, healthy_since_ = -1, cooldown_ = 0;
};
}
#endif
