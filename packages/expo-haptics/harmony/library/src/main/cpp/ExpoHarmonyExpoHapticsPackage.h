#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoHapticsPackage final : public Package {
public:
  explicit ExpoHarmonyExpoHapticsPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
