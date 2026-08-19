#pragma once
#include <ExpoModulesCore.h>

namespace expo::harmony::splashscreen {
class ExpoSplashScreenProvider final : public ExpoModulesProvider {
public:
  std::vector<std::shared_ptr<ExpoModule>> modules(
      const std::shared_ptr<RuntimeContext> &ctx) override;
};
}  // namespace expo::harmony::splashscreen
