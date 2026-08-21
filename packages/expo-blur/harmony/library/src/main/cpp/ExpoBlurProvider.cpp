#include "ExpoBlurProvider.h"

#include <memory>
#include <string>
#include <vector>

namespace expo::harmony::blur {
namespace {

constexpr const char *kComponentName = "ViewManagerAdapter_ExpoBlur_ExpoBlurView";

[[maybe_unused]] const ExpoViewProvider kViewProvider(
    std::vector<std::string>{kComponentName});

class ExpoBlurModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoBlur");
    ViewDefinitionBuilder view("ExpoBlurView");
    view.componentName(kComponentName)
        .prototypeName("ExpoBlur_ExpoBlurView")
        .prop("intensity")
        .prop("tint");

    // The shared JavaScript view forwards these Android-only props on every
    // platform. Accept them for cross-platform prop compatibility.
    view.prop("blurTargetId")
        .prop("blurReductionFactor")
        .prop("blurMethod");

    module.view(std::move(view).build());

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoBlurProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoBlurModule>()};
}
}  // namespace expo::harmony::blur
