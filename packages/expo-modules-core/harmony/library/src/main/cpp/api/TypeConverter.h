#pragma once

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cmath>
#include <concepts>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <list>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <tuple>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <variant>
#include <vector>

#include <jsi/jsi.h>

#include <common/SharedObject.h>

#include "api/JavaScriptValue.h"
#include "api/ModuleDefinition.h"
#include "api/NativeTypes.h"
#include "api/NativeValueParser.h"
#include "api/Promise.h"
#include "api/Worklets.h"
#include "errors/CodedError.h"
#include "objects/BridgeCodec.h"
#include "runtime/RuntimeContext.h"

namespace expo::harmony {

struct Undefined final {};

template <typename T>
class ValueOrUndefined final {
public:
  ValueOrUndefined() = default;

  ValueOrUndefined(T value) : value_(std::move(value)) {}

  bool isUndefined() const noexcept {
    return !value_.has_value();
  }

  const T &value() const {
    return value_.value();
  }

  T &value() {
    return value_.value();
  }

private:
  std::optional<T> value_;
};

template <typename T>
struct IsOptionalArgument : std::false_type {};

template <typename T>
struct IsOptionalArgument<std::optional<T>> : std::true_type {};

template <typename T>
struct IsOptionalArgument<ValueOrUndefined<T>> : std::true_type {};

template <typename... Arguments>
constexpr size_t requiredArgumentCount() {
  constexpr std::array<bool, sizeof...(Arguments)> optionalArguments{
      IsOptionalArgument<std::remove_cvref_t<Arguments>>::value...};
  size_t required = sizeof...(Arguments);
  while (required > 0 && optionalArguments[required - 1]) {
    --required;
  }
  return required;
}

template <typename... Alternatives>
using Either = std::variant<Alternatives...>;

struct URL final {
  std::string value;
};

struct URI final {
  std::string value;
};

struct Color final {
  uint32_t argb{0};
  std::optional<uint32_t> darkArgb;
  std::optional<uint32_t> highContrastLightArgb;
  std::optional<uint32_t> highContrastDarkArgb;
};

struct JSDate final {
  double millisecondsSinceEpoch{0};
};

struct Blob final {
  JavaScriptArrayBuffer buffer;
  size_t offset{0};
  size_t size{0};
  std::string type;
};

class ReadableArguments final {
public:
  ReadableArguments(
      std::shared_ptr<RuntimeContext> context,
      JavaScriptObject object,
      std::string path)
      : context_(std::move(context)),
        object_(std::move(object)),
        path_(std::move(path)) {}

  bool has(const std::string &key) const {
    return object_.hasProperty(key);
  }

  std::vector<std::string> keys() const {
    return object_.getPropertyNames();
  }

  const JavaScriptObject &object() const noexcept {
    return object_;
  }

  template <typename T>
  T get(const std::string &key) const;

  template <typename T>
  std::optional<T> getOptional(const std::string &key) const;

private:
  std::shared_ptr<RuntimeContext> context_;
  JavaScriptObject object_;
  std::string path_;
};

using EnumerableValue = std::variant<std::string, double>;

template <typename Enum>
struct EnumTraits;

template <typename Record>
struct RecordTraits;

template <typename Record, typename Field>
struct RecordField final {
  std::string key;
  Field Record::*member;
  bool required{false};
};

template <typename Record, typename Field>
RecordField<Record, Field> recordField(
    std::string key,
    Field Record::*member,
    bool required = false) {
  return {std::move(key), member, required};
}

template <typename Record, typename Field>
RecordField<Record, Field> requiredRecordField(
    std::string key,
    Field Record::*member) {
  return {std::move(key), member, true};
}

template <typename Record, typename Formatter>
struct FormattedRecord final {
  Record value;
  Formatter formatter;
};

template <typename Record, typename Formatter>
FormattedRecord<Record, std::decay_t<Formatter>> formatRecord(
    Record value,
    Formatter &&formatter) {
  return {std::move(value), std::forward<Formatter>(formatter)};
}

template <typename T>
concept ExpoRecord = requires {
  RecordTraits<T>::fields();
};

template <typename T>
concept ExpoEnumerable = std::is_enum_v<T> && requires {
  EnumTraits<T>::values();
};

inline std::string describeJSValue(
    facebook::jsi::Runtime &runtime,
    const facebook::jsi::Value &value) {
  if (value.isUndefined()) {
    return "undefined";
  }
  if (value.isNull()) {
    return "null";
  }
  if (value.isBool()) {
    return "boolean";
  }
  if (value.isNumber()) {
    return "number";
  }
  if (value.isString()) {
    return "string";
  }
  if (value.isSymbol()) {
    return "symbol";
  }
  if (value.isBigInt()) {
    return "bigint";
  }
  if (value.isObject()) {
    auto object = value.getObject(runtime);
    if (object.isFunction(runtime)) {
      return "function";
    }
    if (object.isArray(runtime)) {
      return "array";
    }
    if (object.isArrayBuffer(runtime)) {
      return "ArrayBuffer";
    }
    if (expo::isTypedArray(runtime, object)) {
      return object.getPropertyAsObject(runtime, "constructor")
          .getProperty(runtime, "name")
          .getString(runtime)
          .utf8(runtime);
    }
    return "object";
  }
  return "unknown";
}

[[noreturn]] inline void throwConversionError(
    facebook::jsi::Runtime &runtime,
    const std::string &path,
    const std::string &expected,
    const facebook::jsi::Value &actual) {
  throw CodedError(
      "ERR_INVALID_ARGUMENT",
      path + " expected " + expected + ", received " + describeJSValue(runtime, actual) + ".");
}

template <typename T, typename Enable = void>
struct TypeConverter;

template <typename T>
struct IsJavaScriptBound : std::false_type {};

template <>
struct IsJavaScriptBound<facebook::jsi::Value> : std::true_type {};

template <>
struct IsJavaScriptBound<facebook::jsi::Object> : std::true_type {};

template <>
struct IsJavaScriptBound<facebook::jsi::Function> : std::true_type {};

template <>
struct IsJavaScriptBound<facebook::jsi::ArrayBuffer> : std::true_type {};

template <>
struct IsJavaScriptBound<JavaScriptValue> : std::true_type {};

template <>
struct IsJavaScriptBound<JavaScriptObject> : std::true_type {};

template <>
struct IsJavaScriptBound<JavaScriptFunction> : std::true_type {};

template <>
struct IsJavaScriptBound<JavaScriptWeakObject> : std::true_type {};

template <>
struct IsJavaScriptBound<JavaScriptArrayBuffer> : std::true_type {};

template <>
struct IsJavaScriptBound<JavaScriptTypedArray> : std::true_type {};

template <>
struct IsJavaScriptBound<ReadableArguments> : std::true_type {};

template <>
struct IsJavaScriptBound<Blob> : std::true_type {};

template <typename Element, expo::TypedArrayKind Kind>
struct IsJavaScriptBound<ConcreteTypedArray<Element, Kind>> : std::true_type {};

template <typename T>
struct IsJavaScriptBound<std::optional<T>> : IsJavaScriptBound<T> {};

template <typename T>
struct IsJavaScriptBound<ValueOrUndefined<T>> : IsJavaScriptBound<T> {};

template <typename T>
struct IsJavaScriptBound<std::vector<T>> : IsJavaScriptBound<T> {};

template <typename T, size_t Size>
struct IsJavaScriptBound<std::array<T, Size>> : IsJavaScriptBound<T> {};

template <typename T>
struct IsJavaScriptBound<std::list<T>> : IsJavaScriptBound<T> {};

template <typename T>
struct IsJavaScriptBound<std::set<T>> : IsJavaScriptBound<T> {};

template <typename T>
struct IsJavaScriptBound<std::unordered_set<T>> : IsJavaScriptBound<T> {};

template <typename T>
struct IsJavaScriptBound<std::map<std::string, T>> : IsJavaScriptBound<T> {};

template <typename T>
struct IsJavaScriptBound<std::unordered_map<std::string, T>> : IsJavaScriptBound<T> {};

template <typename First, typename Second>
struct IsJavaScriptBound<std::pair<First, Second>>
    : std::bool_constant<
          IsJavaScriptBound<First>::value || IsJavaScriptBound<Second>::value> {};

template <typename... Alternatives>
struct IsJavaScriptBound<std::variant<Alternatives...>>
    : std::bool_constant<(IsJavaScriptBound<Alternatives>::value || ...)> {};

template <typename T>
inline constexpr bool isJavaScriptBound = IsJavaScriptBound<std::remove_cvref_t<T>>::value;

template <typename T>
T convertFromJS(
    const std::shared_ptr<RuntimeContext> &context,
    const facebook::jsi::Value &value,
    const std::string &path) {
  return TypeConverter<T>::fromJS(context, value, path);
}

template <typename T>
facebook::jsi::Value convertToJS(
    const std::shared_ptr<RuntimeContext> &context,
    T &&value) {
  return TypeConverter<std::remove_cvref_t<T>>::toJS(
      context, std::forward<T>(value));
}

template <>
struct TypeConverter<facebook::jsi::Value> {
  static facebook::jsi::Value fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &) {
    return facebook::jsi::Value(context->runtime(), value);
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value) {
    return facebook::jsi::Value(context->runtime(), value);
  }
};

