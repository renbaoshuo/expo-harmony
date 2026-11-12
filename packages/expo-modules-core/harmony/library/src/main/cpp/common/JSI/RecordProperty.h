/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include "JSIUtils.h"

namespace expo::common {

// Preserve every record key as an own data property, including __proto__ and
// embedded NUL characters. Assignment can invoke inherited prototype setters.
inline void defineRecordProperty(
    facebook::jsi::Runtime &runtime,
    facebook::jsi::Object &object,
    const facebook::jsi::String &name,
    facebook::jsi::Value value) {
  facebook::jsi::Object descriptor(runtime);
  descriptor.setProperty(runtime, "value", std::move(value));
  descriptor.setProperty(runtime, "writable", true);
  descriptor.setProperty(runtime, "enumerable", true);
  descriptor.setProperty(runtime, "configurable", true);

  defineProperty(runtime, &object, name, std::move(descriptor));
}

}  // namespace expo::common
