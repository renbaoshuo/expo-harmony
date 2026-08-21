#include "ExpoLinearGradientProvider.h"

#include <memory>
#include <string>
#include <vector>

namespace expo::harmony::lineargradient {
namespace {

constexpr const char *kComponentName = "ViewManagerAdapter_ExpoLinearGradient";

[[maybe_unused]] const ExpoViewProvider kExpoLinearGradientViewProvider(
    std::vector<std::string>{kComponentName});

class ExpoLinearGradientModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoLinearGradient");
    ViewDefinitionBuilder view("ExpoLinearGradientView");

    view.componentName(kComponentName)
        .prop("colors")
        .prop("locations")
        .prop("startPoint")
        .prop("endPoint")
        .prop("borderRadii");

    module.view(std::move(view).build());

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoLinearGradientProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoLinearGradientModule>()};
}
}  // namespace expo::harmony::lineargradient
