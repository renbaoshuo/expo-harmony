#include "RuntimeInvocationState.h"

namespace expo::harmony {

void RuntimeInvocationState::acquire() noexcept {
  ++activeCount_;
}

bool RuntimeInvocationState::release() noexcept {
  if (activeCount_ == 0) {
    return false;
  }
  --activeCount_;
  return drainRequested_ && activeCount_ == 0;
}

bool RuntimeInvocationState::requestDrain() noexcept {
  drainRequested_ = true;
  return activeCount_ == 0;
}

size_t RuntimeInvocationState::activeCount() const noexcept {
  return activeCount_;
}

bool RuntimeInvocationState::isDrainRequested() const noexcept {
  return drainRequested_;
}

bool RuntimeInvocationState::isReady() const noexcept {
  return drainRequested_ && activeCount_ == 0;
}

void RuntimeInvocationState::clear() noexcept {
  activeCount_ = 0;
  drainRequested_ = false;
}

}  // namespace expo::harmony
