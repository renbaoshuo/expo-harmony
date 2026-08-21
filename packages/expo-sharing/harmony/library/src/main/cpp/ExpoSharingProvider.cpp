#include "ExpoSharingProvider.h"

#include <string>

#include <jsi/JSIDynamic.h>

namespace expo::harmony::sharing {
namespace {

// Keep this value in sync with SERVICE_NAME in ExpoSharingPackage.ets.
constexpr auto kServiceName = "ExpoSharingService";

FunctionDefinition platformFunction(std::string name, size_t arity) {
  return FunctionDefinition{
      .name = name,
      .arity = arity,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [name = std::move(name)](Invocation &call) {
        auto args = folly::dynamic::array();
        for (size_t i = 0; i < call.argumentCount(); ++i) {
          args.push_back(facebook::jsi::dynamicFromValue(
              call.runtime(), call.argument(i)));
        }

        return call.context().invokePlatformService(
            kServiceName, name, std::move(args));
      }};
}

FunctionDefinition syncPlatformFunction(std::string name, size_t arity) {
  return FunctionDefinition{
      .name = name,
      .arity = arity,
      .async = false,
      .queue = FunctionQueue::JavaScript,
      .body = [name = std::move(name)](Invocation &call) {
        auto args = folly::dynamic::array();
        for (size_t i = 0; i < call.argumentCount(); ++i) {
          args.push_back(facebook::jsi::dynamicFromValue(
              call.runtime(), call.argument(i)));
        }

        return call.context().invokePlatformServiceSync(
            kServiceName, name, std::move(args));
      }};
}

class ExpoSharingModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoSharing");

    module.events({"onSharedPayloadsChanged"});

    module.function(platformFunction("shareAsync", 2));
    module.function(platformFunction("isAvailableAsync", 0));
    module.function(syncPlatformFunction("getSharedPayloads", 0));
    module.function(platformFunction("getResolvedSharedPayloadsAsync", 0));
    module.function(syncPlatformFunction("clearSharedPayloads", 0));

    module.onDestroy([](RuntimeContext &context) {
      context.invokePlatformServiceSync(kServiceName, "destroy");
    });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoSharingProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoSharingModule>()};
}
}  // namespace expo::harmony::sharing
