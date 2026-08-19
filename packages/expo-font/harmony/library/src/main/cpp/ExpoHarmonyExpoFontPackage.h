#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoFontPackage final : public Package {
public:
  explicit ExpoHarmonyExpoFontPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
