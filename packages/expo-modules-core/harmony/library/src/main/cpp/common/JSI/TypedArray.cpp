/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// Copyright 2022-present 650 Industries. All rights reserved.

#include <unordered_map>
#include <cmath>
#include <limits>
#include "TypedArray.h"

namespace expo {

std::unordered_map<std::string, TypedArrayKind> nameToKindMap = {
    {"Int8Array", TypedArrayKind::Int8Array},
    {"Int16Array", TypedArrayKind::Int16Array},
    {"Int32Array", TypedArrayKind::Int32Array},
    {"Uint8Array", TypedArrayKind::Uint8Array},
    {"Uint8ClampedArray", TypedArrayKind::Uint8ClampedArray},
    {"Uint16Array", TypedArrayKind::Uint16Array},
    {"Uint32Array", TypedArrayKind::Uint32Array},
    {"Float32Array", TypedArrayKind::Float32Array},
    {"Float64Array", TypedArrayKind::Float64Array},
    {"BigInt64Array", TypedArrayKind::BigInt64Array},
    {"BigUint64Array", TypedArrayKind::BigUint64Array},
};

TypedArrayKind getTypedArrayKindForName(const std::string &name) {
  return nameToKindMap.at(name);
}

namespace {
size_t checkedByteCount(const jsi::Value &value) {
  if (!value.isNumber()) throw std::runtime_error("TypedArray byte range must be numeric.");

  const auto count = value.getNumber();
  if (!std::isfinite(count) || count < 0 || std::trunc(count) != count ||
      count > 9007199254740991.0 || count > static_cast<double>(std::numeric_limits<size_t>::max())) {
    throw std::runtime_error("TypedArray byte range must be a non-negative safe integer.");
  }

  return static_cast<size_t>(count);
}
} // namespace

TypedArray::TypedArray(jsi::Runtime &runtime, const jsi::Object &obj)
    : jsi::Object(jsi::Value(runtime, obj).asObject(runtime)) {}

TypedArrayKind TypedArray::getKind(jsi::Runtime &runtime) const {
  auto constructorName = this->getPropertyAsObject(runtime, "constructor")
                             .getProperty(runtime, "name")
                             .asString(runtime)
                             .utf8(runtime);
  return getTypedArrayKindForName(constructorName);
};

size_t TypedArray::byteOffset(jsi::Runtime &runtime) const {
  return checkedByteCount(getProperty(runtime, "byteOffset"));
}

size_t TypedArray::byteLength(jsi::Runtime &runtime) const {
  return checkedByteCount(getProperty(runtime, "byteLength"));
}

jsi::ArrayBuffer TypedArray::getBuffer(jsi::Runtime &runtime) const {
  auto buffer = getProperty(runtime, "buffer");
  if (buffer.isObject() && buffer.asObject(runtime).isArrayBuffer(runtime)) {
    return buffer.asObject(runtime).getArrayBuffer(runtime);
  } else {
    throw std::runtime_error("no ArrayBuffer attached");
  }
}

void* TypedArray::getRawPointer(jsi::Runtime &runtime) const {
  auto buffer = getBuffer(runtime);
  const auto offset = byteOffset(runtime);
  const auto length = byteLength(runtime);

  if (offset > buffer.size(runtime) || length > buffer.size(runtime) - offset) {
    throw std::runtime_error("TypedArray view exceeds its backing buffer.");
  }

  auto data = buffer.data(runtime);
  return offset == 0 ? data : data + offset;
}

jsi::ArrayBuffer TypedArray::getViewedBufferSlice(jsi::Runtime &runtime) const {
  auto buffer = getBuffer(runtime);
  const auto offset = byteOffset(runtime);
  const auto length = byteLength(runtime);

  if (offset > buffer.size(runtime) || length > buffer.size(runtime) - offset) {
    throw std::runtime_error("TypedArray view exceeds its backing buffer.");
  }
  if (offset == 0 && length == buffer.size(runtime)) {
    return buffer;
  }

  return buffer.getPropertyAsFunction(runtime, "slice")
      .callWithThis(runtime, buffer, static_cast<double>(offset), static_cast<double>(offset + length))
      .getObject(runtime).getArrayBuffer(runtime);
}

bool isTypedArray(jsi::Runtime &runtime, const jsi::Object &jsObj) {
  jsi::Object ArrayBuffer = runtime
    .global()
    .getPropertyAsObject(runtime, "ArrayBuffer");

  jsi::Value isViewResult = ArrayBuffer
    .getPropertyAsFunction(runtime, "isView")
    .callWithThis(runtime, ArrayBuffer, {jsi::Value(runtime, jsObj)});

  return isViewResult.getBool();
}

} // namespace expo
