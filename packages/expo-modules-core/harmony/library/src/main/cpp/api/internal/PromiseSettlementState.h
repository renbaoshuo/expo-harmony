#pragma once

#include <atomic>

namespace expo::harmony {

class PromiseSettlementState final {
public:
  bool trySettle() noexcept {
    return !settled_.exchange(true, std::memory_order_acq_rel);
  }

  bool isSettled() const noexcept {
    return settled_.load(std::memory_order_acquire);
  }

  void markSettled() noexcept {
    settled_.store(true, std::memory_order_release);
  }

private:
  std::atomic_bool settled_{false};
};

}  // namespace expo::harmony
