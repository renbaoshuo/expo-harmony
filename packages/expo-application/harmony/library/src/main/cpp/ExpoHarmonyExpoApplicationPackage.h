#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoApplicationPackage final : public Package {
public:
  explicit ExpoHarmonyExpoApplicationPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