template <>
struct TypeConverter<facebook::jsi::Object> {
  static facebook::jsi::Object fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isObject()) {
      throwConversionError(context->runtime(), path, "object", value);
    }
    return value.getObject(context->runtime());
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Object &value) {
    return facebook::jsi::Value(context->runtime(), value);
  }
};

template <>
struct TypeConverter<facebook::jsi::Function> {
  static facebook::jsi::Function fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto object = TypeConverter<facebook::jsi::Object>::fromJS(
        context, value, path);
    if (!object.isFunction(context->runtime())) {
      throwConversionError(context->runtime(), path, "function", value);
    }
    return object.getFunction(context->runtime());
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Function &value) {
    return facebook::jsi::Value(context->runtime(), value);
  }
};

template <>
struct TypeConverter<facebook::jsi::ArrayBuffer> {
  static facebook::jsi::ArrayBuffer fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto object = TypeConverter<facebook::jsi::Object>::fromJS(
        context, value, path);
    if (!object.isArrayBuffer(context->runtime())) {
      throwConversionError(context->runtime(), path, "ArrayBuffer", value);
    }
    return object.getArrayBuffer(context->runtime());
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::ArrayBuffer &value) {
    return facebook::jsi::Value(context->runtime(), value);
  }
};

template <>
struct TypeConverter<Undefined> {
  static Undefined fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isUndefined()) {
      throwConversionError(context->runtime(), path, "undefined", value);
    }
    return {};
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      Undefined) {
    return facebook::jsi::Value::undefined();
  }
};

template <>
struct TypeConverter<std::nullptr_t> {
  static std::nullptr_t fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isNull()) {
      throwConversionError(context->runtime(), path, "null", value);
    }
    return nullptr;
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      std::nullptr_t) {
    return facebook::jsi::Value(nullptr);
  }
};

template <>
struct TypeConverter<bool> {
  static bool fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isBool()) {
      throwConversionError(context->runtime(), path, "boolean", value);
    }
    return value.getBool();
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      bool value) {
    return facebook::jsi::Value(value);
  }
};

template <std::integral T>
  requires(!std::same_as<T, bool>)
struct TypeConverter<T> {
  static T fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isNumber()) {
      throwConversionError(context->runtime(), path, "integer", value);
    }
    auto number = value.getNumber();
    bool outOfRange = !std::isfinite(number) || std::trunc(number) != number;
    if constexpr (std::is_unsigned_v<T>) {
      // Converting max() to double rounds uint64_t::max() up to 2^64, so an
      // inclusive comparison against that rounded value would admit 2^64.
      const auto upperExclusive = std::ldexp(1.0, std::numeric_limits<T>::digits);
      outOfRange = outOfRange || number < 0 || number >= upperExclusive;
    } else {
      const auto upperExclusive = std::ldexp(1.0, std::numeric_limits<T>::digits);
      const auto lowerInclusive = -upperExclusive;
      outOfRange = outOfRange || number < lowerInclusive || number >= upperExclusive;
    }
    if (outOfRange) {
      throw CodedError(
          "ERR_INTEGER_OUT_OF_RANGE",
          path + " is outside the supported integer range.");
    }
    return static_cast<T>(number);
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      T value) {
    return facebook::jsi::Value(static_cast<double>(value));
  }
};

