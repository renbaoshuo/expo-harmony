#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace expo::harmony::filesystem::detail {

// JavaScript numbers above this value no longer represent every integer.
inline constexpr double kMaxSafeInteger = 9007199254740991.0;

inline bool isValidFileHandleInteger(double value) {
  return std::isfinite(value) && value >= 0.0 && value <= kMaxSafeInteger && std::floor(value) == value;
}

inline uint64_t fileHandleInteger(double value) {
  return static_cast<uint64_t>(value);
}

inline size_t readAllocationSize(
    uint64_t requested,
    uint64_t offset,
    uintmax_t fileSize) {
  if (offset >= fileSize || requested == 0) {
    return 0;
  }

  const auto remaining = fileSize - offset;
  const auto allocation = std::min<uintmax_t>({
      requested,
      remaining,
      static_cast<uintmax_t>(std::numeric_limits<int32_t>::max()),
  });
  return static_cast<size_t>(allocation);
}

}  // namespace expo::harmony::filesystem::detail
