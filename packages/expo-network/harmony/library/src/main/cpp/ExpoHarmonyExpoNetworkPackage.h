#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoNetworkPackage final : public Package {
public:
  explicit ExpoHarmonyExpoNetworkPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
