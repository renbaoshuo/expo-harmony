#include "ExpoTaskManagerProvider.h"

#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

namespace expo::harmony::taskmanager {
namespace {

constexpr auto kModuleName = "ExpoTaskManager";
constexpr auto kServiceName = "ExpoTaskManagerService";
constexpr auto kTaskManagerEventName = "TaskManager.executeTask";

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

class ExpoTaskManagerModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.events({kTaskManagerEventName});
    module.constant("EVENT_NAME", [](Invocation &invocation) {
      return facebook::jsi::String::createFromAscii(
          invocation.runtime(), kTaskManagerEventName);
    });
    module.function(platformFunction("isAvailableAsync", 0));
    module.function(platformFunction("notifyTaskFinishedAsync", 2));
    module.function(platformFunction("isTaskRegisteredAsync", 1));
    module.function(platformFunction("getTaskOptionsAsync", 1));
    module.function(platformFunction("getRegisteredTasksAsync", 0));
    module.function(platformFunction("unregisterTaskAsync", 1));
    module.function(platformFunction("unregisterAllTasksAsync", 0));
    module.onStartObserving(
        kTaskManagerEventName,
        [](RuntimeContext &context) {
          context.invokePlatformService(kServiceName, "startObserving");
        });
    module.onStopObserving(
        kTaskManagerEventName,
        [](RuntimeContext &context) {
          context.invokePlatformService(kServiceName, "stopObserving");
        });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoTaskManagerProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoTaskManagerModule>()};
}
}  // namespace expo::harmony::taskmanager
