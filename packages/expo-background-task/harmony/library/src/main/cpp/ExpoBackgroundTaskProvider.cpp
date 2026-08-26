#include "ExpoBackgroundTaskProvider.h"

#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

namespace expo::harmony::backgroundtask {
namespace {

constexpr auto kModuleName = "ExpoBackgroundTask";
constexpr auto kServiceName = "ExpoBackgroundTaskService";
constexpr auto kExpirationEventName = "onTasksExpired";

FunctionDefinition platformFunction(std::string name, size_t arity) {
  return FunctionDefinition{
      .name = name,
      .arity = arity,
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

class ExpoBackgroundTaskModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.events({kExpirationEventName});
    module.function(platformFunction("getStatusAsync", 0));
    module.function(platformFunction("registerTaskAsync", 2));
    module.function(platformFunction("unregisterTaskAsync", 1));
    module.function(platformFunction("triggerTaskWorkerForTestingAsync", 0));

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoBackgroundTaskProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoBackgroundTaskModule>()};
}
}  // namespace expo::harmony::backgroundtask
