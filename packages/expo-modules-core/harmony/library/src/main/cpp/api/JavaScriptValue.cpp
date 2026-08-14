#include "JavaScriptValue.h"

#include <cstring>
#include <stdexcept>

#include <common/JSI/JSIUtils.h>
#include <common/JSI/MemoryBuffer.h>
#include <common/JSI/ObjectDeallocator.h>

#include "errors/CodedError.h"
#include "runtime/RuntimeContext.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

std::shared_ptr<RuntimeContext> requireContext(
    const std::weak_ptr<RuntimeContext> &weakContext) {
  auto context = weakContext.lock();
  if (!context || !context->isAlive()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED", "JavaScript value used after runtime destruction.");
  }
  context->assertRuntimeThread();
  return context;
}

}  // namespace

JavaScriptValue::JavaScriptValue(
    std::shared_ptr<RuntimeContext> context,
    const jsi::Value &value)
    : context_(context), value_(std::make_shared<jsi::Value>(context->runtime(), value)) {}

std::shared_ptr<RuntimeContext> JavaScriptValue::requireContext() const {
  return expo::harmony::requireContext(context_);
}

jsi::Runtime &JavaScriptValue::runtime() const {
  return requireContext()->runtime();
}

jsi::Value JavaScriptValue::get() const {
  auto context = requireContext();
  return jsi::Value(context->runtime(), *value_);
}

bool JavaScriptValue::isValid() const noexcept {
  auto context = context_.lock();
  return context && context->isAlive();
}

std::string JavaScriptValue::kind() const {
  auto &rt = runtime();
  if (value_->isNull()) {
    return "null";
  }
  if (value_->isUndefined()) {
    return "undefined";
  }
  if (value_->isBool()) {
    return "boolean";
  }
  if (value_->isNumber()) {
    return "number";
  }
  if (value_->isString()) {
    return "string";
  }
  if (value_->isSymbol()) {
    return "symbol";
  }
  if (value_->isBigInt()) {
    return "bigint";
  }
  if (isFunction()) {
    return "function";
  }
  if (isArray()) {
    return "array";
  }
  if (value_->isObject()) {
    return "object";
  }
  throw CodedError("ERR_UNKNOWN_JS_VALUE", "Unknown JavaScript value kind.");
}

bool JavaScriptValue::isNull() const {
  requireContext();
  return value_->isNull();
}

bool JavaScriptValue::isUndefined() const {
  requireContext();
  return value_->isUndefined();
}

bool JavaScriptValue::isBool() const {
  requireContext();
  return value_->isBool();
}

bool JavaScriptValue::isNumber() const {
  requireContext();
  return value_->isNumber();
}

bool JavaScriptValue::isString() const {
  requireContext();
  return value_->isString();
}

bool JavaScriptValue::isSymbol() const {
  requireContext();
  return value_->isSymbol();
}

bool JavaScriptValue::isBigInt() const {
  requireContext();
  return value_->isBigInt();
}

bool JavaScriptValue::isObject() const {
  requireContext();
  return value_->isObject();
}

bool JavaScriptValue::isFunction() const {
  return value_->isObject() && value_->getObject(runtime()).isFunction(runtime());
}

bool JavaScriptValue::isArray() const {
  return value_->isObject() && value_->getObject(runtime()).isArray(runtime());
}

bool JavaScriptValue::isArrayBuffer() const {
  return value_->isObject() && value_->getObject(runtime()).isArrayBuffer(runtime());
}

bool JavaScriptValue::isTypedArray() const {
  return value_->isObject() && expo::isTypedArray(runtime(), value_->getObject(runtime()));
}

bool JavaScriptValue::getBool() const {
  requireContext();
  if (!value_->isBool()) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript boolean value.");
  }
  return value_->getBool();
}

double JavaScriptValue::getDouble() const {
  requireContext();
  if (!value_->isNumber()) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript number value.");
  }
  return value_->getNumber();
}

std::string JavaScriptValue::getString() const {
  auto &rt = runtime();
  if (!value_->isString()) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript string value.");
  }
  return value_->getString(rt).utf8(rt);
}

JavaScriptObject JavaScriptValue::getObject() const {
  auto context = requireContext();
  if (!value_->isObject()) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript object value.");
  }
  return JavaScriptObject(context, value_->getObject(context->runtime()));
}

JavaScriptFunction JavaScriptValue::getFunction() const {
  auto context = requireContext();
  if (!value_->isObject() || !value_->getObject(context->runtime()).isFunction(context->runtime())) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript function value.");
  }
  return JavaScriptFunction(
      context, value_->getObject(context->runtime()).getFunction(context->runtime()));
}

