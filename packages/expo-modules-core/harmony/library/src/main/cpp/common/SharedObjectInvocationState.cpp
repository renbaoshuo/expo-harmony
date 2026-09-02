#include "SharedObjectInvocationState.h"

namespace expo::harmony {

bool SharedObjectInvocationState::acquire(long objectId) {
  if (objectId <= 0 || releaseRequested_.contains(objectId)) {
    return false;
  }
  ++activeCounts_[objectId];
  return true;
}

bool SharedObjectInvocationState::release(long objectId) noexcept {
  auto active = activeCounts_.find(objectId);
  if (active == activeCounts_.end() || active->second == 0) {
    return false;
  }
  if (--active->second > 0) {
    return false;
  }
  activeCounts_.erase(active);
  return releaseRequested_.contains(objectId);
}

SharedObjectReleaseReadiness SharedObjectInvocationState::requestRelease(
    long objectId) {
  if (objectId <= 0 || !releaseRequested_.insert(objectId).second) {
    return SharedObjectReleaseReadiness::AlreadyRequested;
  }
  return activeCount(objectId) == 0
      ? SharedObjectReleaseReadiness::Ready
      : SharedObjectReleaseReadiness::Deferred;
}

bool SharedObjectInvocationState::isReleaseRequested(
    long objectId) const noexcept {
  return releaseRequested_.contains(objectId);
}

bool SharedObjectInvocationState::isReadyToFinalize(
    long objectId) const noexcept {
  return isReleaseRequested(objectId) && activeCount(objectId) == 0;
}

bool SharedObjectInvocationState::beginFinalization(long objectId) noexcept {
  if (!isReadyToFinalize(objectId)) {
    return false;
  }
  try {
    return finalizing_.insert(objectId).second;
  } catch (...) {
    return false;
  }
}

bool SharedObjectInvocationState::isFinalizing(long objectId) const noexcept {
  return finalizing_.contains(objectId);
}

bool SharedObjectInvocationState::hasFinalizing() const noexcept {
  return !finalizing_.empty();
}

size_t SharedObjectInvocationState::activeCount(long objectId) const noexcept {
  auto active = activeCounts_.find(objectId);
  return active == activeCounts_.end() ? 0 : active->second;
}

void SharedObjectInvocationState::completeRelease(long objectId) noexcept {
  activeCounts_.erase(objectId);
  releaseRequested_.erase(objectId);
  finalizing_.erase(objectId);
}

void SharedObjectInvocationState::clear() noexcept {
  activeCounts_.clear();
  releaseRequested_.clear();
  finalizing_.clear();
}

}  // namespace expo::harmony
