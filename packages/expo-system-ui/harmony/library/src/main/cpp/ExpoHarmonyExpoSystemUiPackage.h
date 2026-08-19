#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoSystemUiPackage final : public Package {
public:
  explicit ExpoHarmonyExpoSystemUiPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
