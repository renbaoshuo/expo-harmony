#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace expo::harmony {

using RuntimeEpoch = uint64_t;

inline constexpr RuntimeEpoch kInvalidRuntimeEpoch = 0;

/** Allocates a process-wide, monotonically increasing runtime identity. */
RuntimeEpoch allocateRuntimeEpoch() noexcept;

/** Encodes an epoch for JSON/ArkTS transport without losing integer precision. */
std::string encodeRuntimeEpoch(RuntimeEpoch epoch);

/** Strictly parses the canonical positive-decimal transport representation. */
std::optional<RuntimeEpoch> decodeRuntimeEpoch(
    std::string_view encoded) noexcept;

}  // namespace expo::harmony