template <std::floating_point T>
struct TypeConverter<T> {
  static T fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isNumber()) {
      throwConversionError(context->runtime(), path, "number", value);
    }
    return static_cast<T>(value.getNumber());
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      T value) {
    return facebook::jsi::Value(static_cast<double>(value));
  }
};

template <ExpoEnumerable T>
struct TypeConverter<T> {
  static T fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    for (const auto &[nativeValue, rawValue] : EnumTraits<T>::values()) {
      auto matches = std::visit(
          [&](const auto &candidate) {
            using Candidate = std::decay_t<decltype(candidate)>;
            if constexpr (std::same_as<Candidate, std::string>) {
              return value.isString() && value.getString(runtime).utf8(runtime) == candidate;
            } else {
              return value.isNumber() && value.getNumber() == candidate;
            }
          },
          rawValue);
      if (matches) {
        return nativeValue;
      }
    }
    std::string expected;
    for (const auto &[nativeValue, rawValue] : EnumTraits<T>::values()) {
      (void)nativeValue;
      if (!expected.empty()) {
        expected += ", ";
      }
      expected += std::visit(
          [](const auto &candidate) -> std::string {
            using Candidate = std::decay_t<decltype(candidate)>;
            if constexpr (std::same_as<Candidate, std::string>) {
              return "'" + candidate + "'";
            } else {
              return std::to_string(candidate);
            }
          },
          rawValue);
    }
    throw CodedError(
        "ERR_ENUM_VALUE",
        path + " must be one of: " + expected + ".");
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      T value) {
    for (const auto &[nativeValue, rawValue] : EnumTraits<T>::values()) {
      if (nativeValue != value) {
        continue;
      }
      return std::visit(
          [&](const auto &candidate) -> facebook::jsi::Value {
            return convertToJS(context, candidate);
          },
          rawValue);
    }
    throw CodedError(
        "ERR_ENUM_VALUE", "Native enum value has no JavaScript representation.");
  }
};

template <>
struct TypeConverter<std::string> {
  static std::string fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isString()) {
      throwConversionError(context->runtime(), path, "string", value);
    }
    return value.getString(context->runtime()).utf8(context->runtime());
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::string &value) {
    return facebook::jsi::String::createFromUtf8(context->runtime(), value);
  }
};

template <>
struct TypeConverter<JavaScriptValue> {
  static JavaScriptValue fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &) {
    return JavaScriptValue(context, value);
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      const JavaScriptValue &value) {
    return value.get();
  }
};

template <>
struct TypeConverter<JavaScriptObject> {
  static JavaScriptObject fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isObject()) {
      throwConversionError(context->runtime(), path, "object", value);
    }
    return JavaScriptObject(context, value.getObject(context->runtime()));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const JavaScriptObject &value) {
    return value.get();
  }
};

template <>
struct TypeConverter<ReadableArguments> {
  static ReadableArguments fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    return ReadableArguments(
        context,
        TypeConverter<JavaScriptObject>::fromJS(context, value, path),
        path);
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      const ReadableArguments &value) {
    return value.object().get();
  }
};

template <>
struct TypeConverter<JavaScriptFunction> {
  static JavaScriptFunction fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isObject() || !value.getObject(context->runtime()).isFunction(context->runtime())) {
      throwConversionError(context->runtime(), path, "function", value);
    }
    return JavaScriptFunction(
        context, value.getObject(context->runtime()).getFunction(context->runtime()));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      const JavaScriptFunction &value) {
    return value.get();
  }
};

template <>
struct TypeConverter<JavaScriptWeakObject> {
  static JavaScriptWeakObject fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    return TypeConverter<JavaScriptObject>::fromJS(context, value, path).createWeak();
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      const JavaScriptWeakObject &value) {
    auto object = value.lock();
    return object
             ? facebook::jsi::Value(object->get())
             : facebook::jsi::Value::undefined();
  }
};

template <>
struct TypeConverter<JavaScriptArrayBuffer> {
  static JavaScriptArrayBuffer fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isObject() || !value.getObject(context->runtime()).isArrayBuffer(context->runtime())) {
      throwConversionError(context->runtime(), path, "ArrayBuffer", value);
    }
    return JavaScriptArrayBuffer(
        context, value.getObject(context->runtime()).getArrayBuffer(context->runtime()));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      const JavaScriptArrayBuffer &value) {
    return value.get();
  }
};

template <>
struct TypeConverter<JavaScriptTypedArray> {
  static JavaScriptTypedArray fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (!value.isObject() || !expo::isTypedArray(context->runtime(), value.getObject(context->runtime()))) {
      throwConversionError(context->runtime(), path, "TypedArray", value);
    }
    return JavaScriptTypedArray(context, value.getObject(context->runtime()));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      const JavaScriptTypedArray &value) {
    return value.get();
  }
};

template <>
struct TypeConverter<Serializable> {
  static Serializable fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    try {
      return Serializable(
          worklets::extractSerializableOrThrow(context->runtime(), value));
    } catch (const std::exception &error) {
      throw CodedError(
          "ERR_SERIALIZABLE_TYPE", path + " is not Serializable: " + error.what());
    }
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const Serializable &value) {
    return value.toJSValue(context->runtime());
  }
};

template <>
struct TypeConverter<Worklet> {
  static Worklet fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    try {
      return Worklet(
          worklets::extractSerializableOrThrow<worklets::SerializableWorklet>(
              context->runtime(), value));
    } catch (const std::exception &error) {
      throw CodedError(
          "ERR_WORKLET_TYPE", path + " is not a Worklet: " + error.what());
    }
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const Worklet &value) {
    return value.toJSValue(context->runtime());
  }
};

template <typename T>
struct TypeConverter<std::optional<T>> {
  static std::optional<T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (value.isNull() || value.isUndefined()) {
      return std::nullopt;
    }
    return convertFromJS<T>(context, value, path);
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::optional<T> &value) {
    return value ? convertToJS(context, *value) : facebook::jsi::Value(nullptr);
  }
};

template <typename Element, expo::TypedArrayKind Kind>
struct TypeConverter<ConcreteTypedArray<Element, Kind>> {
  using Array = ConcreteTypedArray<Element, Kind>;

  static Array fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto raw = TypeConverter<JavaScriptTypedArray>::fromJS(context, value, path);
    if (raw.kind() != Kind) {
      throw CodedError(
          "ERR_TYPED_ARRAY_KIND",
          path + " received an incompatible TypedArray element type.");
    }
    return Array(std::move(raw));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      const Array &value) {
    return value.raw().get();
  }
};

