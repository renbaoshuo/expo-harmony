#pragma once

#include "api/ModuleDefinition.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace expo::harmony {

class ExpoModule;
class RuntimeContext;

class ModuleRegistry final {
 public:
  explicit ModuleRegistry(std::shared_ptr<RuntimeContext> context);
  ~ModuleRegistry();

  void initialize();
  void notifyCreated();
  const ModuleDefinition* find(const std::string& name) const;
  const ViewDefinition* findView(const std::string& componentName) const;
  const std::vector<std::string>& names() const noexcept;
  void dispatchLifecycle(
      const std::string& eventName,
      const folly::dynamic& payload = nullptr);
  void destroy() noexcept;

 private:
  void registerModule(std::shared_ptr<ExpoModule> module);

  std::weak_ptr<RuntimeContext> context_;
  bool initialized_{false};
  bool created_{false};
  bool destroyed_{false};
  std::vector<std::shared_ptr<ExpoModule>> modules_;
  std::vector<std::string> names_;
  std::vector<std::string> createdNames_;
  std::unordered_map<std::string, std::unique_ptr<ModuleDefinition>> definitions_;
  std::unordered_map<std::string, const ViewDefinition*> views_;
};

} // namespace expo::harmony
