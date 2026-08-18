#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoConstantsPackage final : public Package {
public:
  explicit ExpoHarmonyExpoConstantsPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
