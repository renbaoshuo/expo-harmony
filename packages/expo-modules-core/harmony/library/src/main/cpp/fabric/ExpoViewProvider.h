#pragma once

#include "ExpoViewComponentRegistry.h"
#include "api/ExpoModulesProvider.h"

namespace expo::harmony {

/**
 * Native half of the Expo Modules Provider SPI.
 *
 * Each generated/manual Harmony Expo module Package constructs one provider
 * before RNOH asks packages for ComponentDescriptorProviders. Registration is
 * therefore complete before React's ComponentDescriptorRegistry is frozen.
 */
class ExpoViewProvider {
public:
  static std::string componentName(
      const std::string &moduleName,
      const std::string &viewName,
      bool isDefault) {
    return isDefault
             ? "ViewManagerAdapter_" + moduleName
             : "ViewManagerAdapter_" + moduleName + "_" + viewName;
  }

  ExpoViewProvider(
      const std::string &moduleName,
      const std::vector<std::string> &viewNames) {
    for (size_t index = 0; index < viewNames.size(); ++index) {
      ExpoViewComponentRegistry::registerComponent(componentName(
          moduleName, viewNames[index], index == 0));
    }
  }

  explicit ExpoViewProvider(std::vector<std::string> componentNames) {
    for (auto &name : componentNames) {
      ExpoViewComponentRegistry::registerComponent(std::move(name));
    }
  }
};

}  // namespace expo::harmony

#define EXPO_HARMONY_REGISTER_VIEWS(ModuleName, ...)          \
  namespace {                                                 \
  [[maybe_unused]] const ::expo::harmony::ExpoViewProvider    \
      EXPO_HARMONY_DETAIL_CONCAT(                             \
          kExpoViewProviderRegistration_, __COUNTER__)(       \
          ModuleName, std::vector<std::string>{__VA_ARGS__}); \
  }
