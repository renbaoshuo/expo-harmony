#pragma once

#include <cstdint>
#include <span>
#include <string_view>

namespace expo::harmony {

// These parsers are deliberately independent from JSI so their behavior can
// be exercised by a host-native test as well as by TypeConverter.
void validateAbsoluteUrl(std::string_view value);
void validateUri(std::string_view value);
uint32_t parseCssColor(std::string_view value);
uint32_t packNormalizedColor(std::span<const double> components);

} // namespace expo::harmony
