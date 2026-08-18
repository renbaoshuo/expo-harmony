#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoLinkingPackage final : public Package {
public:
  explicit ExpoHarmonyExpoLinkingPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
