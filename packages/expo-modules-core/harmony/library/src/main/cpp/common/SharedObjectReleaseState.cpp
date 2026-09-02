#include "SharedObjectReleaseState.h"

#include <utility>

namespace expo::harmony {

SharedObjectReleaseState::SharedObjectReleaseState(
    long objectId,
    Releaser releaser)
    : objectId_(objectId), releaser_(std::move(releaser)) {}

SharedObjectReleaseState::~SharedObjectReleaseState() noexcept {
  release();
}

bool SharedObjectReleaseState::release() noexcept {
  if (released_.exchange(true, std::memory_order_acq_rel)) {
    return false;
  }
  try {
    if (releaser_) {
      releaser_(objectId_);
    }
  } catch (...) {
    // A native exception must never escape a GC finalizer.
  }
  return true;
}

bool SharedObjectReleaseState::isReleased() const noexcept {
  return released_.load(std::memory_order_acquire);
}

}  // namespace expo::harmony
