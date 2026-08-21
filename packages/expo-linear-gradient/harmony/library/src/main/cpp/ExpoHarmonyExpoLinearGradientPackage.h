#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoLinearGradientPackage final : public Package {
public:
  explicit ExpoHarmonyExpoLinearGradientPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
