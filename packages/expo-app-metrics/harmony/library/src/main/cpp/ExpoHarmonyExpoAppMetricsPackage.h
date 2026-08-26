#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoAppMetricsPackage final : public Package {
public:
  explicit ExpoHarmonyExpoAppMetricsPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
