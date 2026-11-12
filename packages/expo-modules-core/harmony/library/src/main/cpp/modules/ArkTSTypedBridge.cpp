/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "ArkTSTypedBridge.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <functional>
#include <limits>
#include <map>
#include <optional>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

#include <RNOH/ArkJS.h>

#include <ReactCommon/TurboModuleUtils.h>
#include <react/bridging/CallbackWrapper.h>
#include <react/bridging/LongLivedObject.h>

#include "SynchronousNapiBuffers.h"
#include "api/internal/AsyncTaskLifecycle.h"
#include "api/internal/PromiseSettlementState.h"
#include "common/JSI/JSIUtils.h"
#include "common/JSI/RecordProperty.h"
#include "errors/CodedError.h"
#include "runtime/RnohSyncTask.h"
#include "runtime/RuntimeContext.h"
#include "runtime/RuntimeInstaller.h"

namespace jsi = facebook::jsi;
namespace react = facebook::react;

namespace expo::harmony {
namespace {

constexpr size_t kMaximumTransportDepth = 64;

struct UndefinedValue final {};

struct NullValue final {};

struct BigIntValue final {
  std::string decimal;
};

struct ArrayBufferValue final {
  std::vector<uint8_t> bytes;
  std::shared_ptr<SynchronousBinarySnapshot> synchronousBacking = nullptr;
};

struct ArkTSErrorValue final {
  std::string code;
  std::string message;
  std::optional<std::string> path;
  std::shared_ptr<ArkTSErrorValue> cause;
};

enum class NumericTypedArrayKind {
  Int8,
  Uint8,
  Uint8Clamped,
  Int16,
  Uint16,
  Int32,
  Uint32,
  Float32,
  Float64,
  BigInt64,
  BigUint64,
};

struct NumericTypedArraySpec final {
  const char *constructorName;
  NumericTypedArrayKind kind;
  napi_typedarray_type napiType;
  size_t elementSize;
};

constexpr std::array<NumericTypedArraySpec, 11> kNumericTypedArraySpecs{{
    {"Int8Array", NumericTypedArrayKind::Int8, napi_int8_array, 1},
    {"Uint8Array", NumericTypedArrayKind::Uint8, napi_uint8_array, 1},
    {"Uint8ClampedArray", NumericTypedArrayKind::Uint8Clamped, napi_uint8_clamped_array, 1},
    {"Int16Array", NumericTypedArrayKind::Int16, napi_int16_array, 2},
    {"Uint16Array", NumericTypedArrayKind::Uint16, napi_uint16_array, 2},
    {"Int32Array", NumericTypedArrayKind::Int32, napi_int32_array, 4},
    {"Uint32Array", NumericTypedArrayKind::Uint32, napi_uint32_array, 4},
    {"Float32Array", NumericTypedArrayKind::Float32, napi_float32_array, 4},
    {"Float64Array", NumericTypedArrayKind::Float64, napi_float64_array, 8},
    {"BigInt64Array", NumericTypedArrayKind::BigInt64, napi_bigint64_array, 8},
    {"BigUint64Array", NumericTypedArrayKind::BigUint64, napi_biguint64_array, 8},
}};

struct TypedArrayValue final {
  NumericTypedArrayKind kind;
  size_t length;
  std::vector<uint8_t> bytes;
  std::shared_ptr<SynchronousBinarySnapshot> synchronousBacking = nullptr;
  size_t byteOffset = 0;
};

struct TypedPlatformValue final {
  using Array = std::vector<TypedPlatformValue>;
  using Record = std::map<std::string, TypedPlatformValue>;
  using Callback = std::function<void(Array)>;

  using Storage = std::variant<
      UndefinedValue,
      NullValue,
      bool,
      double,
      std::string,
      BigIntValue,
      ArkTSErrorValue,
      Array,
      Record,
      ArrayBufferValue,
      TypedArrayValue,
      Callback>;

  template <typename Value>
  explicit TypedPlatformValue(Value value) : storage(std::move(value)) {}

  Storage storage;
};

jsi::Value toJSI(jsi::Runtime &runtime, TypedPlatformValue value);
napi_value createNapiCallback(napi_env env, TypedPlatformValue::Callback callback);

class VectorMutableBuffer final : public jsi::MutableBuffer {
public:
  explicit VectorMutableBuffer(std::vector<uint8_t> bytes)
      : bytes_(std::move(bytes)) {}

  size_t size() const override {
    return bytes_.size();
  }

  uint8_t *data() override {
    return bytes_.data();
  }

private:
  std::vector<uint8_t> bytes_;
};

void requireNapiStatus(napi_status status, const char *operation) {
  if (status != napi_ok) {
    throw std::runtime_error(
        std::string("Expo Modules typed NAPI transport failed to ") + operation + " (napi_status=" + std::to_string(static_cast<int>(status)) + ").");
  }
}

std::optional<std::string> readNapiString(
    napi_env env,
    napi_value value) noexcept {
  try {
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
      return std::nullopt;
    }

    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
      return std::nullopt;
    }

