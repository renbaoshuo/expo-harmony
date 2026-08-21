#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoCryptoPackage final : public Package {
public:
  explicit ExpoHarmonyExpoCryptoPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
