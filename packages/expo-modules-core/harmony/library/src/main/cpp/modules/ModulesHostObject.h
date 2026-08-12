#pragma once

#include <jsi/jsi.h>

#include <memory>
#include <string>
#include <vector>

namespace expo::harmony {

class RuntimeContext;
struct ModuleDefinition;

class ModulesHostObject final : public facebook::jsi::HostObject {
 public:
  explicit ModulesHostObject(std::shared_ptr<RuntimeContext> context);

  facebook::jsi::Value get(
      facebook::jsi::Runtime& runtime,
      const facebook::jsi::PropNameID& name) override;
  void set(
      facebook::jsi::Runtime& runtime,
      const facebook::jsi::PropNameID& name,
      const facebook::jsi::Value& value) override;
  std::vector<facebook::jsi::PropNameID> getPropertyNames(
      facebook::jsi::Runtime& runtime) override;

 private:
  facebook::jsi::Object createModule(
      facebook::jsi::Runtime& runtime,
      const ModuleDefinition& definition);

  std::shared_ptr<RuntimeContext> context_;
};

} // namespace expo::harmony
