#pragma once

#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace expo::harmony {

class ExpoModule;
class RuntimeContext;

class ExpoModulesProvider {
public:
  virtual ~ExpoModulesProvider() = default;
  virtual std::vector<std::shared_ptr<ExpoModule>> modules(
      const std::shared_ptr<RuntimeContext> &context) = 0;
};

struct RegisteredExpoModulesProvider final {
  std::string identifier;
  std::shared_ptr<ExpoModulesProvider> provider;
};

class ExpoModulesProviderRegistry final {
public:
  using Factory = std::function<std::shared_ptr<ExpoModulesProvider>()>;

  static ExpoModulesProviderRegistry &shared();
  void registerProvider(std::string identifier, Factory factory);
  std::vector<RegisteredExpoModulesProvider> createProviders() const;
  std::vector<std::string> identifiers() const;

private:
  mutable std::mutex mutex_;
  std::vector<std::pair<std::string, Factory>> factories_;
};

template <typename Provider>
class ExpoModulesProviderRegistration final {
public:
  explicit ExpoModulesProviderRegistration(std::string identifier) {
    ExpoModulesProviderRegistry::shared().registerProvider(
        std::move(identifier),
        [] { return std::make_shared<Provider>(); });
  }
};

}  // namespace expo::harmony

#define EXPO_HARMONY_DETAIL_CONCAT_INNER(Left, Right) Left##Right
#define EXPO_HARMONY_DETAIL_CONCAT(Left, Right) \
  EXPO_HARMONY_DETAIL_CONCAT_INNER(Left, Right)
#define EXPO_HARMONY_REGISTER_PROVIDER(ProviderType, Identifier)                                     \
  namespace {                                                                                        \
  [[maybe_unused]] const ::expo::harmony::ExpoModulesProviderRegistration<                           \
      ProviderType> EXPO_HARMONY_DETAIL_CONCAT(kExpoProviderRegistration_, __COUNTER__)(Identifier); \
  }
