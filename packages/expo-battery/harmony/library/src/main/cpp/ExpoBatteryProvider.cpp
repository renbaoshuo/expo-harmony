#include "ExpoBatteryProvider.h"

#include <string>
#include <utility>

namespace expo::harmony::battery {
namespace {

constexpr auto kModuleName = "ExpoBattery";
constexpr auto kServiceName = "ExpoBatteryService";
constexpr auto kGetBatteryLevelMethod = "getBatteryLevelAsync";
constexpr auto kGetBatteryStateMethod = "getBatteryStateAsync";
constexpr auto kGetLowPowerModeMethod = "isLowPowerModeEnabledAsync";
constexpr auto kStartObservingMethod = "startObserving";
constexpr auto kStopObservingMethod = "stopObserving";
constexpr auto kBatteryLevelEventName = "Expo.batteryLevelDidChange";
constexpr auto kBatteryStateEventName = "Expo.batteryStateDidChange";
constexpr auto kPowerModeEventName = "Expo.powerModeDidChange";

FunctionDefinition platformFunction(std::string method) {
  return FunctionDefinition{
      .name = method,
      .arity = 0,
      .requiredArity = 0,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [method = std::move(method)](Invocation &call) {
        return call.context().invokePlatformService(
            kServiceName, method, folly::dynamic::array());
      }};
}

class ExpoBatteryModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.constant<bool>("isSupported", []() { return true; });
    module.events({
        kBatteryLevelEventName,
        kBatteryStateEventName,
        kPowerModeEventName,
    });

    module.function(platformFunction(kGetBatteryLevelMethod));
    module.function(platformFunction(kGetBatteryStateMethod));
    module.function(platformFunction(kGetLowPowerModeMethod));

    module.onStartObserving(
        [](RuntimeContext &context, const std::string &eventName) {
          context.invokePlatformService(
              kServiceName,
              kStartObservingMethod,
              folly::dynamic::array(eventName));
        });

    module.onStopObserving(
        [](RuntimeContext &context, const std::string &eventName) {
          context.invokePlatformService(
              kServiceName,
              kStopObservingMethod,
              folly::dynamic::array(eventName));
        });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoBatteryProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoBatteryModule>()};
}
}  // namespace expo::harmony::battery
