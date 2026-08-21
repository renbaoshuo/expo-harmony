#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoCameraPackage final : public Package {
public:
  explicit ExpoHarmonyExpoCameraPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
