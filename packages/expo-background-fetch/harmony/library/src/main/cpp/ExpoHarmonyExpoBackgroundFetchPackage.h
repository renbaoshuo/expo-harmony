#pragma once

#include <utility>

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoBackgroundFetchPackage final : public Package {
public:
  explicit ExpoHarmonyExpoBackgroundFetchPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
