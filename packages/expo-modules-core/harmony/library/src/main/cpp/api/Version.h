#pragma once

#include <cstddef>
#include <string_view>

#ifndef EXPO_MODULES_CORE_VERSION
#error "EXPO_MODULES_CORE_VERSION must be supplied by the package build"
#endif

namespace expo::harmony {

namespace detail {
constexpr int versionPart(std::string_view version, std::size_t expectedPart) {
  std::size_t part = 0;
  int value = 0;
  for (const char character : version) {
    if (character == '.') {
      if (part == expectedPart) {
        return value;
      }
      ++part;
      value = 0;
    } else if (character >= '0' && character <= '9') {
      if (part == expectedPart) {
        value = value * 10 + (character - '0');
      }
    }
  }
  return part == expectedPart ? value : 0;
}
}  // namespace detail

inline constexpr char ExpoModulesCoreVersion[] = EXPO_MODULES_CORE_VERSION;
inline constexpr int ExpoModulesCoreVersionMajor = detail::versionPart(ExpoModulesCoreVersion, 0);
inline constexpr int ExpoModulesCoreVersionMinor = detail::versionPart(ExpoModulesCoreVersion, 1);
inline constexpr int ExpoModulesCoreVersionPatch = detail::versionPart(ExpoModulesCoreVersion, 2);

}  // namespace expo::harmony
