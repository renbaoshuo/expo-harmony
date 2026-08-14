#pragma once

#include <mutex>
#include <string>
#include <vector>

#include <react/renderer/componentregistry/ComponentDescriptorProvider.h>

namespace expo::harmony {

class ExpoViewComponentRegistry final {
public:
  static void registerComponent(std::string componentName);
  static bool contains(const std::string &componentName);
  static std::vector<std::string> componentNames();
  static std::vector<facebook::react::ComponentDescriptorProvider>
  descriptorProviders();

private:
  static std::mutex mutex_;
  static std::vector<std::shared_ptr<const std::string>> names_;
};

}  // namespace expo::harmony
