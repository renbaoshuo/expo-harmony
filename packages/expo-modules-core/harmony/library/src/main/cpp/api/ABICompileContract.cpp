#include <array>
#include <chrono>
#include <list>
#include <map>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <variant>

#include "ExpoModulesCore.h"

namespace expo::harmony::abi_contract {

enum class ExampleEnum {
  Alpha,
  Beta,
};

struct ExampleRecord {
  std::string requiredName;
  int count{7};
  std::optional<bool> flag;
};

class ExampleSharedObject final : public NativeSharedObject {
public:
  explicit ExampleSharedObject(int value) : value(value) {}

  size_t getAdditionalMemoryPressure() const noexcept override {
    return 64;
  }

  int value;
};

class NamespacedProvider final : public ExpoModulesProvider {
public:
  std::vector<std::shared_ptr<ExpoModule>> modules(
      const std::shared_ptr<RuntimeContext> &) override {
    return {};
  }
};

}  // namespace expo::harmony::abi_contract

namespace expo::harmony {

template <>
struct EnumTraits<abi_contract::ExampleEnum> {
  static auto values() {
    using Enum = abi_contract::ExampleEnum;
    return std::array<std::pair<Enum, EnumerableValue>, 2>{
        std::pair{Enum::Alpha, EnumerableValue{std::string("alpha")}},
        std::pair{Enum::Beta, EnumerableValue{2.0}}};
  }
};

template <>
struct RecordTraits<abi_contract::ExampleRecord> {
  static auto fields() {
    using Record = abi_contract::ExampleRecord;
    return std::make_tuple(
        requiredRecordField("requiredName", &Record::requiredName),
        recordField("count", &Record::count),
        recordField("flag", &Record::flag));
  }
};

namespace abi_contract {

// This translation unit intentionally constructs every public definition and
// converter family. It is linked into the HAR, so header-only ABI drift fails
// the native build instead of remaining latent until a third-party module uses it.
[[maybe_unused]] ModuleDefinition instantiateDefinitionABI() {
  ModuleBuilder module("ExpoABICompileContract");
  module.constant<std::string>("constant", [] { return std::string("value"); });
  module.function(typedFunction<void>("void", [] {}));
  module.function(typedFunction<
                  std::vector<int>,
                  std::vector<int>>("vector", [](std::vector<int> value) { return value; }));
  module.function(typedFunction<
                  std::array<int, 2>,
                  std::array<int, 2>>("array", [](std::array<int, 2> value) { return value; }));
  module.function(typedFunction<
                  std::list<std::string>,
                  std::list<std::string>>("list", [](std::list<std::string> value) { return value; }));
  module.function(typedFunction<
                  std::set<int>,
                  std::set<int>>("set", [](std::set<int> value) { return value; }));
  module.function(typedFunction<
                  std::unordered_set<int>,
                  std::unordered_set<int>>(
      "unorderedSet", [](std::unordered_set<int> value) { return value; }));
  module.function(typedFunction<
                  std::map<std::string, int>,
                  std::map<std::string, int>>(
      "map", [](std::map<std::string, int> value) { return value; }));
  module.function(typedFunction<
                  std::unordered_map<std::string, int>,
                  std::unordered_map<std::string, int>>(
      "unorderedMap",
      [](std::unordered_map<std::string, int> value) { return value; }));
  module.function(typedFunction<
                  std::pair<std::string, int>,
                  std::pair<std::string, int>>(
      "pair", [](std::pair<std::string, int> value) { return value; }));
  module.function(typedFunction<
                  Either<std::string, double>,
                  Either<std::string, double>>(
      "either", [](Either<std::string, double> value) { return value; }));
  module.function(typedFunction<
                  std::optional<int>,
                  std::optional<int>>(
      "optional", [](std::optional<int> value) { return value; }));
  module.function(typedFunction<
                  ValueOrUndefined<int>,
                  ValueOrUndefined<int>>(
      "valueOrUndefined", [](ValueOrUndefined<int> value) { return value; }));
  module.function(typedFunction<
                  int,
                  int,
                  std::optional<int>,
                  ValueOrUndefined<int>>(
      "optionalTail",
      [](int required,
         std::optional<int> optional,
         ValueOrUndefined<int> valueOrUndefined) {
        return required + optional.value_or(0) + (valueOrUndefined.isUndefined() ? 0 : valueOrUndefined.value());
      }));
  module.function(typedFunction<
                  ExampleEnum,
                  ExampleEnum>("enumerable", [](ExampleEnum value) { return value; }));
  module.function(typedFunction<
                  ExampleRecord,
                  ExampleRecord>("record", [](ExampleRecord value) { return value; }));
  module.function(typedFunction<
                  JSDate,
                  JSDate,
                  std::chrono::milliseconds,
                  URL,
                  URI,
                  std::filesystem::path,
                  Color>(
      "platformTypes",
      [](JSDate date,
         std::chrono::milliseconds,
         URL,
         URI,
         std::filesystem::path,
         Color) { return date; }));
  module.function(typedFunction<
                  JavaScriptValue,
                  JavaScriptValue,
                  JavaScriptObject,
                  JavaScriptFunction,
                  JavaScriptWeakObject,
                  JavaScriptArrayBuffer,
                  JavaScriptTypedArray,
                  facebook::jsi::Value,
                  facebook::jsi::Object,
                  facebook::jsi::Function,
                  facebook::jsi::ArrayBuffer,
                  ReadableArguments>(
      "jsiValues",
      [](JavaScriptValue value,
         JavaScriptObject,
         JavaScriptFunction,
         JavaScriptWeakObject,
         JavaScriptArrayBuffer,
         JavaScriptTypedArray,
         facebook::jsi::Value,
         facebook::jsi::Object,
         facebook::jsi::Function,
         facebook::jsi::ArrayBuffer,
         ReadableArguments) { return value; }));
  module.function(typedFunction<
                  NativeArrayBuffer,
                  NativeArrayBuffer,
                  std::vector<uint8_t>,
                  Blob>(
      "buffers",
      [](NativeArrayBuffer buffer, std::vector<uint8_t>, Blob) { return buffer; }));
  module.function(typedFunction<
                  Uint8Array,
                  Int8Array,
                  Int16Array,
                  Int32Array,
                  Uint8Array,
                  Uint8ClampedArray,
                  Uint16Array,
                  Uint32Array,
                  Float32Array,
                  Float64Array,
                  BigInt64Array,
                  BigUint64Array>(
      "typedArrays",
      [](Int8Array,
         Int16Array,
         Int32Array,
         Uint8Array value,
         Uint8ClampedArray,
         Uint16Array,
         Uint32Array,
         Float32Array,
         Float64Array,
         BigInt64Array,
         BigUint64Array) { return value; }));
  module.function(typedFunction<
                  Serializable,
                  Serializable,
                  Worklet>(
      "worklets", [](Serializable value, Worklet) { return value; }));
  module.function(typedFunction<
                  void,
                  std::shared_ptr<ExampleSharedObject>>(
      "sharedObjectArgument",
      [](std::shared_ptr<ExampleSharedObject>) {}));
  module.function(typedFunction<
                  std::shared_ptr<ExampleSharedObject>,
                  std::shared_ptr<ExampleSharedObject>>(
      "sharedObjectRoundTrip",
      [](std::shared_ptr<ExampleSharedObject> value) { return value; }));
  module.function(typedAsyncFunction<int, int>(
      "async", [](int value) { return value; }, FunctionQueue::Modules));
  module.function(typedCancellableFunction<int, int>(
      "cancellable",
      [](std::shared_ptr<const CancellationToken> token, int value) {
        token->throwIfCancellationRequested();
        return value;
      },
      FunctionQueue::Background));
  module.function(typedPromiseFunction<int>(
      "promise",
      [](int value, const std::shared_ptr<Promise> &promise) {
        promise->resolve([value](facebook::jsi::Runtime &) {
          return facebook::jsi::Value(value);
        });
      }));
  module.property(typedProperty<int>("property", [] { return 1; }, [](int) {}));
  module.events({"change"});
  module.onCreate([](RuntimeContext &) {});
  module.onRegisterActivityContracts([](RuntimeContext &) {});
  module.onActivityDestroy([](RuntimeContext &) {});
  module.onStartObserving([](RuntimeContext &) {});
  module.onStartObserving(
      [](RuntimeContext &, const std::string &) {});
  module.onStartObserving("change", [](RuntimeContext &) {});
  module.onStopObserving([](RuntimeContext &) {});
  module.onStopObserving(
      [](RuntimeContext &, const std::string &) {});
  module.onStopObserving("change", [](RuntimeContext &) {});

  ObjectDefinitionBuilder object("Nested");
  object.constant<int>("answer", [] { return 42; });
  object.function(typedFunction<std::string, std::string>(
      "echo", [](std::string value) { return value; }));
  object.property(typedProperty<bool>("enabled", [] { return true; }));
  module.object(std::move(object).build());

  ClassDefinitionBuilder<ExampleSharedObject> klass("ExampleSharedObject");
  klass.constructor<int>([](int value) {
    return std::make_shared<ExampleSharedObject>(value);
  });
  klass.function(typedSharedFunction<ExampleSharedObject, int>(
      "get", [](ExampleSharedObject &owner) { return owner.value; }));
  klass.constant<int>("kind", [] { return 1; });
  klass.function(typedSharedAsyncFunction<ExampleSharedObject, int, int>(
      "add",
      [](ExampleSharedObject &owner, int value) { return owner.value + value; }));
  klass.property(typedSharedProperty<ExampleSharedObject, int>(
      "value",
      [](ExampleSharedObject &owner) { return owner.value; },
      [](ExampleSharedObject &owner, int value) { owner.value = value; }));
  klass.staticFunction(typedFunction<int>("staticValue", [] { return 1; }));
  klass.staticProperty(typedProperty<int>("staticProperty", [] { return 1; }));
  klass.events({"change"});
  klass.onStartObserving(
      [](RuntimeContext &, const std::shared_ptr<NativeSharedObject> &) {});
  klass.onStartObserving(
      [](RuntimeContext &,
         const std::shared_ptr<NativeSharedObject> &,
         const std::string &) {});
  klass.onStartObserving(
      "change",
      [](RuntimeContext &,
         const std::shared_ptr<NativeSharedObject> &,
         const std::string &) {});
  klass.onStopObserving(
      [](RuntimeContext &, const std::shared_ptr<NativeSharedObject> &) {});
  module.klass(std::move(klass).build());

  JavaScriptClassDefinitionBuilder javaScriptClass("JavaScriptClass");
  javaScriptClass
      .constructor(
          [](Invocation &) { return facebook::jsi::Value::undefined(); },
          1,
          0)
      .constant<std::string>("kind", [] { return std::string("js"); })
      .function(typedFunction<int, int>(
          "echo", [](int value) { return value; }))
      .property(typedProperty<int>("value", [] { return 1; }))
      .staticFunction(typedFunction<int>("staticValue", [] { return 1; }))
      .staticProperty(typedProperty<int>("staticProperty", [] { return 1; }));
  module.klass(std::move(javaScriptClass).build());

  const std::string componentName = "ViewManagerAdapter_ExpoABICompileContract";
  ViewDefinitionBuilder view("Default");
  view.defaultView()
      .componentName(componentName)
      .prototypeName("ExpoABICompileContract")
      .group()
      .prop("title")
      .propGroup({"left", "top"}, [](RuntimeContext &, int64_t, const std::string &, const folly::dynamic &) {})
      .events({"onChange"})
      .function(typedViewFunction<void, std::string>(
          "setTitle",
          componentName,
          [](const ViewHandle &handle, std::string title) {
            auto arguments = folly::dynamic::array();
            arguments.push_back(std::move(title));
            handle.dispatchCommand("setTitle", std::move(arguments));
          }));
  module.view(std::move(view).build());
  return std::move(module).build();
}

}  // namespace abi_contract
}  // namespace expo::harmony
