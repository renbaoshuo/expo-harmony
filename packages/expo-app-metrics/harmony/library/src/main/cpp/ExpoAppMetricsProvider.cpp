#include "ExpoAppMetricsProvider.h"

#include <cstddef>
#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

namespace expo::harmony::appmetrics {
namespace {

constexpr auto kModuleName = "ExpoAppMetrics";
constexpr auto kServiceName = "ExpoAppMetricsService";

FunctionDefinition asyncPlatformFunction(
    std::string name,
    size_t arity,
    size_t requiredArity) {
  return FunctionDefinition{
      .name = name,
      .arity = arity,
      .requiredArity = requiredArity,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [name = std::move(name)](Invocation &invocation) {
        auto args = folly::dynamic::array();
        for (size_t i = 0; i < invocation.argumentCount(); ++i) {
          args.push_back(facebook::jsi::dynamicFromValue(
              invocation.runtime(), invocation.argument(i)));
        }

        return invocation.context().invokePlatformService(
            kServiceName, name, std::move(args));
      }};
}

FunctionDefinition syncPlatformFunction(
    std::string name,
    size_t arity,
    size_t requiredArity) {
  return FunctionDefinition{
      .name = name,
      .arity = arity,
      .requiredArity = requiredArity,
      .async = false,
      .queue = FunctionQueue::JavaScript,
      .body = [name = std::move(name)](Invocation &invocation) {
        auto args = folly::dynamic::array();
        for (size_t i = 0; i < invocation.argumentCount(); ++i) {
          args.push_back(facebook::jsi::dynamicFromValue(
              invocation.runtime(), invocation.argument(i)));
        }

        return invocation.context().invokePlatformServiceSync(
            kServiceName, name, std::move(args));
      }};
}

class ExpoAppMetricsModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.function(syncPlatformFunction("markFirstRender", 0, 0));
    module.function(syncPlatformFunction("markInteractive", 1, 0));
    module.function(asyncPlatformFunction("getStoredEntries", 0, 0));
    module.function(asyncPlatformFunction("clearStoredEntries", 0, 0));
    module.function(syncPlatformFunction("startSession", 0, 0));
    module.function(syncPlatformFunction("stopSession", 1, 1));
    module.function(asyncPlatformFunction("addCustomMetricToSession", 2, 2));

    // These APIs exist on one of the upstream native platforms even though the
    // current public TypeScript facade only exposes the common subset.
    module.function(asyncPlatformFunction("takeMemoryUsageSnapshotAsync", 1, 0));
    module.function(asyncPlatformFunction("getAppStartupTimesAsync", 0, 0));
    module.function(asyncPlatformFunction("getMemoryUsageSnapshotAsync", 0, 0));
    module.function(asyncPlatformFunction("getFrameRateMetricsAsync", 0, 0));

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoAppMetricsProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoAppMetricsModule>()};
}

}  // namespace expo::harmony::appmetrics
