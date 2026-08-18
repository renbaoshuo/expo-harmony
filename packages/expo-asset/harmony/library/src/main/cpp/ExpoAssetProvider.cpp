#include "ExpoAssetProvider.h"

namespace expo::harmony::asset {
namespace {
class ExpoAssetModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoAsset");
    module.function(FunctionDefinition{
        .name = "downloadAsync", .arity = 3, .requiredArity = 3, .async = true, .queue = FunctionQueue::JavaScript, .body = [](Invocation &invocation) {
          auto arguments = folly::dynamic::array();
          arguments.push_back(facebook::jsi::dynamicFromValue(invocation.runtime(), invocation.argument(0)));
          arguments.push_back(facebook::jsi::dynamicFromValue(invocation.runtime(), invocation.argument(1)));
          arguments.push_back(facebook::jsi::dynamicFromValue(invocation.runtime(), invocation.argument(2)));
          return invocation.context().invokePlatformService("ExpoAssetService", "downloadAsync", std::move(arguments));
        }});
    module.onDestroy([](RuntimeContext &context) {
      context.invokePlatformService("ExpoAssetService", "destroy");
    });
    return std::move(module).build();
  }
};
}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoAssetProvider::modules(const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoAssetModule>()};
}
}  // namespace expo::harmony::asset
