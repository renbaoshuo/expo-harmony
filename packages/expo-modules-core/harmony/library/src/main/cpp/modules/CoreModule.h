#pragma once

#include "api/ExpoModule.h"

#include <memory>

namespace expo::harmony {

class RuntimeContext;

class CoreModule final : public ExpoModule {
 public:
  explicit CoreModule(std::shared_ptr<RuntimeContext> context);
  ModuleDefinition definition() override;

 private:
  std::weak_ptr<RuntimeContext> context_;
};

class NativeModulesProxyModule final : public ExpoModule {
 public:
  explicit NativeModulesProxyModule(std::shared_ptr<RuntimeContext> context);
  ModuleDefinition definition() override;

 private:
  std::weak_ptr<RuntimeContext> context_;
};

} // namespace expo::harmony
