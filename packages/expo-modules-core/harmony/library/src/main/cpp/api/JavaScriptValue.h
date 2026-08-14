#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include <jsi/jsi.h>

#include <common/JSI/TypedArray.h>

namespace expo::harmony {

class RuntimeContext;
class JavaScriptObject;
class JavaScriptFunction;
class JavaScriptWeakObject;
class JavaScriptArrayBuffer;
class JavaScriptTypedArray;

class JavaScriptValue {
public:
  JavaScriptValue(
      std::shared_ptr<RuntimeContext> context,
      const facebook::jsi::Value &value);

  facebook::jsi::Value get() const;
  bool isValid() const noexcept;
  std::string kind() const;
  bool isNull() const;
  bool isUndefined() const;
  bool isBool() const;
  bool isNumber() const;
  bool isString() const;
  bool isSymbol() const;
  bool isBigInt() const;
  bool isObject() const;
  bool isFunction() const;
  bool isArray() const;
  bool isArrayBuffer() const;
  bool isTypedArray() const;
  bool getBool() const;
  double getDouble() const;
  std::string getString() const;
  JavaScriptObject getObject() const;
  JavaScriptFunction getFunction() const;
  JavaScriptArrayBuffer getArrayBuffer() const;
  JavaScriptTypedArray getTypedArray() const;
  std::vector<JavaScriptValue> getArray() const;

protected:
  std::shared_ptr<RuntimeContext> requireContext() const;
  facebook::jsi::Runtime &runtime() const;

  std::weak_ptr<RuntimeContext> context_;
  std::shared_ptr<facebook::jsi::Value> value_;
};

struct JavaScriptPropertyDescriptor {
  bool configurable{false};
  bool enumerable{false};
  bool writable{false};
  std::optional<JavaScriptValue> value;
  std::shared_ptr<JavaScriptFunction> getter;
  std::shared_ptr<JavaScriptFunction> setter;
};

class JavaScriptObject {
public:
  JavaScriptObject(
      std::shared_ptr<RuntimeContext> context,
      const facebook::jsi::Object &object);

  facebook::jsi::Object get() const;
  bool isValid() const noexcept;
  bool strictEquals(const JavaScriptObject &other) const;
  bool hasProperty(const std::string &name) const;
  JavaScriptValue getProperty(const std::string &name) const;
  std::vector<std::string> getPropertyNames() const;
  void setProperty(const std::string &name, const facebook::jsi::Value &value);
  void unsetProperty(const std::string &name);
  void defineProperty(
      const std::string &name,
      const JavaScriptPropertyDescriptor &descriptor);
  void defineNativeDeallocator(std::function<void()> deallocator);
  void setExternalMemoryPressure(size_t size);
  bool isArray() const;
  std::vector<JavaScriptValue> getArray() const;
  bool isArrayBuffer() const;
  JavaScriptArrayBuffer getArrayBuffer() const;
  bool isFunction() const;
  bool isTypedArray() const;
  JavaScriptWeakObject createWeak() const;

private:
  friend class JavaScriptWeakObject;
  std::shared_ptr<RuntimeContext> requireContext() const;
  facebook::jsi::Runtime &runtime() const;

  std::weak_ptr<RuntimeContext> context_;
  std::shared_ptr<facebook::jsi::Object> object_;
};

class JavaScriptWeakObject {
public:
  explicit JavaScriptWeakObject(const JavaScriptObject &object);
  std::optional<JavaScriptObject> lock() const;

private:
  std::weak_ptr<RuntimeContext> context_;
  std::shared_ptr<facebook::jsi::WeakObject> weakObject_;
};

class JavaScriptFunction {
public:
  JavaScriptFunction(
      std::shared_ptr<RuntimeContext> context,
      const facebook::jsi::Function &function);

  facebook::jsi::Function get() const;
  bool isValid() const noexcept;
  JavaScriptValue call(
      const facebook::jsi::Value *arguments = nullptr,
      size_t argumentCount = 0) const;
  JavaScriptValue callWithThis(
      const JavaScriptObject &thisObject,
      const facebook::jsi::Value *arguments = nullptr,
      size_t argumentCount = 0) const;

private:
  std::shared_ptr<RuntimeContext> requireContext() const;
  facebook::jsi::Runtime &runtime() const;

  std::weak_ptr<RuntimeContext> context_;
  std::shared_ptr<facebook::jsi::Function> function_;
};

class JavaScriptArrayBuffer {
public:
  JavaScriptArrayBuffer(
      std::shared_ptr<RuntimeContext> context,
      const facebook::jsi::ArrayBuffer &buffer);

  static JavaScriptArrayBuffer create(
      const std::shared_ptr<RuntimeContext> &context,
      uint8_t *data,
      size_t size,
      std::function<void()> deallocator);
  facebook::jsi::ArrayBuffer get() const;
  bool isValid() const noexcept;
  uint8_t *data() const;
  size_t size() const;
  void readBytes(size_t offset, void *destination, size_t size) const;
  void writeBytes(size_t offset, const void *source, size_t size) const;

private:
  std::shared_ptr<RuntimeContext> requireContext() const;
  facebook::jsi::Runtime &runtime() const;

  std::weak_ptr<RuntimeContext> context_;
  std::shared_ptr<facebook::jsi::ArrayBuffer> buffer_;
};

class JavaScriptTypedArray {
public:
  JavaScriptTypedArray(
      std::shared_ptr<RuntimeContext> context,
      const facebook::jsi::Object &typedArray);

  facebook::jsi::Object get() const;
  bool isValid() const noexcept;
  expo::TypedArrayKind kind() const;
  size_t byteOffset() const;
  size_t byteLength() const;
  size_t length() const;
  void *data() const;
  void readBytes(size_t byteOffset, void *destination, size_t size) const;
  void writeBytes(size_t byteOffset, const void *source, size_t size) const;
  JavaScriptArrayBuffer buffer() const;

private:
  std::shared_ptr<RuntimeContext> requireContext() const;
  facebook::jsi::Runtime &runtime() const;

  std::weak_ptr<RuntimeContext> context_;
  std::shared_ptr<expo::TypedArray> typedArray_;
};

}  // namespace expo::harmony
