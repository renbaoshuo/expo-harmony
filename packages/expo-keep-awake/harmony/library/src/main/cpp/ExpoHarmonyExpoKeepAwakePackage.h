#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoKeepAwakePackage final : public Package {
public:
  explicit ExpoHarmonyExpoKeepAwakePackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
