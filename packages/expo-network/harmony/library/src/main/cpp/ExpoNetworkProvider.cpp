#include "ExpoNetworkProvider.h"

#include <string>
#include <utility>

namespace expo::harmony::network {
namespace {

constexpr auto kModuleName = "ExpoNetwork";
constexpr auto kServiceName = "ExpoNetworkService";
constexpr auto kNetworkStateEventName = "onNetworkStateChanged";

FunctionDefinition platformFunction(std::string name) {
  return FunctionDefinition{
      .name = name,
      .arity = 0,
      .requiredArity = 0,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [name = std::move(name)](Invocation &invocation) {
        return invocation.context().invokePlatformService(
            kServiceName, name, folly::dynamic::array());
      }};
}

class ExpoNetworkModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.events({kNetworkStateEventName});
    module.function(platformFunction("getNetworkStateAsync"));
    module.function(platformFunction("getIpAddressAsync"));
    module.function(platformFunction("isAirplaneModeEnabledAsync"));
    module.onStartObserving(
        kNetworkStateEventName,
        [](RuntimeContext &context) {
          context.invokePlatformService(kServiceName, "startObserving");
        });
    module.onStopObserving(
        kNetworkStateEventName,
        [](RuntimeContext &context) {
          context.invokePlatformService(kServiceName, "stopObserving");
        });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoNetworkProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoNetworkModule>()};
}
}  // namespace expo::harmony::network
