#pragma once

#include <cstdint>
#include <mutex>

namespace expo::harmony::linking {

class LinkingRegistry final {
public:
  explicit LinkingRegistry(uint64_t initialRevision)
      : lastSeenRevision_(initialRevision) {}

  bool receive(uint64_t revision) {
    std::scoped_lock lock(mutex_);
    if (destroyed_ || revision <= lastSeenRevision_) {
      return false;
    }
    lastSeenRevision_ = revision;
    return true;
  }

  uint64_t lastSeenRevision() const {
    std::scoped_lock lock(mutex_);
    return lastSeenRevision_;
  }

  void startObserving() {
    std::scoped_lock lock(mutex_);
    if (!destroyed_) {
      observing_ = true;
    }
  }

  void stopObserving() {
    std::scoped_lock lock(mutex_);
    observing_ = false;
  }

  bool isObserving() const {
    std::scoped_lock lock(mutex_);
    return !destroyed_ && observing_;
  }

  void destroy() {
    std::scoped_lock lock(mutex_);
    observing_ = false;
    destroyed_ = true;
  }

private:
  mutable std::mutex mutex_;
  uint64_t lastSeenRevision_{0};
  bool observing_{false};
  bool destroyed_{false};
};

}  // namespace expo::harmony::linking
