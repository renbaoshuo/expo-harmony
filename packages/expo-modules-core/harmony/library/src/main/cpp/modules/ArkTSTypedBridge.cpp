#include "ArkTSTypedBridge.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <map>
#include <optional>
#include <stdexcept>
#include <utility>
#include <variant>
#include <vector>

#include <ReactCommon/TurboModuleUtils.h>
#include <RNOH/ArkJS.h>
#include <react/bridging/LongLivedObject.h>

#include "api/internal/AsyncTaskLifecycle.h"
#include "api/internal/PromiseSettlementState.h"
#include "common/JSI/JSIUtils.h"
#include "errors/CodedError.h"

namespace jsi = facebook::jsi;
namespace react = facebook::react;

namespace expo::harmony {
namespace {

constexpr size_t kMaximumTransportDepth = 64;
constexpr size_t kMaximumErrorCauseDepth = 4;

struct UndefinedValue final {};

struct NullValue final {};

struct ArrayBufferValue final {
  std::vector<uint8_t> bytes;
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
};

struct TypedPlatformValue final {
  using Array = std::vector<TypedPlatformValue>;
  using Record = std::map<std::string, TypedPlatformValue>;
  using Callback = ArkJS::IntermediaryCallback;

  using Storage = std::variant<
      UndefinedValue,
      NullValue,
      bool,
      double,
      std::string,
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
            env, value, bytes.data(), bytes.size(), &copied) != napi_ok) {
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
    std::string fallbackMessage,
    size_t depth = 0) {
  ArkTSErrorValue result{
      readNapiStringProperty(env, value, "code").value_or("ERR_ARKTS_MODULE"),
      readNapiStringProperty(env, value, "message").value_or(
          std::move(fallbackMessage)),
      readNapiStringProperty(env, value, "path"),
      nullptr};

  if (depth >= kMaximumErrorCauseDepth) {
    return result;
  }

  napi_value cause = nullptr;
  napi_valuetype causeType = napi_undefined;
  if (napi_get_named_property(env, value, "cause", &cause) == napi_ok &&
      cause != nullptr &&
      napi_typeof(env, cause, &causeType) == napi_ok &&
      (causeType == napi_object || causeType == napi_function)) {
    result.cause = std::make_shared<ArkTSErrorValue>(readNapiErrorValue(
        env,
        cause,
        "An ArkTS Expo module error was caused by another error.",
        depth + 1));
  }

  return result;
}

std::shared_ptr<const CodedError> codedCauseFromArkTS(
    const std::shared_ptr<ArkTSErrorValue> &cause) {
  if (!cause) {
    return nullptr;
  }
  return std::make_shared<CodedError>(
      cause->code,
      cause->message,
      cause->path,
      codedCauseFromArkTS(cause->cause));
}

CodedError codedErrorFromArkTS(ArkTSErrorValue error) {
  return CodedError(
      std::move(error.code),
      std::move(error.message),
      std::move(error.path),
      codedCauseFromArkTS(error.cause));
}

ArkTSErrorValue arkTSErrorFromCodedError(
    const CodedError &error,
    size_t depth = 0) {
  std::shared_ptr<ArkTSErrorValue> cause;
  if (error.cause() && depth < kMaximumErrorCauseDepth) {
    cause = std::make_shared<ArkTSErrorValue>(
        arkTSErrorFromCodedError(*error.cause(), depth + 1));
  }
  return ArkTSErrorValue{
      error.code(),
      error.what(),
      error.path(),
      std::move(cause)};
}

[[noreturn]] void throwNapiMethodFailure(
    napi_env env,
    napi_status status,
    const std::string &methodName) {
  bool exceptionPending = false;
  if (napi_is_exception_pending(env, &exceptionPending) == napi_ok &&
      exceptionPending) {
    napi_value exception = nullptr;
    if (napi_get_and_clear_last_exception(env, &exception) == napi_ok &&
        exception != nullptr) {
      throw codedErrorFromArkTS(readNapiErrorValue(
          env,
          exception,
          "ArkTS Expo method '" + methodName + "' threw an exception."));
    }
  }

  const napi_extended_error_info *errorInfo = nullptr;
  std::string message = "Expo Modules could not invoke ArkTS method '" +
      methodName + "' (napi_status=" +
      std::to_string(static_cast<int>(status)) + ").";
  if (napi_get_last_error_info(env, &errorInfo) == napi_ok &&
      errorInfo != nullptr && errorInfo->error_message != nullptr) {
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
  if (napi_is_exception_pending(env, &exceptionPending) != napi_ok ||
      exceptionPending) {
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

TypedArrayValue copyTypedArray(
    jsi::Runtime &runtime,
    const jsi::Object &object,
    NumericTypedArrayKind kind) {
  auto bufferValue = object.getProperty(runtime, "buffer");
  auto offsetValue = object.getProperty(runtime, "byteOffset");
  auto lengthValue = object.getProperty(runtime, "byteLength");
  if (!bufferValue.isObject() || !bufferValue.getObject(runtime).isArrayBuffer(runtime) || !offsetValue.isNumber() || !lengthValue.isNumber()) {
    throw std::runtime_error("TypedArray has an invalid backing buffer.");
  }

  const auto offsetNumber = offsetValue.getNumber();
  const auto lengthNumber = lengthValue.getNumber();
  if (!std::isfinite(offsetNumber) || !std::isfinite(lengthNumber) || offsetNumber < 0 || lengthNumber < 0 || std::trunc(offsetNumber) != offsetNumber || std::trunc(lengthNumber) != lengthNumber) {
    throw std::runtime_error("TypedArray has an invalid byte range.");
  }

  auto buffer = bufferValue.getObject(runtime).getArrayBuffer(runtime);
  const auto offset = static_cast<size_t>(offsetNumber);
  const auto length = static_cast<size_t>(lengthNumber);
  if (offset > buffer.size(runtime) || length > buffer.size(runtime) - offset) {
    throw std::runtime_error("TypedArray byte range exceeds its backing buffer.");
  }
  const auto &spec = typedArraySpec(kind);
  if (length % spec.elementSize != 0) {
    throw std::runtime_error(
        "TypedArray byte length is not aligned to its element size.");
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
    const std::shared_ptr<react::CallInvoker> &jsInvoker,
    const jsi::Value &value,
    size_t depth) {
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
  if (!value.isObject()) {
    throw std::runtime_error("Expo Modules cannot transport a symbol or bigint to ArkTS.");
  }

  auto object = value.getObject(runtime);
  if (object.isFunction(runtime)) {
    auto intermediary = rnoh::ArkTSTurboModule::convertJSIValuesToIntermediaryValues(
        runtime, jsInvoker, &value, 1);
    if (intermediary.size() != 1 || !std::holds_alternative<ArkJS::IntermediaryCallback>(intermediary.front())) {
      throw std::runtime_error("RNOH could not retain the JavaScript callback.");
    }
    return TypedPlatformValue(
        std::get<ArkJS::IntermediaryCallback>(std::move(intermediary.front())));
  }
  if (object.isArrayBuffer(runtime)) {
    return TypedPlatformValue(ArrayBufferValue{copyArrayBuffer(runtime, object)});
  }
  if (auto kind = typedArrayKind(runtime, object)) {
    return TypedPlatformValue(copyTypedArray(runtime, object, *kind));
  }
  if (object.isArray(runtime)) {
    auto array = object.getArray(runtime);
    TypedPlatformValue::Array result;
    result.reserve(array.size(runtime));
    for (size_t index = 0; index < array.size(runtime); ++index) {
      auto element = array.getValueAtIndex(runtime, index);
      result.push_back(fromJSI(runtime, jsInvoker, element, depth + 1));
    }
    return TypedPlatformValue(std::move(result));
  }

  TypedPlatformValue::Record result;
  auto propertyNames = object.getPropertyNames(runtime);
  for (size_t index = 0; index < propertyNames.size(runtime); ++index) {
    auto keyValue = propertyNames.getValueAtIndex(runtime, index);
    if (!keyValue.isString()) {
      continue;
    }
    auto key = keyValue.getString(runtime).utf8(runtime);
    auto property = object.getProperty(runtime, key.c_str());
    result.emplace(
        std::move(key), fromJSI(runtime, jsInvoker, property, depth + 1));
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

napi_value toNapi(napi_env env, ArkJS &arkJS, TypedPlatformValue value) {
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
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Array>) {
          std::vector<napi_value> items;
          items.reserve(stored.size());
          for (auto &item : stored) {
            items.push_back(toNapi(env, arkJS, std::move(item)));
          }
          return arkJS.createArray(items);
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Record>) {
          auto builder = arkJS.createObjectBuilder();
          for (auto &[key, item] : stored) {
            builder.addProperty(key.c_str(), toNapi(env, arkJS, std::move(item)));
          }
          return builder.build();
        } else if constexpr (std::is_same_v<Value, ArrayBufferValue>) {
          return createNapiArrayBuffer(env, stored.bytes);
        } else if constexpr (std::is_same_v<Value, TypedArrayValue>) {
          const auto &spec = typedArraySpec(stored.kind);
          if (stored.length > std::numeric_limits<size_t>::max() / spec.elementSize ||
              stored.length * spec.elementSize != stored.bytes.size()) {
            throw std::runtime_error(
                "Expo Modules received inconsistent TypedArray storage.");
          }
          auto arrayBuffer = createNapiArrayBuffer(env, stored.bytes);
          napi_value result = nullptr;
          requireNapiStatus(
              napi_create_typedarray(
                  env,
                  spec.napiType,
                  stored.length,
                  arrayBuffer,
                  0,
                  &result),
              "create a TypedArray");
          return result;
        } else if constexpr (std::is_same_v<Value, TypedPlatformValue::Callback>) {
          return arkJS.convertIntermediaryValueToNapiValue(std::move(stored));
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
          "Expo Modules cannot transport an ArkTS function, symbol, or bigint result to JSI.");
  }
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
        } else if constexpr (std::is_same_v<Value, ArkTSErrorValue>) {
          CodedJSError error(runtime, codedErrorFromArkTS(std::move(stored)));
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
            expo::common::defineProperty(
                runtime,
                &result,
                key.c_str(),
                {.configurable = true,
                 .enumerable = true,
                 .writable = true,
                 .value = toJSI(runtime, std::move(item))});
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
      const std::shared_ptr<react::CallInvoker> &jsInvoker)
      : promise_(promise),
        jsInvoker_(jsInvoker),
        retentionRelease_(std::make_shared<OneShotReleaseState>(
            [weakPromise = std::weak_ptr<react::Promise>(promise)]() {
              if (auto retainedPromise = weakPromise.lock()) {
                // allowRelease is synchronized and does not touch JSI.
                retainedPromise->allowRelease();
              }
            })) {}

  ~AsyncSettlementState() noexcept {
    // Release retention when an ArkTS Promise is abandoned.
    retentionRelease_->release();
  }

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
    if (!settlementState_.trySettle()) {
      return;
    }
    try {
      auto jsInvoker = jsInvoker_.lock();
      if (!jsInvoker) {
        retentionRelease_->release();
        return;
      }
      auto transportedValue =
          std::make_shared<TypedPlatformValue>(std::move(value));
      auto weakPromise = promise_;
      auto retentionRelease = retentionRelease_;
      auto delivery = std::make_shared<ScheduledCallbackGuard>(retentionRelease);
      jsInvoker->invokeAsync(
          [weakPromise,
           retentionRelease = std::move(retentionRelease),
           delivery = std::move(delivery),
           transportedValue = std::move(transportedValue),
           rejected](jsi::Runtime &runtime) mutable {
            delivery->markDelivered();
            auto promise = weakPromise.lock();
            if (promise) {
              try {
                auto result = toJSI(runtime, std::move(*transportedValue));
                if (rejected) {
                  promise->reject_.call(runtime, result);
                } else {
                  promise->resolve(result);
                }
              } catch (const std::exception &error) {
                try {
                  promise->reject(
                      "Expo Modules could not convert the ArkTS Promise settlement: " +
                      std::string(error.what()));
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
            retentionRelease->release();
          });
    } catch (...) {
      // Release retention if dispatch admission fails.
      retentionRelease_->release();
    }
  }

  std::weak_ptr<react::Promise> promise_;
  std::weak_ptr<react::CallInvoker> jsInvoker_;
  std::shared_ptr<OneShotReleaseState> retentionRelease_;
  PromiseSettlementState settlementState_;
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
          &rawData) != napi_ok ||
      rawData == nullptr) {
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
        "Expo Modules could not read the ArkTS Promise settlement: " +
        std::string(error.what()));
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
      auto deferred =
          std::make_shared<DeferredNapiRefRelease>(std::move(instanceRef_));
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
      size_t argumentCount) {
    if (!instanceRef_) {
      throw std::runtime_error("Expo Modules Core has no ArkTS TurboModule instance.");
    }

    std::vector<TypedPlatformValue> typedArguments;
    typedArguments.reserve(argumentCount);
    for (size_t index = 0; index < argumentCount; ++index) {
      typedArguments.push_back(fromJSI(runtime, jsInvoker_, arguments[index], 0));
    }

    TypedPlatformValue result(UndefinedValue{});
    taskExecutor_->runSyncTask(
        turboModuleThread_,
        [this, &methodName, &typedArguments, &result]() mutable {
          ArkJS arkJS(env_);
          std::vector<napi_value> napiArguments;
          napiArguments.reserve(typedArguments.size());
          for (auto &argument : typedArguments) {
            napiArguments.push_back(toNapi(env_, arkJS, std::move(argument)));
          }
          auto instance = arkJS.getReferenceValue(instanceRef_);
          auto napiResult = callNapiMethod(
              env_, instance, methodName, napiArguments);
          result = fromNapi(env_, arkJS, napiResult, 0);
        });
    return toJSI(runtime, std::move(result));
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
      typedArguments.push_back(fromJSI(runtime, jsInvoker_, arguments[index], 0));
    }

    // Copy the reference in the synchronous Promise executor for thread-safe release.
    return react::createPromiseAsJSIValue(
        runtime,
        [this,
         methodName,
         typedArguments = std::move(typedArguments)](
            jsi::Runtime &setupRuntime,
            std::shared_ptr<react::Promise> promise) mutable {
          react::LongLivedObjectCollection::get(setupRuntime).add(promise);
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
            auto delivery =
                std::make_shared<ScheduledCallbackGuard>(droppedInvocation);
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
                        "Expo Modules could not invoke the ArkTS Promise: " +
                        std::string(error.what()));
                  } catch (...) {
                    settlement->reject(
                        "Expo Modules could not invoke the ArkTS Promise.");
                  }
                });
          } catch (const std::exception &error) {
            if (settlement) {
              settlement->reject(
                  "Expo Modules could not schedule the ArkTS Promise: " +
                  std::string(error.what()));
            } else {
              try {
                promise->reject(
                    "Expo Modules could not retain the ArkTS Promise settlement: " +
                    std::string(error.what()));
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
    size_t argumentCount) {
  return impl_->call(runtime, methodName, arguments, argumentCount);
}

jsi::Value ArkTSTypedBridge::callAsync(
    jsi::Runtime &runtime,
    const std::string &methodName,
    const jsi::Value *arguments,
    size_t argumentCount) {
  return impl_->callAsync(runtime, methodName, arguments, argumentCount);
}

}  // namespace expo::harmony