    std::vector<char> bytes(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(
            env, value, bytes.data(), bytes.size(), &copied)
        != napi_ok) {
      return std::nullopt;
    }
    return std::string(bytes.data(), copied);
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<std::string> readNapiStringProperty(
    napi_env env,
    napi_value object,
    const char *name) noexcept {
  napi_value value = nullptr;
  if (napi_get_named_property(env, object, name, &value) != napi_ok) {
    return std::nullopt;
  }
  return readNapiString(env, value);
}

ArkTSErrorValue readNapiErrorValue(
    napi_env env,
    napi_value value,
    std::string fallbackMessage) {
  ArkTSErrorValue result;
  auto *current = &result;
  std::vector<napi_value> visited;
  while (true) {
    *current = ArkTSErrorValue{
        readNapiStringProperty(env, value, "code").value_or("ERR_ARKTS_MODULE"),
        readNapiStringProperty(env, value, "message").value_or(fallbackMessage),
        readNapiStringProperty(env, value, "path"),
        nullptr};
    visited.push_back(value);

    napi_value cause = nullptr;
    napi_valuetype type = napi_undefined;
    if (napi_get_named_property(env, value, "cause", &cause) != napi_ok || cause == nullptr || napi_typeof(env, cause, &type) != napi_ok || (type != napi_object && type != napi_function)) {
      break;
    }
    if (visited.size() >= kMaximumTransportDepth) {
      current->cause = std::make_shared<ArkTSErrorValue>(ArkTSErrorValue{
          "ERR_CAUSE_DEPTH", "The native error cause exceeds the transport depth limit.", std::nullopt, nullptr});
      break;
    }
    bool cyclic = false;
    for (auto previous : visited) {
      bool equal = false;
      if (napi_strict_equals(env, previous, cause, &equal) == napi_ok && equal) {
        cyclic = true;
        break;
      }
    }
    if (cyclic) {
      current->cause = std::make_shared<ArkTSErrorValue>(ArkTSErrorValue{
          "ERR_CYCLIC_CAUSE", "The native error cause refers to an earlier error.", std::nullopt, nullptr});
      break;
    }

    current->cause = std::make_shared<ArkTSErrorValue>();
    current = current->cause.get();
    value = cause;
    fallbackMessage = "An ArkTS Expo module error was caused by another error.";
  }
  return result;
}

std::shared_ptr<const CodedError> codedCauseFromArkTS(
    const std::shared_ptr<ArkTSErrorValue> &cause) {
  std::vector<const ArkTSErrorValue *> chain;
  for (auto current = cause.get(); current; current = current->cause.get()) {
    chain.push_back(current);
  }
  std::shared_ptr<const CodedError> result;
  for (auto current = chain.rbegin(); current != chain.rend(); ++current) {
    result = std::make_shared<CodedError>(
        (*current)->code, (*current)->message, (*current)->path, std::move(result));
  }
  return result;
}

ArkTSErrorValue arkTSErrorFromCodedError(const CodedError &error) {
  ArkTSErrorValue result;
  auto *target = &result;
  for (auto current = &error; current; current = current->cause().get()) {
    *target = ArkTSErrorValue{current->code(), current->what(), current->path(), nullptr};
    if (current->cause()) {
      target->cause = std::make_shared<ArkTSErrorValue>();
      target = target->cause.get();
    }
  }
  return result;
}

[[noreturn]] void throwNapiMethodFailure(
    napi_env env,
    napi_status status,
    const std::string &methodName) {
  bool exceptionPending = false;
  if (napi_is_exception_pending(env, &exceptionPending) == napi_ok && exceptionPending) {
    napi_value exception = nullptr;
    if (napi_get_and_clear_last_exception(env, &exception) == napi_ok && exception != nullptr) {
      auto error = readNapiErrorValue(
          env,
          exception,
          "ArkTS Expo method '" + methodName + "' threw an exception.");

      throw CodedError(
          std::move(error.code),
          std::move(error.message),
          std::move(error.path),
          codedCauseFromArkTS(error.cause));
    }
  }

  const napi_extended_error_info *errorInfo = nullptr;
  std::string message = "Expo Modules could not invoke ArkTS method '" + methodName + "' (napi_status=" + std::to_string(static_cast<int>(status)) + ").";
  if (napi_get_last_error_info(env, &errorInfo) == napi_ok && errorInfo != nullptr && errorInfo->error_message != nullptr) {
    message += " ";
    message += errorInfo->error_message;
  }
  throw std::runtime_error(std::move(message));
}

napi_value callNapiMethod(
    napi_env env,
    napi_value instance,
    const std::string &methodName,
    const std::vector<napi_value> &arguments) {
  // Call NAPI directly so ExpoModuleError.code survives exception conversion.
  napi_value method = nullptr;
  auto status = napi_get_named_property(
      env, instance, methodName.c_str(), &method);
  if (status != napi_ok) {
    throwNapiMethodFailure(env, status, methodName);
  }
  napi_valuetype type = napi_undefined;
  status = napi_typeof(env, method, &type);
  if (status != napi_ok) {
    throwNapiMethodFailure(env, status, methodName);
  }
  if (type != napi_function) {
    throw std::runtime_error(
        "Expo Modules ArkTS instance has no method '" + methodName + "'.");
  }

  napi_value result = nullptr;
  status = napi_call_function(
      env,
      instance,
      method,
      arguments.size(),
      arguments.empty() ? nullptr : arguments.data(),
      &result);
  if (status != napi_ok) {
    throwNapiMethodFailure(env, status, methodName);
  }
  bool exceptionPending = false;
  if (napi_is_exception_pending(env, &exceptionPending) != napi_ok || exceptionPending) {
    throwNapiMethodFailure(env, napi_pending_exception, methodName);
  }

  return result;
}

const NumericTypedArraySpec &typedArraySpec(NumericTypedArrayKind kind) {
  for (const auto &spec : kNumericTypedArraySpecs) {
    if (spec.kind == kind) {
      return spec;
    }
  }
  throw std::runtime_error("Expo Modules received an unknown TypedArray kind.");
}

const NumericTypedArraySpec &typedArraySpec(napi_typedarray_type type) {
  for (const auto &spec : kNumericTypedArraySpecs) {
    if (spec.napiType == type) {
      return spec;
    }
  }
  throw std::runtime_error("Expo Modules received an unsupported NAPI TypedArray kind.");
}

std::optional<NumericTypedArrayKind> typedArrayKind(
    jsi::Runtime &runtime,
    const jsi::Object &object) {
  auto arrayBuffer = runtime.global().getPropertyAsObject(runtime, "ArrayBuffer");
  auto isView = arrayBuffer.getPropertyAsFunction(runtime, "isView");
  auto isViewResult = isView.callWithThis(runtime, arrayBuffer, object);
  if (!isViewResult.isBool() || !isViewResult.getBool()) {
    return std::nullopt;
  }

  for (const auto &spec : kNumericTypedArraySpecs) {
    auto constructorValue = runtime.global().getProperty(
        runtime, spec.constructorName);
    if (!constructorValue.isObject()) {
      continue;
    }
    auto constructorObject = constructorValue.getObject(runtime);
    if (!constructorObject.isFunction(runtime)) {
      continue;
    }
    if (object.instanceOf(runtime, constructorObject.getFunction(runtime))) {
      return spec.kind;
    }
  }

  throw std::runtime_error(
      "Expo Modules cannot transport DataView or an unknown ArrayBuffer view as a numeric TypedArray.");
}

std::vector<uint8_t> copyArrayBuffer(jsi::Runtime &runtime, const jsi::Object &object) {
  auto buffer = object.getArrayBuffer(runtime);
  if (buffer.size(runtime) == 0) {
    return {};
  }
  return std::vector<uint8_t>(
      buffer.data(runtime), buffer.data(runtime) + buffer.size(runtime));
}

// Writable arguments use detached snapshots during the ArkTS call. Keep only
// JSI handles and byte ranges here; no JS-owned pointer crosses runtime threads.
struct WritableBinaryRange final {
  jsi::Object buffer;
  size_t offset;
  size_t length;
};

WritableBinaryRange writableBinaryRange(jsi::Runtime &runtime, const jsi::Value &value) {
  if (!value.isObject()) {
    throw CodedError("ERR_WRITABLE_ARGUMENT", "A writable argument must be an ArrayBuffer or numeric TypedArray.");
  }

  auto object = value.getObject(runtime);
  if (object.isArrayBuffer(runtime)) {
    const auto length = object.getArrayBuffer(runtime).size(runtime);
    return {std::move(object), 0, length};
  }
  if (!typedArrayKind(runtime, object)) {
    throw CodedError("ERR_WRITABLE_ARGUMENT", "A writable argument must be an ArrayBuffer or numeric TypedArray.");
  }

  auto buffer = object.getProperty(runtime, "buffer");
  auto offset = object.getProperty(runtime, "byteOffset");
  auto length = object.getProperty(runtime, "byteLength");
  const auto validSize = [](const jsi::Value &size) {
    return size.isNumber() && std::isfinite(size.getNumber()) && size.getNumber() >= 0 && size.getNumber() <= 9007199254740991.0 && std::trunc(size.getNumber()) == size.getNumber() && size.getNumber() <= static_cast<double>(std::numeric_limits<size_t>::max());
  };
  if (!buffer.isObject() || !buffer.getObject(runtime).isArrayBuffer(runtime) || !validSize(offset) || !validSize(length)) {
    throw CodedError("ERR_WRITABLE_ARGUMENT", "A writable argument has invalid binary storage.");
  }

  auto backing = buffer.getObject(runtime);
  const auto offsetBytes = static_cast<size_t>(offset.getNumber());
  const auto lengthBytes = static_cast<size_t>(length.getNumber());
  const auto backingSize = backing.getArrayBuffer(runtime).size(runtime);
  if (offsetBytes > backingSize || lengthBytes > backingSize - offsetBytes) {
    throw CodedError("ERR_WRITABLE_ARGUMENT", "A writable argument exceeds its backing buffer.");
  }

  return {std::move(backing), offsetBytes, lengthBytes};
}

// These JSI identities never leave the JavaScript thread. The shared byte
// vectors contain independent copies, not pointers into a runtime heap.
class SynchronousBinarySnapshots final {
public:
  std::shared_ptr<SynchronousBinarySnapshot> get(
      jsi::Runtime &runtime, const jsi::Object &buffer, size_t offset, size_t length) {
    // Align the union's beginning for every supported numeric element size.
    const size_t alignedOffset = offset - offset % sizeof(uint64_t);
    for (const auto &entry : entries_) {
      if (jsi::Object::strictEquals(runtime, entry.first, buffer)) {
        entry.second->offset = std::min(entry.second->offset, alignedOffset);
        entry.second->end = std::max(entry.second->end, offset + length);
        return entry.second;
      }
    }
    auto snapshot = std::make_shared<SynchronousBinarySnapshot>(
        SynchronousBinarySnapshot{{}, alignedOffset, offset + length});
    entries_.emplace_back(jsi::Value(runtime, buffer).getObject(runtime), snapshot);
    return snapshot;
  }

