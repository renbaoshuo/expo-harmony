/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <memory>
#include <string>
#include <vector>

#include <jsi/jsi.h>

namespace expo::harmony {

class RuntimeContext;
struct ClassDefinition;
struct ModuleDefinition;

class ModulesHostObject final : public facebook::jsi::HostObject {
public:
  explicit ModulesHostObject(std::shared_ptr<RuntimeContext> context);

  facebook::jsi::Value get(
      facebook::jsi::Runtime &runtime,
      const facebook::jsi::PropNameID &name) override;
  void set(
      facebook::jsi::Runtime &runtime,
      const facebook::jsi::PropNameID &name,
      const facebook::jsi::Value &value) override;
  std::vector<facebook::jsi::PropNameID> getPropertyNames(
      facebook::jsi::Runtime &runtime) override;

private:
  facebook::jsi::Function getOrCreateClass(
      facebook::jsi::Runtime &runtime,
      const ModuleDefinition &module,
      const ClassDefinition &spec);

  facebook::jsi::Object createModule(
      facebook::jsi::Runtime &runtime,
      const ModuleDefinition &definition);

  std::shared_ptr<RuntimeContext> context_;
};

}  // namespace expo::harmony
