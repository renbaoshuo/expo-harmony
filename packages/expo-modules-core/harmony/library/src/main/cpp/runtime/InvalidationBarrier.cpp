#include "InvalidationBarrier.h"

#include <utility>

namespace expo::harmony {

std::shared_ptr<InvalidationBarrier> InvalidationBarrier::create(
    size_t count,
    std::function<void()> completion) {
  auto barrier = std::shared_ptr<InvalidationBarrier>(
      new InvalidationBarrier(count, std::move(completion)));
  if (count == 0) {
    barrier->complete();
  }
  return barrier;
}

InvalidationBarrier::InvalidationBarrier(
    size_t count,
    std::function<void()> completion)
    : remaining_(count), completion_(std::move(completion)) {}

void InvalidationBarrier::arrive() noexcept {
  auto remaining = remaining_.load(std::memory_order_acquire);
  while (remaining > 0) {
    if (remaining_.compare_exchange_weak(
            remaining,
            remaining - 1,
            std::memory_order_acq_rel,
            std::memory_order_acquire)) {
      if (remaining == 1) {
        complete();
      }
      return;
    }
  }
}

void InvalidationBarrier::complete() noexcept {
  auto completion = std::move(completion_);
  try {
    if (completion) {
      completion();
    }
  } catch (...) {
  }
}

}  // namespace expo::harmony