  void materialize(jsi::Runtime &runtime) {
    for (const auto &entry : entries_) {
      auto buffer = entry.first.getArrayBuffer(runtime);
      auto &snapshot = *entry.second;
      if (snapshot.offset > snapshot.end || snapshot.end > buffer.size(runtime)) {
        throw std::runtime_error("A synchronous binary backing buffer was detached or resized.");
      }
      if (snapshot.end > snapshot.offset) {
        snapshot.bytes.assign(buffer.data(runtime) + snapshot.offset,
                              buffer.data(runtime) + snapshot.end);
      }
    }
  }

private:
  std::vector<std::pair<jsi::Object, std::shared_ptr<SynchronousBinarySnapshot>>> entries_;
};

TypedArrayValue copyTypedArray(
    jsi::Runtime &runtime,
    const jsi::Object &object,
    NumericTypedArrayKind kind,
    SynchronousBinarySnapshots *snapshots = nullptr) {
  auto bufferValue = object.getProperty(runtime, "buffer");
  auto offsetValue = object.getProperty(runtime, "byteOffset");
  auto lengthValue = object.getProperty(runtime, "byteLength");
  if (!bufferValue.isObject() || !bufferValue.getObject(runtime).isArrayBuffer(runtime) || !offsetValue.isNumber() || !lengthValue.isNumber()) {
    throw std::runtime_error("TypedArray has an invalid backing buffer.");
  }

  const auto offsetNumber = offsetValue.getNumber();
  const auto lengthNumber = lengthValue.getNumber();
  if (!std::isfinite(offsetNumber) || !std::isfinite(lengthNumber) || offsetNumber < 0 || lengthNumber < 0 || offsetNumber > 9007199254740991.0 || lengthNumber > 9007199254740991.0 || offsetNumber > static_cast<double>(std::numeric_limits<size_t>::max()) || lengthNumber > static_cast<double>(std::numeric_limits<size_t>::max()) || std::trunc(offsetNumber) != offsetNumber || std::trunc(lengthNumber) != lengthNumber) {
    throw std::runtime_error("TypedArray has an invalid byte range.");
  }

  auto buffer = bufferValue.getObject(runtime).getArrayBuffer(runtime);
  const auto offset = static_cast<size_t>(offsetNumber);
  const auto length = static_cast<size_t>(lengthNumber);
  if (offset > buffer.size(runtime) || length > buffer.size(runtime) - offset) {
    throw std::runtime_error("TypedArray byte range exceeds its backing buffer.");
  }

  const auto &spec = typedArraySpec(kind);
  if (length % spec.elementSize != 0 || offset % spec.elementSize != 0) {
    throw std::runtime_error(
        "TypedArray byte length is not aligned to its element size.");
  }
  if (snapshots) {
    return TypedArrayValue{kind, length / spec.elementSize, {}, snapshots->get(runtime, bufferValue.getObject(runtime), offset, length), offset};
  }

  std::vector<uint8_t> bytes;
  if (length > 0) {
    bytes.assign(
        buffer.data(runtime) + offset,
        buffer.data(runtime) + offset + length);
  }

  return TypedArrayValue{kind, length / spec.elementSize, std::move(bytes)};
}

TypedPlatformValue fromJSI(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    size_t depth,
    SynchronousBinarySnapshots *snapshots = nullptr) {
  if (depth > kMaximumTransportDepth) {
    throw std::runtime_error("Expo Modules platform value exceeds the maximum nesting depth.");
  }

  if (value.isUndefined()) {
    return TypedPlatformValue(UndefinedValue{});
  }
  if (value.isNull()) {
    return TypedPlatformValue(NullValue{});
  }
  if (value.isBool()) {
    return TypedPlatformValue(value.getBool());
  }
  if (value.isNumber()) {
    return TypedPlatformValue(value.getNumber());
  }
  if (value.isString()) {
    return TypedPlatformValue(value.getString(runtime).utf8(runtime));
  }
  if (value.isBigInt()) {
    return TypedPlatformValue(BigIntValue{value.getBigInt(runtime).toString(runtime).utf8(runtime)});
  }
  if (!value.isObject()) {
    throw std::runtime_error("Expo Modules cannot transport a symbol to ArkTS.");
  }

  auto object = value.getObject(runtime);
  if (object.isFunction(runtime)) {
    auto context = RuntimeInstaller::installedContext(runtime);
    if (!context) {
      throw CodedError("ERR_RUNTIME_DESTROYED", "Cannot retain an Expo callback after runtime destruction.");
    }

    auto weakCallback = react::CallbackWrapper::createWeak(object.getFunction(runtime), runtime, context->jsInvoker());
    auto callback = weakCallback.lock();
    if (!callback) {
      throw CodedError("ERR_RUNTIME_DESTROYED", "The Expo callback was released before it could be retained.");
    }

    try {
      context->retainLongLivedObject(callback);
    } catch (...) {
      // createWeak already rooted the function in React Native's collection.
      callback->allowRelease();
      throw;
    }

    auto weakContext = std::weak_ptr<RuntimeContext>(context);
    // The last ArkTS callback copy releases its JS root on the owning executor.
    // RuntimeContext also retires the root on reload, even if ArkTS retains it.
    auto lifetime = std::shared_ptr<void>(nullptr, [weakContext, weakCallback](void *) {
      try {
        if (auto context = weakContext.lock(); context && context->isAcceptingTasks()) {
          context->dispatchToJavaScript([weakCallback]() {
            if (auto callback = weakCallback.lock()) callback->allowRelease();
          });
        }
      } catch (...) {
        // RuntimeContext owns the remaining root until its executor teardown.
      }
    });

    return TypedPlatformValue(TypedPlatformValue::Callback(
        [weakContext, weakCallback, lifetime](TypedPlatformValue::Array arguments) {
          if (auto context = weakContext.lock(); context && context->isAcceptingTasks()) {
            context->dispatchToJavaScript([weakCallback, arguments = std::move(arguments)]() mutable {
              if (auto callback = weakCallback.lock()) {
                auto &rt = callback->runtime();
                std::vector<jsi::Value> values;
                values.reserve(arguments.size());
                for (auto &argument : arguments) values.push_back(toJSI(rt, std::move(argument)));

                callback->callback().call(rt, static_cast<const jsi::Value *>(values.data()), values.size());
              }
            });
          }
        }));
  }
  if (object.isArrayBuffer(runtime)) {
    if (snapshots) {
      return TypedPlatformValue(ArrayBufferValue{{}, snapshots->get(runtime, object, 0, object.getArrayBuffer(runtime).size(runtime))});
    }
    return TypedPlatformValue(ArrayBufferValue{copyArrayBuffer(runtime, object)});
  }
  if (auto kind = typedArrayKind(runtime, object)) {
    return TypedPlatformValue(copyTypedArray(runtime, object, *kind, snapshots));
  }
  if (object.isArray(runtime)) {
    auto array = object.getArray(runtime);
    TypedPlatformValue::Array result;
    result.reserve(array.size(runtime));
    for (size_t index = 0; index < array.size(runtime); ++index) {
      auto element = array.getValueAtIndex(runtime, index);
      result.push_back(fromJSI(runtime, element, depth + 1, snapshots));
    }
    return TypedPlatformValue(std::move(result));
  }

  TypedPlatformValue::Record result;
  auto names = object.getPropertyNames(runtime);
  for (size_t index = 0; index < names.size(runtime); ++index) {
    auto name = names.getValueAtIndex(runtime, index);
    if (!name.isString()) {
      continue;
    }

    auto key = name.getString(runtime);
    auto property = object.getProperty(runtime, key);
    result.emplace(
        key.utf8(runtime), fromJSI(runtime, property, depth + 1, snapshots));
  }

  return TypedPlatformValue(std::move(result));
}

napi_value createNapiArrayBuffer(napi_env env, const std::vector<uint8_t> &bytes) {
  void *data = nullptr;
  napi_value result = nullptr;
  requireNapiStatus(
      napi_create_arraybuffer(env, bytes.size(), &data, &result),
      "create an ArrayBuffer");
  if (!bytes.empty()) {
    std::memcpy(data, bytes.data(), bytes.size());
  }

  return result;
}

napi_value synchronousNapiArrayBuffer(napi_env env,
                                      const std::shared_ptr<SynchronousBinarySnapshot> &snapshot,
                                      SynchronousNapiBuffers *buffers) {
  if (!buffers) {
    throw std::runtime_error("Synchronous binary snapshot has no NAPI buffer scope.");
  }
  return buffers->get(snapshot);
}

napi_value toNapi(napi_env env, ArkJS &arkJS, TypedPlatformValue value, SynchronousNapiBuffers *buffers = nullptr) {
  return std::visit(
      [&](auto &&stored) -> napi_value {
        using Value = std::decay_t<decltype(stored)>;
        if constexpr (std::is_same_v<Value, UndefinedValue>) {
          return arkJS.getUndefined();
        } else if constexpr (std::is_same_v<Value, NullValue>) {
          return arkJS.getNull();
        } else if constexpr (std::is_same_v<Value, bool>) {
          return arkJS.createBoolean(stored);
        } else if constexpr (std::is_same_v<Value, double>) {
          return arkJS.createDouble(stored);
        } else if constexpr (std::is_same_v<Value, std::string>) {
          return arkJS.createString(stored);
        } else if constexpr (std::is_same_v<Value, BigIntValue>) {
          napi_value global = nullptr;
          napi_value constructor = nullptr;
          napi_value result = nullptr;
          requireNapiStatus(napi_get_global(env, &global), "get the ArkTS global object");
          requireNapiStatus(napi_get_named_property(env, global, "BigInt", &constructor), "get BigInt");

          auto decimal = arkJS.createString(stored.decimal);
          requireNapiStatus(napi_call_function(env, global, constructor, 1, &decimal, &result), "create BigInt");
          return result;
        } else if constexpr (std::is_same_v<Value, ArkTSErrorValue>) {
          throw std::runtime_error("An ArkTS error result cannot be passed back as a native argument.");
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Array>) {
          std::vector<napi_value> items;
          items.reserve(stored.size());
          for (auto &item : stored) {
            items.push_back(toNapi(env, arkJS, std::move(item), buffers));
          }
          return arkJS.createArray(items);
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Record>) {
          napi_value result = nullptr;
          requireNapiStatus(napi_create_object(env, &result), "create a record");

          std::vector<napi_property_descriptor> properties;
          properties.reserve(stored.size());
          for (auto &[key, item] : stored) {
            // A value name preserves embedded NULs, and defining the property
            // handles keys such as __proto__ without invoking inherited setters.
            properties.push_back(napi_property_descriptor{
                .name = arkJS.createString(key),
                .value = toNapi(env, arkJS, std::move(item), buffers),
                .attributes = napi_default_jsproperty,
            });
          }

          if (!properties.empty()) {
            requireNapiStatus(napi_define_properties(env, result, properties.size(), properties.data()), "define record properties");
          }
          return result;
        } else if constexpr (std::is_same_v<Value, ArrayBufferValue>) {
          if (stored.synchronousBacking) {
            return synchronousNapiArrayBuffer(env, stored.synchronousBacking, buffers);
          }
          return createNapiArrayBuffer(env, stored.bytes);
        } else if constexpr (std::is_same_v<Value, TypedArrayValue>) {
          const auto &spec = typedArraySpec(stored.kind);
          const auto &bytes = stored.synchronousBacking ? stored.synchronousBacking->bytes : stored.bytes;
          if (stored.synchronousBacking && stored.byteOffset < stored.synchronousBacking->offset) {
            throw std::runtime_error("TypedArray byte offset precedes its synchronous snapshot.");
          }

          const auto offset = stored.synchronousBacking
                                ? stored.byteOffset - stored.synchronousBacking->offset
                                : stored.byteOffset;
          if (stored.length > std::numeric_limits<size_t>::max() / spec.elementSize || offset > bytes.size() || offset % spec.elementSize != 0 || stored.length * spec.elementSize > bytes.size() - offset || (!stored.synchronousBacking && stored.length * spec.elementSize != bytes.size())) {
            throw std::runtime_error(
                "Expo Modules received inconsistent TypedArray storage.");
          }

          auto arrayBuffer = stored.synchronousBacking
                               ? synchronousNapiArrayBuffer(env, stored.synchronousBacking, buffers)
                               : createNapiArrayBuffer(env, stored.bytes);
          napi_value result = nullptr;
          requireNapiStatus(
              napi_create_typedarray(
                  env,
                  spec.napiType,
                  stored.length,
                  arrayBuffer,
                  offset,
                  &result),
              "create a TypedArray");
          return result;
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Callback>) {
          return createNapiCallback(env, std::move(stored));
        }
      },
      std::move(value.storage));
}

TypedPlatformValue fromNapi(napi_env env, ArkJS &arkJS, napi_value value, size_t depth) {
  if (depth > kMaximumTransportDepth) {
    throw std::runtime_error("Expo Modules platform result exceeds the maximum nesting depth.");
  }

  switch (arkJS.getType(value)) {
    case napi_undefined:
      return TypedPlatformValue(UndefinedValue{});
    case napi_null:
      return TypedPlatformValue(NullValue{});
    case napi_boolean:
      return TypedPlatformValue(arkJS.getBoolean(value));
    case napi_number:
      return TypedPlatformValue(arkJS.getDouble(value));
    case napi_string:
      return TypedPlatformValue(arkJS.getString(value));
    case napi_bigint: {
      napi_value decimal = nullptr;
      requireNapiStatus(napi_coerce_to_string(env, value, &decimal), "encode BigInt");
      return TypedPlatformValue(BigIntValue{arkJS.getString(decimal)});
    }
    case napi_object: {
      bool isTypedArray = false;
      requireNapiStatus(
          napi_is_typedarray(env, value, &isTypedArray),
          "inspect a TypedArray result");
      if (isTypedArray) {
        napi_typedarray_type type;
        size_t length = 0;
        void *data = nullptr;
        napi_value arrayBuffer = nullptr;
        size_t byteOffset = 0;
        requireNapiStatus(
            napi_get_typedarray_info(
                env, value, &type, &length, &data, &arrayBuffer, &byteOffset),
            "read a TypedArray result");
        const auto &spec = typedArraySpec(type);
        if (length > std::numeric_limits<size_t>::max() / spec.elementSize) {
          throw std::runtime_error(
              "Expo Modules received an oversized TypedArray result.");
        }

        const auto byteLength = length * spec.elementSize;
        auto *bytes = static_cast<uint8_t *>(data);
        if (byteLength > 0 && bytes == nullptr) {
          throw std::runtime_error(
              "Expo Modules received a TypedArray result without backing storage.");
        }

        std::vector<uint8_t> copiedBytes;
        if (byteLength > 0) {
          copiedBytes.assign(bytes, bytes + byteLength);
        }
        return TypedPlatformValue(TypedArrayValue{
            spec.kind,
            length,
            std::move(copiedBytes)});
      }

      bool isArrayBuffer = false;
      requireNapiStatus(
          napi_is_arraybuffer(env, value, &isArrayBuffer),
          "inspect an ArrayBuffer result");
      if (isArrayBuffer) {
        return TypedPlatformValue(ArrayBufferValue{arkJS.getArrayBuffer(value)});
      }

      bool isArray = false;
      requireNapiStatus(napi_is_array(env, value, &isArray), "inspect an array result");
      if (isArray) {
        const auto length = arkJS.getArrayLength(value);
        TypedPlatformValue::Array result;
        result.reserve(length);
        for (uint32_t index = 0; index < length; ++index) {
          result.push_back(fromNapi(
              env, arkJS, arkJS.getArrayElement(value, index), depth + 1));
        }
        return TypedPlatformValue(std::move(result));
      }

      TypedPlatformValue::Record result;
      for (auto &[keyValue, propertyValue] : arkJS.getObjectProperties(value)) {
        result.emplace(
            arkJS.getString(keyValue),
            fromNapi(env, arkJS, propertyValue, depth + 1));
      }
      return TypedPlatformValue(std::move(result));
    }
    default:
      throw std::runtime_error(
          "Expo Modules cannot transport an ArkTS function or symbol result to JSI.");
  }
}

void throwNapiCallbackError(napi_env env, const char *message) noexcept {
  bool pending = false;
  if (napi_is_exception_pending(env, &pending) == napi_ok && pending) return;
  (void)napi_throw_error(env, "ERR_EXPO_CALLBACK", message);
}

napi_value handleNapiCallback(napi_env env, napi_callback_info info) noexcept {
  try {
    size_t count = 0;
    void *data = nullptr;
    requireNapiStatus(napi_get_cb_info(env, info, &count, nullptr, nullptr, &data), "read callback arity");
    std::vector<napi_value> arguments(count);
    requireNapiStatus(napi_get_cb_info(env, info, &count, arguments.data(), nullptr, &data), "read callback arguments");
    if (data == nullptr) throw std::runtime_error("The Expo callback has no native state.");

    ArkJS arkJS(env);
    TypedPlatformValue::Array values;
    values.reserve(count);
    // Copy while NAPI handles are valid before forwarding to the JS executor.
    for (size_t index = 0; index < count; ++index) {
      values.push_back(fromNapi(env, arkJS, arguments[index], 0));
    }

    (*static_cast<TypedPlatformValue::Callback *>(data))(std::move(values));
    return arkJS.getUndefined();
  } catch (const std::exception &error) {
    throwNapiCallbackError(env, error.what());
  } catch (...) {
    throwNapiCallbackError(env, "Expo Modules could not invoke the JavaScript callback.");
  }
  return nullptr;
}

napi_value createNapiCallback(napi_env env, TypedPlatformValue::Callback body) {
  auto data = std::make_unique<TypedPlatformValue::Callback>(std::move(body));
  napi_value callback = nullptr;
  requireNapiStatus(
      napi_create_function(env, "expoTypedCallback", NAPI_AUTO_LENGTH, handleNapiCallback, data.get(), &callback),
      "create a typed callback");
  requireNapiStatus(
      napi_add_finalizer(env, callback, data.get(), [](napi_env, void *data, void *) {
        delete static_cast<TypedPlatformValue::Callback *>(data);
      }, nullptr, nullptr),
      "retain a typed callback");

  (void)data.release();
  return callback;
}

jsi::Value toJSI(jsi::Runtime &runtime, TypedPlatformValue value) {
  return std::visit(
      [&](auto &&stored) -> jsi::Value {
        using Value = std::decay_t<decltype(stored)>;
        if constexpr (std::is_same_v<Value, UndefinedValue>) {
          return jsi::Value::undefined();
        } else if constexpr (std::is_same_v<Value, NullValue>) {
          return jsi::Value(nullptr);
        } else if constexpr (std::is_same_v<Value, bool>) {
          return jsi::Value(stored);
        } else if constexpr (std::is_same_v<Value, double>) {
          return jsi::Value(stored);
        } else if constexpr (std::is_same_v<Value, std::string>) {
          return jsi::Value(jsi::String::createFromUtf8(runtime, stored));
        } else if constexpr (std::is_same_v<Value, BigIntValue>) {
          return runtime.global().getPropertyAsFunction(runtime, "BigInt")
              .call(runtime, jsi::String::createFromUtf8(runtime, stored.decimal));
        } else if constexpr (std::is_same_v<Value, ArkTSErrorValue>) {
          CodedJSError error(runtime, CodedError(std::move(stored.code), std::move(stored.message), std::move(stored.path), codedCauseFromArkTS(stored.cause)));

          return jsi::Value(runtime, error.value());
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Array>) {
          jsi::Array result(runtime, stored.size());
          for (size_t index = 0; index < stored.size(); ++index) {
            result.setValueAtIndex(runtime, index, toJSI(runtime, std::move(stored[index])));
          }
          return jsi::Value(std::move(result));
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Record>) {
          jsi::Object result(runtime);
          for (auto &[key, item] : stored) {
            expo::common::defineRecordProperty(
                runtime,
                result,
                jsi::String::createFromUtf8(runtime, key),
                toJSI(runtime, std::move(item)));
          }
          return jsi::Value(std::move(result));
        } else if constexpr (std::is_same_v<Value, ArrayBufferValue>) {
          return jsi::Value(jsi::ArrayBuffer(
              runtime,
              std::make_shared<VectorMutableBuffer>(std::move(stored.bytes))));
        } else if constexpr (std::is_same_v<Value, TypedArrayValue>) {
          const auto &spec = typedArraySpec(stored.kind);
          auto arrayBuffer = jsi::ArrayBuffer(
              runtime,
              std::make_shared<VectorMutableBuffer>(std::move(stored.bytes)));
          auto constructor = runtime.global().getPropertyAsFunction(
              runtime, spec.constructorName);
          return constructor.callAsConstructor(runtime, std::move(arrayBuffer));
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Callback>) {
          throw std::runtime_error(
              "Expo Modules cannot return an ArkTS callback through the synchronous bridge.");
        }
      },
      std::move(value.storage));
}

class AsyncSettlementState final {
public:
  AsyncSettlementState(
      const std::shared_ptr<react::Promise> &promise,
      const std::shared_ptr<react::CallInvoker> &invoker)
      : promise_(promise),
        invoker_(invoker),
        retention_(
            [weak = std::weak_ptr<react::Promise>(promise)]() {
              if (auto promise = weak.lock()) {
                // allowRelease is synchronized and does not touch JSI.
                promise->allowRelease();
              }
            }) {}

