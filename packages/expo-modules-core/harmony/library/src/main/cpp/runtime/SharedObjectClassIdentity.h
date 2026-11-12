/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <string>
#include <vector>

namespace expo::harmony {

/** One Expo class in a canonical SharedObject's derived-to-base lineage. */
struct SharedObjectClassIdentity final {
  std::string moduleName;
  std::string className;

  bool operator==(const SharedObjectClassIdentity &) const = default;
};

using SharedObjectClassLineage = std::vector<SharedObjectClassIdentity>;

inline bool sharedObjectClassIsAssignableTo(
    const SharedObjectClassLineage &lineage,
    const std::string &moduleName,
    const std::string &className) noexcept {
  for (const auto &identity : lineage) {
    if (identity.moduleName == moduleName && identity.className == className) {
      return true;
    }
  }
  return false;
}

}  // namespace expo::harmony