JavaScriptArrayBuffer JavaScriptValue::getArrayBuffer() const {
  auto context = requireContext();
  if (!value_->isObject() || !value_->getObject(context->runtime()).isArrayBuffer(context->runtime())) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript ArrayBuffer value.");
  }
  return JavaScriptArrayBuffer(
      context, value_->getObject(context->runtime()).getArrayBuffer(context->runtime()));
}

JavaScriptTypedArray JavaScriptValue::getTypedArray() const {
  auto context = requireContext();
  if (!value_->isObject() || !expo::isTypedArray(context->runtime(), value_->getObject(context->runtime()))) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript TypedArray value.");
  }
  return JavaScriptTypedArray(context, value_->getObject(context->runtime()));
}

std::vector<JavaScriptValue> JavaScriptValue::getArray() const {
  auto context = requireContext();
  auto &rt = context->runtime();
  if (!value_->isObject() || !value_->getObject(rt).isArray(rt)) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript array value.");
  }
  auto array = value_->getObject(rt).getArray(rt);
  std::vector<JavaScriptValue> result;
  result.reserve(array.size(rt));
  for (size_t index = 0; index < array.size(rt); ++index) {
    result.emplace_back(context, array.getValueAtIndex(rt, index));
  }
  return result;
}

JavaScriptObject::JavaScriptObject(
    std::shared_ptr<RuntimeContext> context,
    const jsi::Object &object)
    : context_(context),
      object_(std::make_shared<jsi::Object>(
          jsi::Value(context->runtime(), object).getObject(context->runtime()))) {}

std::shared_ptr<RuntimeContext> JavaScriptObject::requireContext() const {
  return expo::harmony::requireContext(context_);
}

jsi::Runtime &JavaScriptObject::runtime() const {
  return requireContext()->runtime();
}

jsi::Object JavaScriptObject::get() const {
  auto context = requireContext();
  return jsi::Value(context->runtime(), *object_).getObject(context->runtime());
}

bool JavaScriptObject::isValid() const noexcept {
  auto context = context_.lock();
  return context && context->isAlive();
}

bool JavaScriptObject::strictEquals(const JavaScriptObject &other) const {
  auto context = requireContext();
  auto otherContext = other.requireContext();
  if (context.get() != otherContext.get()) {
    return false;
  }
  return jsi::Object::strictEquals(context->runtime(), *object_, *other.object_);
}

bool JavaScriptObject::hasProperty(const std::string &name) const {
  return object_->hasProperty(runtime(), name.c_str());
}

JavaScriptValue JavaScriptObject::getProperty(const std::string &name) const {
  auto context = requireContext();
  return JavaScriptValue(context, object_->getProperty(context->runtime(), name.c_str()));
}

std::vector<std::string> JavaScriptObject::getPropertyNames() const {
  auto &rt = runtime();
  auto names = object_->getPropertyNames(rt);
  std::vector<std::string> result;
  result.reserve(names.size(rt));
  for (size_t index = 0; index < names.size(rt); ++index) {
    result.push_back(
        names.getValueAtIndex(rt, index).getString(rt).utf8(rt));
  }
  return result;
}

void JavaScriptObject::setProperty(
    const std::string &name,
    const jsi::Value &value) {
  object_->setProperty(runtime(), name.c_str(), value);
}

void JavaScriptObject::unsetProperty(const std::string &name) {
  object_->setProperty(runtime(), name.c_str(), jsi::Value::undefined());
}

void JavaScriptObject::defineProperty(
    const std::string &name,
    const JavaScriptPropertyDescriptor &descriptor) {
  auto &rt = runtime();
  jsi::Object jsDescriptor(rt);
  jsDescriptor.setProperty(rt, "configurable", descriptor.configurable);
  jsDescriptor.setProperty(rt, "enumerable", descriptor.enumerable);
  if (descriptor.value) {
    jsDescriptor.setProperty(rt, "value", descriptor.value->get());
    jsDescriptor.setProperty(rt, "writable", descriptor.writable);
  }
  if (descriptor.getter) {
    jsDescriptor.setProperty(rt, "get", descriptor.getter->get());
  }
  if (descriptor.setter) {
    jsDescriptor.setProperty(rt, "set", descriptor.setter->get());
  }
  expo::common::defineProperty(rt, object_.get(), name.c_str(), std::move(jsDescriptor));
}

void JavaScriptObject::defineNativeDeallocator(
    std::function<void()> deallocator) {
  expo::common::setDeallocator(runtime(), object_, std::move(deallocator));
}

void JavaScriptObject::setExternalMemoryPressure(size_t size) {
  object_->setExternalMemoryPressure(runtime(), size);
}

bool JavaScriptObject::isArray() const {
  return object_->isArray(runtime());
}