  void resolve(TypedPlatformValue value) noexcept {
    settle(false, std::move(value));
  }

  void reject(TypedPlatformValue value) noexcept {
    settle(true, std::move(value));
  }

  void reject(std::string message) noexcept {
    reject(TypedPlatformValue(std::move(message)));
  }

private:
  void settle(bool rejected, TypedPlatformValue value) noexcept {
    if (!settlement_.trySettle()) {
      return;
    }

    auto release = retention_.transferToDelivery();
    try {
      auto invoker = invoker_.lock();
      if (!invoker) {
        release->release();
        return;
      }

      auto payload = std::make_shared<TypedPlatformValue>(std::move(value));
      auto weak = promise_;
      auto delivery = std::make_shared<ScheduledCallbackGuard>(release);

      invoker->invokeAsync(
          [weak,
           release,
           delivery = std::move(delivery),
           payload = std::move(payload),
           rejected](jsi::Runtime &runtime) mutable {
            delivery->markDelivered();

            auto promise = weak.lock();
            if (promise) {
              try {
                auto result = toJSI(runtime, std::move(*payload));
                if (rejected) {
                  promise->reject_.call(runtime, result);
                } else {
                  promise->resolve(result);
                }
              } catch (const std::exception &error) {
                try {
                  promise->reject(
                      "Expo Modules could not convert the ArkTS Promise settlement: " + std::string(error.what()));
                } catch (...) {
                }
              } catch (...) {
                try {
                  promise->reject(
                      "Expo Modules could not convert the ArkTS Promise settlement.");
                } catch (...) {
                }
              }
            }

            release->release();
          });
    } catch (...) {
      // Release retention if dispatch admission fails.
      release->release();
    }
  }

