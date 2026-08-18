#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoAssetPackage final : public Package {
public:
  explicit ExpoHarmonyExpoAssetPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
