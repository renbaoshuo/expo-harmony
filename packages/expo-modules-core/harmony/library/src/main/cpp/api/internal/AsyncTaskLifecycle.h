#pragma once

#include <atomic>
#include <functional>
#include <memory>
#include <utility>

namespace expo::harmony {

// One-shot teardown action shared by asynchronous failure paths.
class OneShotReleaseState final {
public:
  explicit OneShotReleaseState(std::function<void()> release)
      : release_(std::move(release)) {}

  void release() noexcept {
    if (released_.exchange(true, std::memory_order_acq_rel)) {
      return;
    }
    try {
      if (release_) {
        release_();
      }
    } catch (...) {
    }
  }

  bool isReleased() const noexcept {
    return released_.load(std::memory_order_acquire);
  }

private:
  std::atomic_bool released_{false};
  std::function<void()> release_;
};

// Converts discarded executor callbacks into one-shot releases without touching JSI off-thread.
class ScheduledCallbackGuard final {
public:
  explicit ScheduledCallbackGuard(
      std::shared_ptr<OneShotReleaseState> droppedRelease)
      : droppedRelease_(std::move(droppedRelease)) {}

  ~ScheduledCallbackGuard() noexcept {
    if (!delivered_.load(std::memory_order_acquire) && droppedRelease_) {
      droppedRelease_->release();
    }
  }

  void markDelivered() noexcept {
    delivered_.store(true, std::memory_order_release);
  }

private:
  std::atomic_bool delivered_{false};
  std::shared_ptr<OneShotReleaseState> droppedRelease_;
};

}  // namespace expo::harmony