  std::weak_ptr<react::Promise> promise_;
  std::weak_ptr<react::CallInvoker> invoker_;
  AsyncSettlementLifetime retention_;
  PromiseSettlementState settlement_;
};

// napi_delete_reference must run on the creation thread; discarded tasks have
// no cleanup hook, so the reference is intentionally leaked in that case.
class DeferredNapiRefRelease final {
public:
  explicit DeferredNapiRefRelease(NapiRef ref)
      : reference_(new NapiRef(std::move(ref))) {}

  ~DeferredNapiRefRelease() noexcept = default;

  void releaseOnOwnerThread() noexcept {
    auto *reference = reference_.exchange(nullptr, std::memory_order_acq_rel);
    delete reference;
  }

private:
  std::atomic<NapiRef *> reference_;
};

struct NapiSettlementCallbackData final {
  std::shared_ptr<AsyncSettlementState> state;
  bool rejected;
};

napi_value handleNapiSettlement(napi_env env, napi_callback_info info) noexcept {
  size_t argumentCount = 1;
  napi_value argument = nullptr;
  void *rawData = nullptr;
  if (napi_get_cb_info(
          env,
          info,
          &argumentCount,
          &argument,
          nullptr,
          &rawData)
          != napi_ok
      || rawData == nullptr) {
    return nullptr;
  }
  auto *data = static_cast<NapiSettlementCallbackData *>(rawData);
  try {
    ArkJS arkJS(env);
    if (data->rejected && argumentCount > 0) {
      bool isError = false;
      if (napi_is_error(env, argument, &isError) == napi_ok && isError) {
        data->state->reject(TypedPlatformValue(
            readNapiErrorValue(
                env,
                argument,
                "An ArkTS Expo module Promise rejected.")));
        return arkJS.getUndefined();
      }
    }

    auto value = argumentCount == 0
                   ? TypedPlatformValue(UndefinedValue{})
                   : fromNapi(env, arkJS, argument, 0);
    if (data->rejected) {
      data->state->reject(std::move(value));
    } else {
      data->state->resolve(std::move(value));
    }
    return arkJS.getUndefined();
  } catch (const std::exception &error) {
    data->state->reject(
        "Expo Modules could not read the ArkTS Promise settlement: " + std::string(error.what()));
  } catch (...) {
    data->state->reject(
        "Expo Modules could not read the ArkTS Promise settlement.");
  }
  napi_value undefinedValue = nullptr;
  (void)napi_get_undefined(env, &undefinedValue);

  return undefinedValue;
}

napi_value createNapiSettlementCallback(
    napi_env env,
    const std::shared_ptr<AsyncSettlementState> &state,
    bool rejected) {
  auto data = std::make_unique<NapiSettlementCallbackData>(
      NapiSettlementCallbackData{state, rejected});
  napi_value callback = nullptr;
  requireNapiStatus(
      napi_create_function(
          env,
          rejected ? "rejectExpoTypedPromise" : "resolveExpoTypedPromise",
          NAPI_AUTO_LENGTH,
          handleNapiSettlement,
          data.get(),
          &callback),
      "create a Promise settlement callback");
  requireNapiStatus(
      napi_add_finalizer(
          env,
          callback,
          data.get(),
          [](napi_env, void *rawData, void *) {
            delete static_cast<NapiSettlementCallbackData *>(rawData);
          },
          nullptr,
          nullptr),
      "retain a Promise settlement callback");
  (void)data.release();

  return callback;
}

void attachNapiPromise(
    napi_env env,
    ArkJS &arkJS,
    napi_value value,
    const std::shared_ptr<AsyncSettlementState> &state) {
  bool isPromise = false;
  requireNapiStatus(
      napi_is_promise(env, value, &isPromise),
      "inspect an ArkTS Promise");
  if (!isPromise) {
    throw std::runtime_error("The ArkTS method did not return a Promise.");
  }

  auto onFulfilled = createNapiSettlementCallback(env, state, false);
  auto onRejected = createNapiSettlementCallback(env, state, true);
  auto chainedPromise = arkJS.getObject(value).call("then", {onFulfilled});
  arkJS.getObject(chainedPromise).call("catch", {onRejected});
}

}  // namespace

class SynchronousBinaryWriteBack::Impl final {
public:
  explicit Impl(jsi::Runtime &runtime) : runtime(runtime) {}