std::vector<JavaScriptValue> JavaScriptObject::getArray() const {
  auto context = requireContext();
  auto &rt = context->runtime();
  if (!object_->isArray(rt)) {
    throw CodedError("ERR_JS_VALUE_TYPE", "Expected a JavaScript array object.");
  }
  auto array = object_->getArray(rt);
  std::vector<JavaScriptValue> result;
  result.reserve(array.size(rt));
  for (size_t index = 0; index < array.size(rt); ++index) {
    result.emplace_back(context, array.getValueAtIndex(rt, index));
  }
  return result;
}

bool JavaScriptObject::isArrayBuffer() const {
  return object_->isArrayBuffer(runtime());
}

JavaScriptArrayBuffer JavaScriptObject::getArrayBuffer() const {
  auto context = requireContext();
  if (!object_->isArrayBuffer(context->runtime())) {
    throw CodedError(
        "ERR_JS_VALUE_TYPE", "Expected a JavaScript ArrayBuffer object.");
  }
  return JavaScriptArrayBuffer(
      context, object_->getArrayBuffer(context->runtime()));
}

bool JavaScriptObject::isFunction() const {
  return object_->isFunction(runtime());
}

bool JavaScriptObject::isTypedArray() const {
  return expo::isTypedArray(runtime(), *object_);
}

JavaScriptWeakObject JavaScriptObject::createWeak() const {
  return JavaScriptWeakObject(*this);
}

JavaScriptWeakObject::JavaScriptWeakObject(const JavaScriptObject &object)
    : context_(object.requireContext()),
      weakObject_(std::make_shared<jsi::WeakObject>(object.runtime(), object.get())) {}

std::optional<JavaScriptObject> JavaScriptWeakObject::lock() const {
  auto context = expo::harmony::requireContext(context_);
  auto value = weakObject_->lock(context->runtime());
  if (value.isUndefined()) {
    return std::nullopt;
  }
  return JavaScriptObject(context, value.getObject(context->runtime()));
}

JavaScriptFunction::JavaScriptFunction(
    std::shared_ptr<RuntimeContext> context,
    const jsi::Function &function)
    : context_(context),
      function_(std::make_shared<jsi::Function>(
          jsi::Value(context->runtime(), function)
              .getObject(context->runtime())
              .getFunction(context->runtime()))) {}

std::shared_ptr<RuntimeContext> JavaScriptFunction::requireContext() const {
  return expo::harmony::requireContext(context_);
}

jsi::Runtime &JavaScriptFunction::runtime() const {
  return requireContext()->runtime();
}

jsi::Function JavaScriptFunction::get() const {
  auto context = requireContext();
  return jsi::Value(context->runtime(), *function_)
      .getObject(context->runtime())
      .getFunction(context->runtime());
}

bool JavaScriptFunction::isValid() const noexcept {
  auto context = context_.lock();
  return context && context->isAlive();
}

JavaScriptValue JavaScriptFunction::call(
    const jsi::Value *arguments,
    size_t argumentCount) const {
  auto context = requireContext();
  return JavaScriptValue(
      context, function_->call(context->runtime(), arguments, argumentCount));
}

JavaScriptValue JavaScriptFunction::callWithThis(
    const JavaScriptObject &thisObject,
    const jsi::Value *arguments,
    size_t argumentCount) const {
  auto context = requireContext();
  return JavaScriptValue(
      context,
      function_->callWithThis(
          context->runtime(), thisObject.get(), arguments, argumentCount));
}

JavaScriptArrayBuffer::JavaScriptArrayBuffer(
    std::shared_ptr<RuntimeContext> context,
    const jsi::ArrayBuffer &buffer)
    : context_(context),
      buffer_(std::make_shared<jsi::ArrayBuffer>(
          jsi::Value(context->runtime(), buffer)
              .getObject(context->runtime())
              .getArrayBuffer(context->runtime()))) {}

JavaScriptArrayBuffer JavaScriptArrayBuffer::create(
    const std::shared_ptr<RuntimeContext> &context,
    uint8_t *data,
    size_t size,
    std::function<void()> deallocator) {
  context->assertRuntimeThread();
  auto buffer = std::make_shared<expo::MemoryBuffer>(
      data, size, std::move(deallocator));
  return JavaScriptArrayBuffer(
      context, jsi::ArrayBuffer(context->runtime(), std::move(buffer)));
}

std::shared_ptr<RuntimeContext> JavaScriptArrayBuffer::requireContext() const {
  return expo::harmony::requireContext(context_);
}

jsi::Runtime &JavaScriptArrayBuffer::runtime() const {
  return requireContext()->runtime();
}

