#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoBlurPackage final : public Package {
public:
  explicit ExpoHarmonyExpoBlurPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
