#pragma once

#include "api/JavaScriptValue.h"
#include "errors/CodedError.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <functional>
#include <memory>
#include <string>
#include <type_traits>
#include <vector>

namespace expo::harmony {

class NativeArrayBuffer final {
 public:
  explicit NativeArrayBuffer(size_t size)
      : storage_(std::make_shared<std::vector<uint8_t>>(size)) {}
  explicit NativeArrayBuffer(std::vector<uint8_t> bytes)
      : storage_(std::make_shared<std::vector<uint8_t>>(std::move(bytes))) {}

  uint8_t* data() noexcept { return storage_->data(); }
  const uint8_t* data() const noexcept { return storage_->data(); }
  size_t size() const noexcept { return storage_->size(); }
  const std::shared_ptr<std::vector<uint8_t>>& storage() const noexcept {
    return storage_;
  }

 private:
  std::shared_ptr<std::vector<uint8_t>> storage_;
};

template <typename Element, expo::TypedArrayKind Kind>
class ConcreteTypedArray final {
 public:
  using value_type = Element;
  static constexpr expo::TypedArrayKind kind = Kind;

  explicit ConcreteTypedArray(JavaScriptTypedArray array)
      : array_(std::move(array)) {
    if (array_.kind() != Kind) {
      throw CodedError(
          "ERR_TYPED_ARRAY_KIND",
          "JavaScript TypedArray has a different element type than requested.");
    }
  }

  size_t size() const { return array_.length(); }
  bool empty() const { return size() == 0; }
  Element get(size_t index) const {
    requireIndex(index);
    Element value{};
    array_.readBytes(index * sizeof(Element), &value, sizeof(Element));
    return value;
  }
  void set(size_t index, Element value) const {
    requireIndex(index);
    array_.writeBytes(index * sizeof(Element), &value, sizeof(Element));
  }
  Element operator[](size_t index) const { return get(index); }
  const JavaScriptTypedArray& raw() const noexcept { return array_; }

 private:
  void requireIndex(size_t index) const {
    if (index >= size()) {
      throw CodedError(
          "ERR_BUFFER_OUT_OF_BOUNDS",
          "TypedArray index " + std::to_string(index) + " is out of bounds.");
    }
  }

  JavaScriptTypedArray array_;
};

using Int8Array = ConcreteTypedArray<int8_t, expo::TypedArrayKind::Int8Array>;
using Int16Array = ConcreteTypedArray<int16_t, expo::TypedArrayKind::Int16Array>;
using Int32Array = ConcreteTypedArray<int32_t, expo::TypedArrayKind::Int32Array>;
using Uint8Array = ConcreteTypedArray<uint8_t, expo::TypedArrayKind::Uint8Array>;
using Uint8ClampedArray =
    ConcreteTypedArray<uint8_t, expo::TypedArrayKind::Uint8ClampedArray>;
using Uint16Array = ConcreteTypedArray<uint16_t, expo::TypedArrayKind::Uint16Array>;
using Uint32Array = ConcreteTypedArray<uint32_t, expo::TypedArrayKind::Uint32Array>;
using Float32Array = ConcreteTypedArray<float, expo::TypedArrayKind::Float32Array>;
using Float64Array = ConcreteTypedArray<double, expo::TypedArrayKind::Float64Array>;
using BigInt64Array = ConcreteTypedArray<int64_t, expo::TypedArrayKind::BigInt64Array>;
using BigUint64Array = ConcreteTypedArray<uint64_t, expo::TypedArrayKind::BigUint64Array>;

} // namespace expo::harmony
