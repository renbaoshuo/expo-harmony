#pragma once

#include <utility>

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoTaskManagerPackage final : public Package {
public:
  explicit ExpoHarmonyExpoTaskManagerPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