template <>
struct TypeConverter<NativeArrayBuffer> {
  static NativeArrayBuffer fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto source = TypeConverter<JavaScriptArrayBuffer>::fromJS(context, value, path);
    std::vector<uint8_t> bytes(source.size());
    source.readBytes(0, bytes.data(), bytes.size());
    return NativeArrayBuffer(std::move(bytes));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const NativeArrayBuffer &value) {
    auto storage = value.storage();
    return JavaScriptArrayBuffer::create(
               context,
               storage->data(),
               storage->size(),
               [storage = std::move(storage)]() {})
        .get();
  }
};

template <>
struct TypeConverter<std::vector<uint8_t>> {
  static std::vector<uint8_t> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto array = TypeConverter<Uint8Array>::fromJS(context, value, path);
    std::vector<uint8_t> bytes(array.size());
    array.raw().readBytes(0, bytes.data(), bytes.size());
    return bytes;
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::vector<uint8_t> &value) {
    auto &runtime = context->runtime();
    auto storage = std::make_shared<std::vector<uint8_t>>(value);
    auto buffer = JavaScriptArrayBuffer::create(context, storage->data(), storage->size(), [storage]() {});
    return runtime.global()
        .getPropertyAsFunction(runtime, "Uint8Array")
        .callAsConstructor(runtime, buffer.get());
  }
};

template <typename T>
struct TypeConverter<ValueOrUndefined<T>> {
  static ValueOrUndefined<T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (value.isUndefined()) {
      return {};
    }
    return ValueOrUndefined<T>(convertFromJS<T>(context, value, path));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const ValueOrUndefined<T> &value) {
    return value.isUndefined()
             ? facebook::jsi::Value::undefined()
             : convertToJS(context, value.value());
  }
};

template <typename T>
struct TypeConverter<std::vector<T>> {
  static std::vector<T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    if (!value.isObject() || !value.getObject(runtime).isArray(runtime)) {
      throwConversionError(runtime, path, "array", value);
    }
    auto array = value.getObject(runtime).getArray(runtime);
    std::vector<T> result;
    result.reserve(array.size(runtime));
    for (size_t index = 0; index < array.size(runtime); ++index) {
      result.push_back(convertFromJS<T>(
          context,
          array.getValueAtIndex(runtime, index),
          path + "[" + std::to_string(index) + "]"));
    }
    return result;
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::vector<T> &value) {
    auto &runtime = context->runtime();
    facebook::jsi::Array result(runtime, value.size());
    for (size_t index = 0; index < value.size(); ++index) {
      result.setValueAtIndex(runtime, index, convertToJS(context, value[index]));
    }
    return result;
  }
};

template <typename T, size_t Size>
struct TypeConverter<std::array<T, Size>> {
  static std::array<T, Size> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto vector = convertFromJS<std::vector<T>>(context, value, path);
    if (vector.size() != Size) {
      throw CodedError(
          "ERR_INVALID_ARRAY_LENGTH",
          path + " expected " + std::to_string(Size) + " entries, received " + std::to_string(vector.size()) + ".");
    }
    std::array<T, Size> result;
    std::move(vector.begin(), vector.end(), result.begin());
    return result;
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::array<T, Size> &value) {
    return convertToJS(context, std::vector<T>(value.begin(), value.end()));
  }
};

template <typename T>
struct TypeConverter<std::list<T>> {
  static std::list<T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto vector = convertFromJS<std::vector<T>>(context, value, path);
    return std::list<T>(
        std::make_move_iterator(vector.begin()), std::make_move_iterator(vector.end()));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::list<T> &value) {
    return convertToJS(context, std::vector<T>(value.begin(), value.end()));
  }
};

template <typename T>
struct TypeConverter<std::set<T>> {
  static std::set<T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto vector = convertFromJS<std::vector<T>>(context, value, path);
    return std::set<T>(
        std::make_move_iterator(vector.begin()), std::make_move_iterator(vector.end()));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::set<T> &value) {
    return convertToJS(context, std::vector<T>(value.begin(), value.end()));
  }
};

template <typename T>
struct TypeConverter<std::unordered_set<T>> {
  static std::unordered_set<T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto vector = convertFromJS<std::vector<T>>(context, value, path);
    return std::unordered_set<T>(
        std::make_move_iterator(vector.begin()), std::make_move_iterator(vector.end()));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::unordered_set<T> &value) {
    return convertToJS(context, std::vector<T>(value.begin(), value.end()));
  }
};

template <typename T>
struct TypeConverter<std::unordered_map<std::string, T>> {
  static std::unordered_map<std::string, T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    if (!value.isObject() || value.getObject(runtime).isArray(runtime)) {
      throwConversionError(runtime, path, "record", value);
    }
    auto object = value.getObject(runtime);
    auto names = object.getPropertyNames(runtime);
    std::unordered_map<std::string, T> result;
    for (size_t index = 0; index < names.size(runtime); ++index) {
      auto key = names.getValueAtIndex(runtime, index).getString(runtime).utf8(runtime);
      result.emplace(
          key,
          convertFromJS<T>(context, object.getProperty(runtime, key.c_str()), path + "." + key));
    }
    return result;
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::unordered_map<std::string, T> &value) {
    facebook::jsi::Object result(context->runtime());
    for (const auto &[key, item] : value) {
      result.setProperty(context->runtime(), key.c_str(), convertToJS(context, item));
    }
    return result;
  }
};

template <ExpoRecord T>
struct TypeConverter<T> {
  static T fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    if (!value.isObject() || value.getObject(runtime).isArray(runtime) || value.getObject(runtime).isFunction(runtime)) {
      throwConversionError(runtime, path, "record", value);
    }
    auto object = value.getObject(runtime);
    T result{};
    std::apply(
        [&](const auto &...field) {
          ([&]() {
            if (!object.hasProperty(runtime, field.key.c_str())) {
              if (field.required) {
                throw CodedError(
                    "ERR_REQUIRED_FIELD",
                    path + "." + field.key + " is required.");
              }
              return;
            }
            using Field = std::remove_cvref_t<decltype(result.*(field.member))>;
            result.*(field.member) = convertFromJS<Field>(
                context,
                object.getProperty(runtime, field.key.c_str()),
                path + "." + field.key);
          }(),
           ...);
        },
        RecordTraits<T>::fields());
    return result;
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const T &value) {
    facebook::jsi::Object result(context->runtime());
    std::apply(
        [&](const auto &...field) {
          (result.setProperty(
               context->runtime(),
               field.key.c_str(),
               convertToJS(context, value.*(field.member))),
           ...);
        },
        RecordTraits<T>::fields());
    return result;
  }
};

