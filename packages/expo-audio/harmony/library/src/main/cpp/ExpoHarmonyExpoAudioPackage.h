#pragma once

#include <RNOH/Package.h>

namespace rnoh {
class ExpoHarmonyExpoAudioPackage final : public Package {
public:
  explicit ExpoHarmonyExpoAudioPackage(Package::Context context)
      : Package(std::move(context)) {}
};
}  // namespace rnoh