jsi::ArrayBuffer JavaScriptArrayBuffer::get() const {
  auto context = requireContext();
  return jsi::Value(context->runtime(), *buffer_)
      .getObject(context->runtime())
      .getArrayBuffer(context->runtime());
}

bool JavaScriptArrayBuffer::isValid() const noexcept {
  auto context = context_.lock();
  return context && context->isAlive();
}

uint8_t *JavaScriptArrayBuffer::data() const {
  return buffer_->data(runtime());
}

size_t JavaScriptArrayBuffer::size() const {
  return buffer_->size(runtime());
}

void JavaScriptArrayBuffer::readBytes(
    size_t offset,
    void *destination,
    size_t byteCount) const {
  if ((destination == nullptr && byteCount != 0) || offset > size() || byteCount > size() - offset) {
    throw CodedError("ERR_BUFFER_OUT_OF_BOUNDS", "ArrayBuffer read is out of bounds.");
  }
  std::memcpy(destination, data() + offset, byteCount);
}

void JavaScriptArrayBuffer::writeBytes(
    size_t offset,
    const void *source,
    size_t byteCount) const {
  if ((source == nullptr && byteCount != 0) || offset > size() || byteCount > size() - offset) {
    throw CodedError("ERR_BUFFER_OUT_OF_BOUNDS", "ArrayBuffer write is out of bounds.");
  }
  std::memcpy(data() + offset, source, byteCount);
}

JavaScriptTypedArray::JavaScriptTypedArray(
    std::shared_ptr<RuntimeContext> context,
    const jsi::Object &typedArray)
    : context_(context),
      typedArray_(std::make_shared<expo::TypedArray>(context->runtime(), typedArray)) {
  if (!expo::isTypedArray(context->runtime(), typedArray)) {
    throw CodedError("ERR_EXPECTED_TYPED_ARRAY", "Expected a JavaScript TypedArray.");
  }
  try {
    (void)typedArray_->getKind(context->runtime());
  } catch (const std::out_of_range &) {
    throw CodedError(
        "ERR_EXPECTED_TYPED_ARRAY",
        "Expected a JavaScript TypedArray, but received a DataView or an unknown ArrayBuffer view.");
  }
}

std::shared_ptr<RuntimeContext> JavaScriptTypedArray::requireContext() const {
  return expo::harmony::requireContext(context_);
}

jsi::Runtime &JavaScriptTypedArray::runtime() const {
  return requireContext()->runtime();
}

jsi::Object JavaScriptTypedArray::get() const {
  auto context = requireContext();
  return jsi::Value(context->runtime(), *typedArray_).getObject(context->runtime());
}

bool JavaScriptTypedArray::isValid() const noexcept {
  auto context = context_.lock();
  return context && context->isAlive();
}

expo::TypedArrayKind JavaScriptTypedArray::kind() const {
  return typedArray_->getKind(runtime());
}

size_t JavaScriptTypedArray::byteOffset() const {
  return typedArray_->byteOffset(runtime());
}

size_t JavaScriptTypedArray::byteLength() const {
  return typedArray_->byteLength(runtime());
}

size_t JavaScriptTypedArray::length() const {
  auto &rt = runtime();
  auto value = typedArray_->getProperty(rt, "length");
  if (!value.isNumber() || value.getNumber() < 0) {
    throw CodedError("ERR_INVALID_TYPED_ARRAY", "TypedArray length is invalid.");
  }
  return static_cast<size_t>(value.getNumber());
}

void *JavaScriptTypedArray::data() const {
  return typedArray_->getRawPointer(runtime());
}

void JavaScriptTypedArray::readBytes(
    size_t byteOffset,
    void *destination,
    size_t size) const {
  if ((destination == nullptr && size != 0) || byteOffset > byteLength() || size > byteLength() - byteOffset) {
    throw CodedError("ERR_BUFFER_OUT_OF_BOUNDS", "TypedArray read is out of bounds.");
  }
  std::memcpy(destination, static_cast<const uint8_t *>(data()) + byteOffset, size);
}

void JavaScriptTypedArray::writeBytes(
    size_t byteOffset,
    const void *source,
    size_t size) const {
  if ((source == nullptr && size != 0) || byteOffset > byteLength() || size > byteLength() - byteOffset) {
    throw CodedError("ERR_BUFFER_OUT_OF_BOUNDS", "TypedArray write is out of bounds.");
  }
  std::memcpy(static_cast<uint8_t *>(data()) + byteOffset, source, size);
}

JavaScriptArrayBuffer JavaScriptTypedArray::buffer() const {
  auto context = requireContext();
  return JavaScriptArrayBuffer(context, typedArray_->getBuffer(context->runtime()));
}

}  // namespace expo::harmony
