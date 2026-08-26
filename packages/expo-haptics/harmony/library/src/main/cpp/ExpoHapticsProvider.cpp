#include "ExpoHapticsProvider.h"

#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

namespace expo::harmony::haptics {
namespace {

constexpr auto kModuleName = "ExpoHaptics";
constexpr auto kServiceName = "ExpoHapticsService";
constexpr auto kNotificationMethod = "notificationAsync";
constexpr auto kImpactMethod = "impactAsync";
constexpr auto kSelectionMethod = "selectionAsync";

FunctionDefinition platformFunction(std::string name, size_t arity) {
  return FunctionDefinition{
      .name = name,
      .arity = arity,
      .requiredArity = arity,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [name = std::move(name)](Invocation &invocation) {
        auto arguments = folly::dynamic::array();
        for (size_t index = 0; index < invocation.argumentCount(); ++index) {
          arguments.push_back(facebook::jsi::dynamicFromValue(
              invocation.runtime(), invocation.argument(index)));
        }

        return invocation.context().invokePlatformService(
            kServiceName, name, std::move(arguments));
      }};
}

class ExpoHapticsModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.function(platformFunction(kNotificationMethod, 1));
    module.function(platformFunction(kImpactMethod, 1));
    module.function(platformFunction(kSelectionMethod, 0));

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoHapticsProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoHapticsModule>()};
}
}  // namespace expo::harmony::haptics
