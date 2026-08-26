#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoBatteryPackage final : public Package {
public:
  explicit ExpoHarmonyExpoBatteryPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
