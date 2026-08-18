#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoFileSystemPackage final : public Package {
public:
  explicit ExpoHarmonyExpoFileSystemPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