  void add(const jsi::Value &argument) {
    auto range = writableBinaryRange(runtime, argument);
    targets.push_back({jsi::Value(runtime, argument), std::move(range), nullptr});
  }

  void prepare(SynchronousBinarySnapshots &snapshots) {
    for (auto &target : targets) {
      target.snapshot = snapshots.get(runtime, target.range.buffer, target.range.offset, target.range.length);
      target.snapshot->writable = true;
    }
  }

  void commit(const RuntimeContext &context) {
    if (!completed) {
      throw CodedError("ERR_WRITABLE_ARGUMENT", "The synchronous binary call did not complete.");
    }

    // Finish all JS property reads before obtaining any writable pointer.
    // A getter on a later view must not detach an already acquired pointer.
    for (const auto &target : targets) {
      const auto current = writableBinaryRange(runtime, target.argument);
      if (current.offset != target.range.offset || current.length != target.range.length || !jsi::Object::strictEquals(runtime, current.buffer, target.range.buffer)) {
        throw CodedError("ERR_WRITABLE_ARGUMENT", "A writable argument changed its storage during the call.");
      }
    }
    if (!context.isAlive() || !context.isAcceptingTasks()) {
      throw CodedError("ERR_WRITABLE_ARGUMENT", "The runtime became unavailable before binary write-back.");
    }

    std::vector<uint8_t *> destinations;
    destinations.reserve(targets.size());
    for (const auto &target : targets) {
      auto buffer = target.range.buffer.getArrayBuffer(runtime);
      const auto size = buffer.size(runtime);
      if (target.range.offset > size || target.range.length > size - target.range.offset) {
        throw CodedError("ERR_WRITABLE_ARGUMENT", "A writable backing buffer was detached or resized.");
      }
      destinations.push_back(target.range.length == 0 ? nullptr : buffer.data(runtime) + target.range.offset);
    }
    // Aliased targets refer to the same native snapshot, so overlapping bytes
    // agree by construction. Commit only the explicitly writable view ranges.
    for (size_t index = 0; index < targets.size(); ++index) {
      const auto &target = targets[index];
      if (target.range.length > 0) {
        std::memcpy(destinations[index],
                    target.snapshot->bytes.data() + target.range.offset - target.snapshot->offset,
                    target.range.length);
      }
    }
    completed = false;
  }

