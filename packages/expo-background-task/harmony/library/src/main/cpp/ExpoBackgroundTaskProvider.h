#pragma once

#include <ExpoModulesCore.h>

namespace expo::harmony::backgroundtask {
class ExpoBackgroundTaskProvider final : public ExpoModulesProvider {
public:
  std::vector<std::shared_ptr<ExpoModule>> modules(
      const std::shared_ptr<RuntimeContext> &context) override;
};
}  // namespace expo::harmony::backgroundtask
