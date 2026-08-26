#pragma once
#include <ExpoModulesCore.h>

namespace expo::harmony::appmetrics {
class ExpoAppMetricsProvider final : public ExpoModulesProvider {
public:
  std::vector<std::shared_ptr<ExpoModule>> modules(const std::shared_ptr<RuntimeContext> &context) override;
};
}  // namespace expo::harmony::appmetrics