template <typename Record, typename Formatter>
struct TypeConverter<FormattedRecord<Record, Formatter>> {
  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const FormattedRecord<Record, Formatter> &value) {
    return value.formatter(context, value.value);
  }
};

template <typename T>
struct TypeConverter<std::map<std::string, T>> {
  static std::map<std::string, T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto unordered = convertFromJS<std::unordered_map<std::string, T>>(context, value, path);
    return std::map<std::string, T>(
        std::make_move_iterator(unordered.begin()),
        std::make_move_iterator(unordered.end()));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::map<std::string, T> &value) {
    facebook::jsi::Object result(context->runtime());
    for (const auto &[key, item] : value) {
      result.setProperty(context->runtime(), key.c_str(), convertToJS(context, item));
    }
    return result;
  }
};

template <typename First, typename Second>
struct TypeConverter<std::pair<First, Second>> {
  static std::pair<First, Second> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    if (!value.isObject() || !value.getObject(runtime).isArray(runtime) || value.getObject(runtime).getArray(runtime).size(runtime) != 2) {
      throwConversionError(runtime, path, "pair", value);
    }
    auto array = value.getObject(runtime).getArray(runtime);
    return {
        convertFromJS<First>(context, array.getValueAtIndex(runtime, 0), path + "[0]"),
        convertFromJS<Second>(context, array.getValueAtIndex(runtime, 1), path + "[1]")};
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::pair<First, Second> &value) {
    facebook::jsi::Array result(context->runtime(), 2);
    result.setValueAtIndex(context->runtime(), 0, convertToJS(context, value.first));
    result.setValueAtIndex(context->runtime(), 1, convertToJS(context, value.second));
    return result;
  }
};

template <typename... Alternatives>
struct TypeConverter<std::variant<Alternatives...>> {
  static std::variant<Alternatives...> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    return tryAlternative<0>(context, value, path, {});
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::variant<Alternatives...> &value) {
    return std::visit(
        [&context](const auto &item) { return convertToJS(context, item); }, value);
  }

private:
  template <size_t Index>
  static std::variant<Alternatives...> tryAlternative(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path,
      std::string errors) {
    if constexpr (Index == sizeof...(Alternatives)) {
      throw CodedError(
          "ERR_INVALID_ARGUMENT",
          path + " did not match any Either alternative: " + errors);
    } else {
      using Candidate = std::variant_alternative_t<Index, std::variant<Alternatives...>>;
      try {
        return std::variant<Alternatives...>(
            std::in_place_index<Index>, convertFromJS<Candidate>(context, value, path));
      } catch (const CodedError &error) {
        return tryAlternative<Index + 1>(
            context,
            value,
            path,
            errors + (errors.empty() ? "" : "; ") + error.what());
      }
    }
  }
};

template <typename Representation, typename Period>
struct TypeConverter<std::chrono::duration<Representation, Period>> {
  using Duration = std::chrono::duration<Representation, Period>;

  static Duration fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto seconds = convertFromJS<double>(context, value, path);
    return std::chrono::duration_cast<Duration>(
        std::chrono::duration<double>(seconds));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &,
      const Duration &value) {
    return facebook::jsi::Value(
        std::chrono::duration<double>(value).count());
  }
};

template <>
struct TypeConverter<std::filesystem::path> {
  static std::filesystem::path fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    return std::filesystem::path(convertFromJS<std::string>(context, value, path));
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::filesystem::path &value) {
    return convertToJS(context, value.string());
  }
};

template <>
struct TypeConverter<URL> {
  static URL fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto text = convertFromJS<std::string>(context, value, path);
    try {
      validateAbsoluteUrl(text);
    } catch (const std::invalid_argument &error) {
      throw CodedError(
          "ERR_INVALID_URL",
          path + " is not a valid absolute URL: " + error.what() + ".");
    }
    return {std::move(text)};
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const URL &value) {
    return convertToJS(context, value.value);
  }
};

template <>
struct TypeConverter<URI> {
  static URI fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto text = convertFromJS<std::string>(context, value, path);
    try {
      validateUri(text);
    } catch (const std::invalid_argument &error) {
      throw CodedError(
          "ERR_INVALID_URI",
          path + " is not a valid URI: " + error.what() + ".");
    }
    return {std::move(text)};
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const URI &value) {
    return convertToJS(context, value.value);
  }
};

template <>
struct TypeConverter<Color> {
  static uint32_t parseString(const std::string &text, const std::string &path) {
    try {
      return parseCssColor(text);
    } catch (const std::invalid_argument &error) {
      throw CodedError(
          "ERR_INVALID_COLOR",
          path + " is not a valid color: " + error.what() + ".");
    }
  }

  static uint32_t parseSingle(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    if (value.isNumber()) {
      auto number = value.getNumber();
      if (!std::isfinite(number) || std::trunc(number) != number || number < static_cast<double>(std::numeric_limits<int32_t>::lowest()) || number > static_cast<double>(std::numeric_limits<uint32_t>::max())) {
        throw CodedError("ERR_INVALID_COLOR", path + " is outside the ARGB range.");
      }
      return static_cast<uint32_t>(static_cast<int64_t>(number));
    }
    if (value.isString()) {
      return parseString(
          value.getString(context->runtime()).utf8(context->runtime()), path);
    }
    if (value.isObject() && value.getObject(context->runtime()).isArray(context->runtime())) {
      auto &runtime = context->runtime();
      auto array = value.getObject(runtime).getArray(runtime);
      const auto size = array.size(runtime);
      if (size != 3 && size != 4) {
        throw CodedError(
            "ERR_INVALID_COLOR",
            path + " color array must contain three or four normalized components.");
      }
      std::array<double, 4> components{};
      for (size_t index = 0; index < size; ++index) {
        components[index] = convertFromJS<double>(
            context,
            array.getValueAtIndex(runtime, index),
            path + "[" + std::to_string(index) + "]");
      }
      try {
        return packNormalizedColor(
            std::span<const double>(components.data(), size));
      } catch (const std::invalid_argument &error) {
        throw CodedError(
            "ERR_INVALID_COLOR",
            path + " is not a valid color array: " + error.what() + ".");
      }
    }
    throwConversionError(
        context->runtime(),
        path,
        "numeric ARGB, CSS color string, or normalized RGB(A) array",
        value);
  }

