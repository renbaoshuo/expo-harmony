#pragma once

#include <utility>

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoBackgroundTaskPackage final : public Package {
public:
  explicit ExpoHarmonyExpoBackgroundTaskPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