  bool completed = false;

private:
  struct Target {
    jsi::Value argument;
    WritableBinaryRange range;
    std::shared_ptr<SynchronousBinarySnapshot> snapshot;
  };

  jsi::Runtime &runtime;
  std::vector<Target> targets;
};

SynchronousBinaryWriteBack::SynchronousBinaryWriteBack(jsi::Runtime &runtime)
    : impl_(std::make_unique<Impl>(runtime)) {}

SynchronousBinaryWriteBack::~SynchronousBinaryWriteBack() = default;

void SynchronousBinaryWriteBack::add(const jsi::Value &argument) {
  impl_->add(argument);
}

void SynchronousBinaryWriteBack::commit(const RuntimeContext &context) {
  impl_->commit(context);
}

class ArkTSTypedBridge::Impl final {
public:
  explicit Impl(const rnoh::ArkTSTurboModule::Context &context)
      : env_(context.env),
        instanceRef_(context.arkTSTurboModuleInstanceRef),
        turboModuleThread_(context.turboModuleThread),
        taskExecutor_(context.taskExecutor),
        jsInvoker_(context.jsInvoker) {}

  ~Impl() noexcept {
    if (!instanceRef_) {
      return;
    }

    try {
      auto deferred = std::make_shared<DeferredNapiRefRelease>(std::move(instanceRef_));
      if (!taskExecutor_) {
        return;
      }
      if (taskExecutor_->isOnTaskThread(turboModuleThread_)) {
        deferred->releaseOnOwnerThread();
        return;
      }

      taskExecutor_->runTask(
          turboModuleThread_,
          [deferred = std::move(deferred)]() noexcept {
            deferred->releaseOnOwnerThread();
          });
    } catch (...) {
      // Failed admission leaves the reference allocated for thread safety.
    }
  }

