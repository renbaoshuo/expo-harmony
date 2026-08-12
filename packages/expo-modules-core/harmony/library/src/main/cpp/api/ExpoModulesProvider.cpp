#include "ExpoModulesProvider.h"

#include <algorithm>
#include <unordered_set>

#include "errors/CodedError.h"

namespace expo::harmony {

ExpoModulesProviderRegistry &ExpoModulesProviderRegistry::shared() {
  static ExpoModulesProviderRegistry registry;
  return registry;
}

void ExpoModulesProviderRegistry::registerProvider(
    std::string identifier,
    Factory factory) {
  std::scoped_lock lock(mutex_);
  // Static registration can run while a HAR is being loaded. Logical
  // validation must not throw through a global constructor; defer it to
  // createProviders(), where RuntimeInstaller can translate CodedError.
  factories_.emplace_back(std::move(identifier), std::move(factory));
}

std::vector<RegisteredExpoModulesProvider>
ExpoModulesProviderRegistry::createProviders() const {
  std::vector<std::pair<std::string, Factory>> registrations;
  {
    std::scoped_lock lock(mutex_);
    registrations.reserve(factories_.size());
    for (const auto &[identifier, factory] : factories_) {
      registrations.emplace_back(identifier, factory);
    }
  }
  std::unordered_set<std::string> identifiers;
  std::vector<RegisteredExpoModulesProvider> providers;
  providers.reserve(registrations.size());
  for (const auto &[identifier, factory] : registrations) {
    if (identifier.empty() || !factory) {
      throw CodedError(
          "ERR_INVALID_PROVIDER", "Expo module provider registration is invalid.");
    }
    if (!identifiers.insert(identifier).second) {
      throw CodedError(
          "ERR_DUPLICATE_PROVIDER",
          "Expo module provider '" + identifier + "' was registered twice.");
    }
    auto provider = factory();
    if (!provider) {
      throw CodedError(
          "ERR_INVALID_PROVIDER", "Expo module provider factory returned null.");
    }
    providers.push_back(RegisteredExpoModulesProvider{
        .identifier = identifier,
        .provider = std::move(provider),
    });
  }
  return providers;
}

std::vector<std::string> ExpoModulesProviderRegistry::identifiers() const {
  std::scoped_lock lock(mutex_);
  std::vector<std::string> result;
  result.reserve(factories_.size());
  for (const auto &[identifier, factory] : factories_) {
    result.push_back(identifier);
  }
  return result;
}

}  // namespace expo::harmony
