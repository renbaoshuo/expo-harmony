#pragma once

#include <optional>

namespace expo::harmony {

enum class SharedObjectBindResult {
  Bound,
  AlreadyBound,
  RuntimeConflict,
};

/** Tracks the runtime binding of one native SharedObject. */
class SharedObjectBindingState final {
public:
  SharedObjectBindResult bind(const void *runtime, long objectId) noexcept {
    if (!runtime || objectId <= 0) {
      return SharedObjectBindResult::RuntimeConflict;
    }
    if (!runtime_ || objectId_ == 0) {
      runtime_ = runtime;
      objectId_ = objectId;
      return SharedObjectBindResult::Bound;
    }
    if (runtime_ == runtime && objectId_ == objectId) {
      return SharedObjectBindResult::AlreadyBound;
    }
    return SharedObjectBindResult::RuntimeConflict;
  }

  bool unbind(const void *runtime, long objectId) noexcept {
    if (runtime_ != runtime || objectId_ != objectId) {
      return false;
    }
    reset();
    return true;
  }

  void reset() noexcept {
    runtime_ = nullptr;
    objectId_ = 0;
  }

  std::optional<long> objectId(const void *runtime) const noexcept {
    if (runtime_ != runtime || objectId_ == 0) {
      return std::nullopt;
    }
    return objectId_;
  }

private:
  const void *runtime_{nullptr};
  long objectId_{0};
};

}  // namespace expo::harmony
