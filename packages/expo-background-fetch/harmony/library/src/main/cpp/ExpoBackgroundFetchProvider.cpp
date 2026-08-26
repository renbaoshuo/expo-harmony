#include "ExpoBackgroundFetchProvider.h"

#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

namespace expo::harmony::backgroundfetch {
namespace {

constexpr auto kServiceName = "ExpoBackgroundFetchService";
constexpr auto kBackgroundFetchModuleName = "ExpoBackgroundFetch";

FunctionDefinition platformFunction(
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
        auto arguments = folly::dynamic::array();
        for (size_t index = 0; index < invocation.argumentCount(); ++index) {
          arguments.push_back(facebook::jsi::dynamicFromValue(
              invocation.runtime(), invocation.argument(index)));
        }
        return invocation.context().invokePlatformService(
            kServiceName, name, std::move(arguments));
      }};
}

class ExpoBackgroundFetchModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kBackgroundFetchModuleName);
    module.function(platformFunction("getStatusAsync", 0, 0));
    module.function(platformFunction("registerTaskAsync", 2, 2));
    module.function(platformFunction("unregisterTaskAsync", 1, 1));

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoBackgroundFetchProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoBackgroundFetchModule>()};
}
}  // namespace expo::harmony::backgroundfetch
