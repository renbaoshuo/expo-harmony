#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoFetchPackage final : public Package {
public:
  explicit ExpoHarmonyExpoFetchPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
