#include "ExpoSystemUIProvider.h"

#include <string>

#include <jsi/JSIDynamic.h>

namespace expo::harmony::systemui {
namespace {

FunctionDefinition platformFunction(std::string name, size_t arity) {
  return FunctionDefinition{
      .name = name,
      .arity = arity,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [name = std::move(name)](Invocation &invocation) {
        auto args = folly::dynamic::array();

        for (size_t index = 0; index < invocation.argumentCount(); ++index) {
          args.push_back(facebook::jsi::dynamicFromValue(
              invocation.runtime(), invocation.argument(index)));
        }

        return invocation.context().invokePlatformService(
            "ExpoSystemUIService", name, std::move(args));
      }};
}

class ExpoSystemUIModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoSystemUI");
    module.function(platformFunction("setBackgroundColorAsync", 1));
    module.function(platformFunction("getBackgroundColorAsync", 0));
    module.onDestroy([](RuntimeContext &context) {
      context.invokePlatformServiceSync("ExpoSystemUIService", "destroy");
    });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoSystemUIProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoSystemUIModule>()};
}
}  // namespace expo::harmony::systemui