  static std::optional<Color> parseDynamic(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Object &object,
      const std::string &path) {
    auto &runtime = context->runtime();
    auto light = object.getProperty(runtime, "light");
    auto dark = object.getProperty(runtime, "dark");
    auto highContrastLight = object.getProperty(runtime, "highContrastLight");
    auto highContrastDark = object.getProperty(runtime, "highContrastDark");
    if (light.isUndefined() && dark.isUndefined() && highContrastLight.isUndefined() && highContrastDark.isUndefined()) {
      return std::nullopt;
    }
    if (light.isUndefined() || dark.isUndefined()) {
      throw CodedError(
          "ERR_INVALID_COLOR",
          path + " must define both light and dark colors.");
    }
    return Color{
        parseSingle(context, light, path + ".light"),
        parseSingle(context, dark, path + ".dark"),
        highContrastLight.isUndefined()
            ? std::nullopt
            : std::optional<uint32_t>(parseSingle(
                  context, highContrastLight, path + ".highContrastLight")),
        highContrastDark.isUndefined()
            ? std::nullopt
            : std::optional<uint32_t>(parseSingle(
                  context, highContrastDark, path + ".highContrastDark"))};
  }

  static Color fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    if (value.isObject() && !value.getObject(runtime).isArray(runtime)) {
      auto object = value.getObject(runtime);
      if (object.hasProperty(runtime, "semantic") || object.hasProperty(runtime, "resource_paths")) {
        throw CodedError(
            "ERR_INVALID_COLOR",
            path +
                " contains an unresolved platform color. On Harmony, "
                "React Native PlatformColor must resolve it to a color string first.");
      }
      auto dynamic = object.getProperty(runtime, "dynamic");
      if (!dynamic.isUndefined()) {
        if (!dynamic.isObject() || dynamic.getObject(runtime).isArray(runtime)) {
          throw CodedError(
              "ERR_INVALID_COLOR",
              path + ".dynamic must be an object with light and dark colors.");
        }
        if (auto parsed = parseDynamic(
                context,
                dynamic.getObject(runtime),
                path + ".dynamic")) {
          return *parsed;
        }
        throw CodedError(
            "ERR_INVALID_COLOR",
            path + ".dynamic must define light and dark colors.");
      }
      // Preserve the original Harmony shape while also accepting React
      // Native's { dynamic: { light, dark } } representation.
      if (auto parsed = parseDynamic(context, object, path)) {
        return *parsed;
      }
    }
    return Color{parseSingle(context, value, path), std::nullopt};
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const Color &value) {
    if (value.darkArgb) {
      facebook::jsi::Object result(context->runtime());
      result.setProperty(
          context->runtime(), "light", static_cast<double>(value.argb));
      result.setProperty(
          context->runtime(), "dark", static_cast<double>(*value.darkArgb));
      if (value.highContrastLightArgb) {
        result.setProperty(
            context->runtime(),
            "highContrastLight",
            static_cast<double>(*value.highContrastLightArgb));
      }
      if (value.highContrastDarkArgb) {
        result.setProperty(
            context->runtime(),
            "highContrastDark",
            static_cast<double>(*value.highContrastDarkArgb));
      }
      return result;
    }
    return convertToJS(context, value.argb);
  }
};

template <>
struct TypeConverter<JSDate> {
  static JSDate fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    if (value.isNumber()) {
      return {value.getNumber()};
    }
    auto dateConstructor = runtime.global().getPropertyAsFunction(runtime, "Date");
    facebook::jsi::Object object(runtime);
    if (value.isString()) {
      object = dateConstructor
                   .callAsConstructor(runtime, value.getString(runtime))
                   .getObject(runtime);
    } else if (value.isObject()) {
      object = value.getObject(runtime);
    } else {
      throwConversionError(
          runtime,
          path,
          "Date, ISO date string, or epoch milliseconds",
          value);
    }
    if (!object.instanceOf(runtime, dateConstructor)) {
      throwConversionError(runtime, path, "Date", value);
    }
    auto getTime = object.getProperty(runtime, "getTime");
    if (!getTime.isObject() || !getTime.getObject(runtime).isFunction(runtime)) {
      throwConversionError(runtime, path, "Date", value);
    }
    auto result = getTime.getObject(runtime).getFunction(runtime).callWithThis(runtime, object);
    auto milliseconds = convertFromJS<double>(context, result, path);
    if (!std::isfinite(milliseconds)) {
      throw CodedError("ERR_INVALID_DATE", path + " is not a valid date.");
    }
    return {milliseconds};
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const JSDate &value) {
    auto &runtime = context->runtime();
    return runtime.global()
        .getPropertyAsFunction(runtime, "Date")
        .callAsConstructor(runtime, value.millisecondsSinceEpoch);
  }
};

