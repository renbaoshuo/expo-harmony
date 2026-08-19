#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoSplashScreenPackage final : public Package {
public:
  explicit ExpoHarmonyExpoSplashScreenPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
