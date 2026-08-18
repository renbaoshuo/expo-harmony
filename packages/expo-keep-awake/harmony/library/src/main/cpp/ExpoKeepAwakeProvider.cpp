#include "ExpoKeepAwakeProvider.h"

#include <jsi/JSIDynamic.h>

namespace expo::harmony::keepawake {
namespace {

constexpr const char *kServiceName = "ExpoKeepAwakeService";

facebook::jsi::Value invoke(
    Invocation &invocation,
    std::string method,
    folly::dynamic arguments = folly::dynamic::array()) {
  return invocation.context().invokePlatformService(
      kServiceName, std::move(method), std::move(arguments));
}

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

        return invoke(invocation, name, std::move(arguments));
      }};
}

class ExpoKeepAwakeModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoKeepAwake");

    module.function(platformFunction("activate", 1));
    module.function(platformFunction("deactivate", 1));
    module.function(platformFunction("isActivated", 0));

    module.function(FunctionDefinition{
        .name = "isAvailableAsync",
        .arity = 0,
        .async = true,
        .queue = FunctionQueue::JavaScript,
        .body = [](Invocation &invocation) {
          return invoke(invocation, "isAvailable");
        }});

    module.onForeground([](RuntimeContext &context) {
      context.invokePlatformService(kServiceName, "foreground");
    });
    module.onBackground([](RuntimeContext &context) {
      context.invokePlatformService(kServiceName, "background");
    });
    module.onDestroy([](RuntimeContext &context) {
      context.invokePlatformService(kServiceName, "destroy");
    });
    module.onActivityDestroy([](RuntimeContext &context) {
      context.invokePlatformService(kServiceName, "destroy");
    });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoKeepAwakeProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoKeepAwakeModule>()};
}
}  // namespace expo::harmony::keepawake
