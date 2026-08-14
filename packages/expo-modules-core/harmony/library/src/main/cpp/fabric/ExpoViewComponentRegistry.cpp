#include "ExpoViewComponentRegistry.h"

#include <algorithm>

#include <common/fabric/ExpoViewComponentDescriptor.h>

namespace react = facebook::react;

namespace expo::harmony {

std::mutex ExpoViewComponentRegistry::mutex_;
std::vector<std::shared_ptr<const std::string>> ExpoViewComponentRegistry::names_;

void ExpoViewComponentRegistry::registerComponent(std::string componentName) {
  std::scoped_lock lock(mutex_);
  auto duplicate = std::find_if(
      names_.begin(), names_.end(), [&](const auto &value) {
        return *value == componentName;
      });
  if (duplicate == names_.end()) {
    names_.push_back(std::make_shared<const std::string>(std::move(componentName)));
  }
}

bool ExpoViewComponentRegistry::contains(const std::string &componentName) {
  std::scoped_lock lock(mutex_);
  return std::any_of(names_.begin(), names_.end(), [&](const auto &value) {
    return *value == componentName;
  });
}

std::vector<std::string> ExpoViewComponentRegistry::componentNames() {
  std::scoped_lock lock(mutex_);
  std::vector<std::string> result;
  result.reserve(names_.size());
  for (const auto &name : names_) {
    result.push_back(*name);
  }
  return result;
}

std::vector<react::ComponentDescriptorProvider>
ExpoViewComponentRegistry::descriptorProviders() {
  std::scoped_lock lock(mutex_);
  std::vector<react::ComponentDescriptorProvider> result;
  result.reserve(names_.size());
  for (const auto &flavor : names_) {
    result.push_back(react::ComponentDescriptorProvider{
        reinterpret_cast<react::ComponentHandle>(flavor->c_str()),
        react::ComponentName{flavor->c_str()},
        flavor,
        &react::concreteComponentDescriptorConstructor<expo::ExpoViewComponentDescriptor>});
  }
  return result;
}

}  // namespace expo::harmony
