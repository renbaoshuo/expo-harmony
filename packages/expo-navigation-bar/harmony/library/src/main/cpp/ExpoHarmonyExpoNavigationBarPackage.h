#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoNavigationBarPackage final : public Package {
public:
  explicit ExpoHarmonyExpoNavigationBarPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
