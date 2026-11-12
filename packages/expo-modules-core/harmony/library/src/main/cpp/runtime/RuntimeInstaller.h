/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <memory>

#include <jsi/jsi.h>

namespace expo::harmony {

class RuntimeContext;

class RuntimeInstaller final {
public:
  static std::shared_ptr<RuntimeContext> installedContext(
      facebook::jsi::Runtime &runtime, bool requireAcceptingTasks = true);
  static void uninstall(
      facebook::jsi::Runtime &runtime,
      const RuntimeContext *context);
  static bool install(
      facebook::jsi::Runtime &runtime,
      const std::shared_ptr<RuntimeContext> &context,
      bool workletRuntime);
};

}  // namespace expo::harmony
