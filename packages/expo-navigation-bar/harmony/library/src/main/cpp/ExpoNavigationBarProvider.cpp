#include "ExpoNavigationBarProvider.h"

#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

namespace expo::harmony::navigationbar {
namespace {

constexpr const char *kModuleName = "ExpoNavigationBar";
constexpr const char *kServiceName = "ExpoNavigationBarService";
constexpr const char *kVisibilityEventName = "ExpoNavigationBar.didChange";

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

class ExpoNavigationBarModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.events({kVisibilityEventName});
    module.function(platformFunction("setBackgroundColorAsync", 1));
    module.function(platformFunction("getBackgroundColorAsync", 0));
    module.function(platformFunction("setButtonStyleAsync", 1));
    module.function(platformFunction("getButtonStyleAsync", 0));
    module.function(platformFunction("setVisibilityAsync", 1));
    module.function(platformFunction("getVisibilityAsync", 0));
    module.function(platformFunction("setPositionAsync", 1));
    module.function(platformFunction("getPositionAsync", 0));
    module.onDestroy([](RuntimeContext &context) {
      context.invokePlatformServiceSync(kServiceName, "destroy");
    });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoNavigationBarProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoNavigationBarModule>()};
}
}  // namespace expo::harmony::navigationbar