  jsi::Value call(
      jsi::Runtime &runtime,
      const std::string &methodName,
      const jsi::Value *arguments,
      size_t argumentCount,
      SynchronousBinaryWriteBack::Impl *writeBack) {
    if (!instanceRef_) {
      throw std::runtime_error("Expo Modules Core has no ArkTS TurboModule instance.");
    }

    SynchronousBinarySnapshots snapshots;
    if (writeBack) {
      writeBack->prepare(snapshots);
    }
    std::vector<TypedPlatformValue> typedArguments;
    typedArguments.reserve(argumentCount);
    for (size_t index = 0; index < argumentCount; ++index) {
      typedArguments.push_back(fromJSI(runtime, arguments[index], 0, &snapshots));
    }
    snapshots.materialize(runtime);

    TypedPlatformValue result(UndefinedValue{});
    napi_status writableStatus = napi_ok;
    runRnohSyncTask(
        *taskExecutor_,
        turboModuleThread_,
        [this, &methodName, &typedArguments, &result, &writableStatus]() mutable {
          ArkJS arkJS(env_);
          SynchronousNapiBuffers buffers(env_);
          std::vector<napi_value> napiArguments;
          napiArguments.reserve(typedArguments.size());
          for (auto &argument : typedArguments) {
            napiArguments.push_back(toNapi(env_, arkJS, std::move(argument), &buffers));
          }

          auto instance = arkJS.getReferenceValue(instanceRef_);
          auto napiResult = callNapiMethod(
              env_, instance, methodName, napiArguments);
          result = fromNapi(env_, arkJS, napiResult, 0);
          writableStatus = buffers.finish();
        });

    auto value = toJSI(runtime, std::move(result));
    // Let the caller decode the result even if closing the writable scope
    // failed. Its commit failure then rolls back any returned SharedObjects.
    if (writeBack) {
      writeBack->completed = writableStatus == napi_ok;
    }
    return value;
  }

  jsi::Value callAsync(
      jsi::Runtime &runtime,
      const std::string &methodName,
      const jsi::Value *arguments,
      size_t argumentCount) {
    if (!instanceRef_) {
      throw std::runtime_error("Expo Modules Core has no ArkTS TurboModule instance.");
    }
    if (!taskExecutor_ || !jsInvoker_) {
      throw std::runtime_error(
          "Expo Modules Core cannot schedule an ArkTS Promise without its runtime executors.");
    }

    std::vector<TypedPlatformValue> typedArguments;
    typedArguments.reserve(argumentCount);
    for (size_t index = 0; index < argumentCount; ++index) {
      typedArguments.push_back(fromJSI(runtime, arguments[index], 0));
    }

    // Copy the reference in the synchronous Promise executor for thread-safe release.
    return react::createPromiseAsJSIValue(
        runtime,
        [this,
         methodName,
         typedArguments = std::move(typedArguments)](
            jsi::Runtime &setupRuntime,
            std::shared_ptr<react::Promise> promise) mutable {
          auto context = RuntimeInstaller::installedContext(setupRuntime);
          if (!context) {
            throw CodedError("ERR_RUNTIME_DESTROYED", "Cannot retain an ArkTS Promise without an active Expo runtime.");
          }
          context->retainLongLivedObject(promise);
          std::shared_ptr<AsyncSettlementState> settlement;
          try {
            settlement = std::make_shared<AsyncSettlementState>(
                promise, jsInvoker_);
            auto instanceRef = instanceRef_;
            auto droppedInvocation = std::make_shared<OneShotReleaseState>(
                [settlement]() noexcept {
                  settlement->reject(
                      "Expo Modules ArkTS executor discarded the Promise invocation.");
                });
            auto delivery = std::make_shared<ScheduledCallbackGuard>(droppedInvocation);
            taskExecutor_->runTask(
                turboModuleThread_,
                [env = env_,
                 instanceRef = std::move(instanceRef),
                 methodName = std::move(methodName),
                 typedArguments = std::move(typedArguments),
                 settlement,
                 delivery = std::move(delivery)]() mutable {
                  delivery->markDelivered();
                  try {
                    ArkJS arkJS(env);
                    std::vector<napi_value> napiArguments;
                    napiArguments.reserve(typedArguments.size());
                    for (auto &argument : typedArguments) {
                      napiArguments.push_back(
                          toNapi(env, arkJS, std::move(argument)));
                    }
                    auto instance = arkJS.getReferenceValue(instanceRef);
                    auto result = callNapiMethod(
                        env, instance, methodName, napiArguments);
                    attachNapiPromise(env, arkJS, result, settlement);
                  } catch (const CodedError &error) {
                    settlement->reject(TypedPlatformValue(
                        arkTSErrorFromCodedError(error)));
                  } catch (const std::exception &error) {
                    settlement->reject(
                        "Expo Modules could not invoke the ArkTS Promise: " + std::string(error.what()));
                  } catch (...) {
                    settlement->reject(
                        "Expo Modules could not invoke the ArkTS Promise.");
                  }
                });
          } catch (const std::exception &error) {
            if (settlement) {
              settlement->reject(
                  "Expo Modules could not schedule the ArkTS Promise: " + std::string(error.what()));
            } else {
              try {
                promise->reject(
                    "Expo Modules could not retain the ArkTS Promise settlement: " + std::string(error.what()));
              } catch (...) {
              }
              promise->allowRelease();
            }
          } catch (...) {
            if (settlement) {
              settlement->reject(
                  "Expo Modules could not schedule the ArkTS Promise.");
            } else {
              try {
                promise->reject(
                    "Expo Modules could not retain the ArkTS Promise settlement.");
              } catch (...) {
              }
              promise->allowRelease();
            }
          }
        });
  }

private:
  napi_env env_;
  NapiRef instanceRef_;
  rnoh::TaskThread turboModuleThread_;
  rnoh::TaskExecutor::Shared taskExecutor_;
  std::shared_ptr<react::CallInvoker> jsInvoker_;
};

ArkTSTypedBridge::ArkTSTypedBridge(
    const rnoh::ArkTSTurboModule::Context &context)
    : impl_(std::make_unique<Impl>(context)) {}

ArkTSTypedBridge::~ArkTSTypedBridge() noexcept = default;

jsi::Value ArkTSTypedBridge::call(
    jsi::Runtime &runtime,
    const std::string &methodName,
    const jsi::Value *arguments,
    size_t argumentCount,
    SynchronousBinaryWriteBack *writeBack) {
  return impl_->call(runtime, methodName, arguments, argumentCount, writeBack ? writeBack->impl_.get() : nullptr);
}

jsi::Value ArkTSTypedBridge::callAsync(
    jsi::Runtime &runtime,
    const std::string &methodName,
    const jsi::Value *arguments,
    size_t argumentCount) {
  return impl_->callAsync(runtime, methodName, arguments, argumentCount);
}

}  // namespace expo::harmony
