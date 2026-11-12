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

class WorkletRuntimeInstaller final {
public:
  static void install(
      facebook::jsi::Runtime &mainRuntime,
      const std::shared_ptr<RuntimeContext> &mainContext,
      const facebook::jsi::Value &runtimeHolder);
};

}  // namespace expo::harmony