template <>
struct TypeConverter<Blob> {
  static Blob fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    if (!value.isObject()) {
      throwConversionError(runtime, path, "Blob-compatible object", value);
    }
    auto object = value.getObject(runtime);
    auto bufferValue = object.getProperty(runtime, "buffer");
    auto typeValue = object.getProperty(runtime, "type");
    auto offsetValue = object.getProperty(runtime, "offset");
    auto sizeValue = object.getProperty(runtime, "size");
    size_t baseOffset = 0;
    size_t availableSize = 0;
    JavaScriptArrayBuffer buffer = [&]() {
      if (bufferValue.isObject() && bufferValue.getObject(runtime).isArrayBuffer(runtime)) {
        auto result = TypeConverter<JavaScriptArrayBuffer>::fromJS(
            context, bufferValue, path + ".buffer");
        availableSize = result.size();
        return result;
      }
      if (bufferValue.isObject() && expo::isTypedArray(runtime, bufferValue.getObject(runtime))) {
        auto typedArray = JavaScriptTypedArray(context, bufferValue.getObject(runtime));
        baseOffset = typedArray.byteOffset();
        availableSize = typedArray.byteLength();
        return typedArray.buffer();
      }
      throwConversionError(runtime, path + ".buffer", "ArrayBuffer or TypedArray", bufferValue);
    }();
    auto relativeOffset = offsetValue.isUndefined()
                            ? size_t{0}
                            : convertFromJS<size_t>(context, offsetValue, path + ".offset");
    if (relativeOffset > availableSize) {
      throw CodedError("ERR_BUFFER_OUT_OF_BOUNDS", path + ".offset is out of bounds.");
    }
    auto offset = baseOffset + relativeOffset;
    auto size = sizeValue.isUndefined()
                  ? availableSize - relativeOffset
                  : convertFromJS<size_t>(context, sizeValue, path + ".size");
    if (offset > buffer.size() || size > availableSize - relativeOffset || size > buffer.size() - offset) {
      throw CodedError("ERR_BUFFER_OUT_OF_BOUNDS", path + " references bytes outside its buffer.");
    }
    return Blob{
        std::move(buffer),
        offset,
        size,
        typeValue.isUndefined()
            ? std::string{}
            : convertFromJS<std::string>(context, typeValue, path + ".type")};
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const Blob &value) {
    facebook::jsi::Object result(context->runtime());
    result.setProperty(context->runtime(), "buffer", value.buffer.get());
    result.setProperty(context->runtime(), "offset", static_cast<double>(value.offset));
    result.setProperty(context->runtime(), "size", static_cast<double>(value.size));
    result.setProperty(
        context->runtime(),
        "type",
        facebook::jsi::String::createFromUtf8(context->runtime(), value.type));
    return result;
  }
};

template <typename T>
  requires std::derived_from<T, NativeSharedObject>
struct TypeConverter<std::shared_ptr<T>> {
  static std::shared_ptr<T> fromJS(
      const std::shared_ptr<RuntimeContext> &context,
      const facebook::jsi::Value &value,
      const std::string &path) {
    auto &runtime = context->runtime();
    if (!value.isObject()) {
      throwConversionError(runtime, path, "SharedObject", value);
    }
    auto objectId = requireSharedObjectId(runtime, value, path);
    auto nativeObject = context->getNativeSharedObject(objectId);
    auto converted = std::dynamic_pointer_cast<T>(nativeObject);
    if (!converted) {
      throw CodedError(
          "ERR_SHARED_OBJECT_TYPE", path + " has an incompatible SharedObject type.");
    }
    return converted;
  }

  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      const std::shared_ptr<T> &value) {
    if (!value) {
      throw CodedError(
          "ERR_INVALID_SHARED_OBJECT",
          "A native SharedObject return value cannot be null.");
    }
    return context->materializeNativeSharedObject(
        std::static_pointer_cast<NativeSharedObject>(value));
  }
};

template <>
struct TypeConverter<SharedObjectResult> {
  static facebook::jsi::Value toJS(
      const std::shared_ptr<RuntimeContext> &context,
      SharedObjectResult value) {
    if (!value.object) {
      throw CodedError(
          "ERR_INVALID_SHARED_OBJECT", "SharedObject result contains a null native object.");
    }
    return context->materializeNativeSharedObject(
        std::move(value.moduleName),
        std::move(value.className),
        std::move(value.object));
  }
};

class ArgumentReader final {
public:
  explicit ArgumentReader(Invocation &invocation) : invocation_(invocation) {}

  template <typename T>
  T get(size_t index) const {
    if (index >= invocation_.argumentCount()) {
      return convertFromJS<T>(
          invocation_.sharedContext(),
          facebook::jsi::Value::undefined(),
          invocation_.path() + " argument " + std::to_string(index));
    }
    return convertFromJS<T>(
        invocation_.sharedContext(),
        invocation_.argument(index),
        invocation_.path() + " argument " + std::to_string(index));
  }

private:
  Invocation &invocation_;
};

template <typename T>
T ReadableArguments::get(const std::string &key) const {
  if (!object_.hasProperty(key)) {
    throw CodedError(
        "ERR_REQUIRED_FIELD", path_ + "." + key + " is required.");
  }
  return convertFromJS<T>(
      context_, object_.getProperty(key).get(), path_ + "." + key);
}

template <typename T>
std::optional<T> ReadableArguments::getOptional(const std::string &key) const {
  if (!object_.hasProperty(key)) {
    return std::nullopt;
  }
  auto value = object_.getProperty(key).get();
  if (value.isNull() || value.isUndefined()) {
    return std::nullopt;
  }
  return convertFromJS<T>(context_, value, path_ + "." + key);
}

template <typename Return, typename... Arguments, typename Body, size_t... Indices>
facebook::jsi::Value invokeTypedBody(
    Invocation &invocation,
    Body &body,
    std::index_sequence<Indices...>) {
  invocation.requireArgumentCount(
      requiredArgumentCount<Arguments...>(), sizeof...(Arguments));
  ArgumentReader reader(invocation);
  if constexpr (std::is_void_v<Return>) {
    body(reader.template get<Arguments>(Indices)...);
    return facebook::jsi::Value::undefined();
  } else {
    return convertToJS(
        invocation.sharedContext(),
        body(reader.template get<Arguments>(Indices)...));
  }
}

template <typename Return, typename... Arguments, typename Body>
FunctionDefinition typedFunction(
    std::string name,
    Body body,
    FunctionQueue queue = FunctionQueue::JavaScript) {
  FunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = sizeof...(Arguments);
  definition.requiredArity = requiredArgumentCount<Arguments...>();
  definition.queue = queue;
  definition.body = [body = std::move(body)](Invocation &invocation) mutable {
    return invokeTypedBody<Return, Arguments...>(
        invocation, body, std::index_sequence_for<Arguments...>{});
  };
  return definition;
}

template <typename... Arguments, size_t... Indices>
std::tuple<Arguments...> readTypedArguments(
    Invocation &invocation,
    std::index_sequence<Indices...>) {
  invocation.requireArgumentCount(
      requiredArgumentCount<Arguments...>(), sizeof...(Arguments));
  ArgumentReader reader(invocation);
  return std::tuple<Arguments...>{reader.template get<Arguments>(Indices)...};
}

