#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoSharingPackage final : public Package {
public:
  explicit ExpoHarmonyExpoSharingPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
