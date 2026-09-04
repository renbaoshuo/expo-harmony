#include "RuntimeIdentity.h"

#include <atomic>
#include <charconv>
#include <exception>
#include <limits>

namespace expo::harmony {

namespace {

std::atomic<RuntimeEpoch> nextRuntimeEpoch{1};

}  // namespace

RuntimeEpoch allocateRuntimeEpoch() noexcept {
  auto epoch = nextRuntimeEpoch.load(std::memory_order_relaxed);
  while (true) {
    if (epoch == kInvalidRuntimeEpoch || epoch == std::numeric_limits<RuntimeEpoch>::max()) {
      // Fail closed rather than reusing an epoch.
      std::terminate();
    }
    if (nextRuntimeEpoch.compare_exchange_weak(
            epoch,
            epoch + 1,
            std::memory_order_relaxed,
            std::memory_order_relaxed)) {
      return epoch;
    }
  }
}

std::string encodeRuntimeEpoch(RuntimeEpoch epoch) {
  if (epoch == kInvalidRuntimeEpoch) {
    return {};
  }
  return std::to_string(epoch);
}

std::optional<RuntimeEpoch> decodeRuntimeEpoch(
    std::string_view encoded) noexcept {
  if (encoded.empty() || encoded.front() < '1' || encoded.front() > '9') {
    return std::nullopt;
  }
  RuntimeEpoch epoch = kInvalidRuntimeEpoch;
  const auto [end, error] = std::from_chars(
      encoded.data(), encoded.data() + encoded.size(), epoch);
  if (error != std::errc{} || end != encoded.data() + encoded.size() || epoch == kInvalidRuntimeEpoch) {
    return std::nullopt;
  }
  return epoch;
}

}  // namespace expo::harmony