template <typename Return, typename... Arguments, typename Body>
FunctionDefinition typedAsyncFunction(
    std::string name,
    Body body,
    FunctionQueue queue = FunctionQueue::Modules) {
  FunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = sizeof...(Arguments);
  definition.requiredArity = requiredArgumentCount<Arguments...>();
  definition.async = true;
  definition.queue = queue;
  definition.asyncBody =
      [body = std::move(body), queue](
          Invocation &invocation,
          const std::shared_ptr<Promise> &promise) mutable {
        if (queue != FunctionQueue::JavaScript && (isJavaScriptBound<Return> || (isJavaScriptBound<Arguments> || ...))) {
          throw CodedError(
              "ERR_WRONG_THREAD",
              invocation.path() + " uses a JSI-bound type and therefore must run on the JavaScript queue.");
        }
        auto context = invocation.sharedContext();
        auto arguments = readTypedArguments<Arguments...>(
            invocation, std::index_sequence_for<Arguments...>{});
        context->dispatch(
            queue,
            [body,
             context,
             arguments = std::move(arguments),
             promise]() mutable {
              try {
                promise->cancellationToken()->throwIfCancellationRequested();
                if constexpr (std::is_void_v<Return>) {
                  std::apply(body, std::move(arguments));
                  promise->resolveUndefined();
                } else {
                  auto result = std::make_shared<Return>(
                      std::apply(body, std::move(arguments)));
                  promise->resolve(
                      [context, result = std::move(result)](
                          facebook::jsi::Runtime &) mutable {
                        return convertToJS(context, std::move(*result));
                      });
                }
              } catch (const CodedError &error) {
                promise->reject(error);
              } catch (const std::exception &error) {
                promise->reject("ERR_UNEXPECTED", error.what());
              } catch (...) {
                promise->reject(
                    "ERR_UNEXPECTED", "The native async function threw a non-standard exception.");
              }
            });
      };
  return definition;
}

template <typename Return, typename... Arguments, typename Body>
FunctionDefinition typedCancellableFunction(
    std::string name,
    Body body,
    FunctionQueue queue = FunctionQueue::Modules) {
  FunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = sizeof...(Arguments);
  definition.requiredArity = requiredArgumentCount<Arguments...>();
  definition.async = true;
  definition.queue = queue;
  definition.asyncBody =
      [body = std::move(body), queue](
          Invocation &invocation,
          const std::shared_ptr<Promise> &promise) mutable {
        if (queue != FunctionQueue::JavaScript && (isJavaScriptBound<Return> || (isJavaScriptBound<Arguments> || ...))) {
          throw CodedError(
              "ERR_WRONG_THREAD",
              invocation.path() + " uses a JSI-bound type and therefore must run on the JavaScript queue.");
        }
        auto context = invocation.sharedContext();
        auto arguments = readTypedArguments<Arguments...>(
            invocation, std::index_sequence_for<Arguments...>{});
        auto token = promise->cancellationToken();
        context->dispatch(
            queue,
            [body,
             context,
             arguments = std::move(arguments),
             promise,
             token = std::move(token)]() mutable {
              try {
                token->throwIfCancellationRequested();
                if constexpr (std::is_void_v<Return>) {
                  std::apply(
                      [&](auto &&...values) {
                        body(
                            token,
                            std::forward<decltype(values)>(values)...);
                      },
                      std::move(arguments));
                  token->throwIfCancellationRequested();
                  promise->resolveUndefined();
                } else {
                  auto result = std::apply(
                      [&](auto &&...values) {
                        return body(
                            token,
                            std::forward<decltype(values)>(values)...);
                      },
                      std::move(arguments));
                  token->throwIfCancellationRequested();
                  auto retained = std::make_shared<Return>(std::move(result));
                  promise->resolve(
                      [context, retained = std::move(retained)](
                          facebook::jsi::Runtime &) mutable {
                        return convertToJS(context, std::move(*retained));
                      });
                }
              } catch (const CodedError &error) {
                promise->reject(error);
              } catch (const std::exception &error) {
                promise->reject("ERR_UNEXPECTED", error.what());
              } catch (...) {
                promise->reject(
                    "ERR_UNEXPECTED",
                    "The cancellable native function threw a non-standard exception.");
              }
            });
      };
  return definition;
}

template <typename... Arguments, typename Body>
FunctionDefinition typedPromiseFunction(
    std::string name,
    Body body,
    FunctionQueue queue = FunctionQueue::Modules) {
  FunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = sizeof...(Arguments);
  definition.requiredArity = requiredArgumentCount<Arguments...>();
  definition.async = true;
  definition.queue = queue;
  definition.asyncBody =
      [body = std::move(body), queue](
          Invocation &invocation,
          const std::shared_ptr<Promise> &promise) mutable {
        if (queue != FunctionQueue::JavaScript && (isJavaScriptBound<Arguments> || ...)) {
          throw CodedError(
              "ERR_WRONG_THREAD",
              invocation.path() + " uses a JSI-bound type and therefore must run on the JavaScript queue.");
        }
        auto context = invocation.sharedContext();
        auto arguments = readTypedArguments<Arguments...>(
            invocation, std::index_sequence_for<Arguments...>{});
        context->dispatch(
            queue,
            [body,
             arguments = std::move(arguments),
             promise]() mutable {
              try {
                promise->cancellationToken()->throwIfCancellationRequested();
                std::apply(
                    [&body, &promise](auto &&...values) {
                      body(
                          std::forward<decltype(values)>(values)...,
                          promise);
                    },
                    std::move(arguments));
              } catch (const CodedError &error) {
                promise->reject(error);
              } catch (const std::exception &error) {
                promise->reject("ERR_UNEXPECTED", error.what());
              } catch (...) {
                promise->reject(
                    "ERR_UNEXPECTED", "The native Promise function threw a non-standard exception.");
              }
            });
      };
  return definition;
}

template <typename... Arguments>
void NativeSharedObject::sendEvent(
    std::string eventName,
    Arguments &&...arguments) const {
  std::vector<SharedObjectEventArgument> convertedArguments;
  convertedArguments.reserve(sizeof...(Arguments));
  (convertedArguments.emplace_back(
       [retained = std::make_shared<std::decay_t<Arguments>>(
            std::forward<Arguments>(arguments))](
           const std::shared_ptr<RuntimeContext> &context) mutable {
         return convertToJS(context, std::move(*retained));
       }),
   ...);
  sendEventWithArguments(
      std::move(eventName),
      std::move(convertedArguments),
      (false || ... || isJavaScriptBound<Arguments>));
}

}  // namespace expo::harmony
