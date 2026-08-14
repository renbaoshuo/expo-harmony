#include "Worklets.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

SerializableValueType stableType(worklets::Serializable::ValueType type) {
  using Source = worklets::Serializable::ValueType;
  switch (type) {
    case Source::UndefinedType: return SerializableValueType::Undefined;
    case Source::NullType: return SerializableValueType::Null;
    case Source::BooleanType: return SerializableValueType::Boolean;
    case Source::NumberType: return SerializableValueType::Number;
    case Source::BigIntType: return SerializableValueType::BigInt;
    case Source::StringType: return SerializableValueType::String;
    case Source::ObjectType: return SerializableValueType::Object;
    case Source::ArrayType: return SerializableValueType::Array;
    case Source::MapType: return SerializableValueType::Map;
    case Source::SetType: return SerializableValueType::Set;
    case Source::WorkletType: return SerializableValueType::Worklet;
    case Source::RemoteFunctionType: return SerializableValueType::RemoteFunction;
    case Source::HandleType: return SerializableValueType::Handle;
    case Source::HostObjectType: return SerializableValueType::HostObject;
    case Source::HostFunctionType: return SerializableValueType::HostFunction;
    case Source::ArrayBufferType: return SerializableValueType::ArrayBuffer;
    case Source::TurboModuleLikeType: return SerializableValueType::TurboModuleLike;
    case Source::ImportType: return SerializableValueType::Import;
    case Source::SynchronizableType: return SerializableValueType::Synchronizable;
    case Source::CustomType: return SerializableValueType::Custom;
  }
  // Match Expo's iOS/Android forward-compatibility behavior: a value type
  // introduced by a newer Worklets build degrades to Undefined.
  return SerializableValueType::Undefined;
}

std::vector<std::shared_ptr<worklets::Serializable>> unwrapArguments(
    std::vector<Serializable> arguments) {
  std::vector<std::shared_ptr<worklets::Serializable>> result;
  result.reserve(arguments.size());
  for (const auto &argument : arguments) {
    result.push_back(argument.value());
  }
  return result;
}

void invoke(
    jsi::Runtime &runtime,
    const std::shared_ptr<worklets::SerializableWorklet> &worklet,
    const std::vector<std::shared_ptr<worklets::Serializable>> &arguments) {
  auto function = worklet->toJSValue(runtime).asObject(runtime).asFunction(runtime);
  std::vector<jsi::Value> values;
  values.reserve(arguments.size());
  for (const auto &argument : arguments) {
    values.push_back(argument->toJSValue(runtime));
  }
  function.call(
      runtime,
      static_cast<const jsi::Value *>(values.data()),
      values.size());
}

}  // namespace

Serializable::Serializable(std::shared_ptr<worklets::Serializable> value)
    : value_(std::move(value)) {
  if (!value_) {
    throw CodedError("ERR_SERIALIZABLE_TYPE", "Serializable cannot hold a null value.");
  }
}

SerializableValueType Serializable::type() const {
  return stableType(value_->valueType());
}

const std::shared_ptr<worklets::Serializable> &Serializable::value() const noexcept {
  return value_;
}

jsi::Value Serializable::toJSValue(jsi::Runtime &runtime) const {
  return worklets::SerializableJSRef::newNativeStateObject(runtime, value_);
}

Worklet::Worklet(std::shared_ptr<worklets::SerializableWorklet> value)
    : Serializable(value), worklet_(std::move(value)) {
  if (!worklet_) {
    throw CodedError("ERR_WORKLET_TYPE", "Worklet cannot hold a null function.");
  }
}

void Worklet::schedule(
    const WorkletRuntime &runtime,
    std::vector<Serializable> arguments) const {
  auto nativeRuntime = runtime.runtime_.lock();
  if (!nativeRuntime) {
    return;
  }
  auto worklet = worklet_;
  if (arguments.empty()) {
    nativeRuntime->schedule(std::move(worklet));
    return;
  }
  auto nativeArguments = unwrapArguments(std::move(arguments));
  nativeRuntime->schedule(
      [worklet = std::move(worklet), arguments = std::move(nativeArguments)](
          jsi::Runtime &targetRuntime) {
        invoke(targetRuntime, worklet, arguments);
      });
}

void Worklet::execute(
    const WorkletRuntime &runtime,
    std::vector<Serializable> arguments) const {
  auto nativeRuntime = runtime.requireRuntime();
  if (arguments.empty()) {
    nativeRuntime->runSync(worklet_);
    return;
  }
  auto nativeArguments = unwrapArguments(std::move(arguments));
  nativeRuntime->runSync(
      [worklet = worklet_, arguments = std::move(nativeArguments)](
          jsi::Runtime &targetRuntime) {
        invoke(targetRuntime, worklet, arguments);
      });
}

const std::shared_ptr<worklets::SerializableWorklet> &Worklet::worklet() const noexcept {
  return worklet_;
}

WorkletRuntime::WorkletRuntime(std::weak_ptr<worklets::WorkletRuntime> runtime)
    : runtime_(std::move(runtime)) {}

WorkletRuntime WorkletRuntime::fromJSRuntime(jsi::Runtime &runtime) {
  return WorkletRuntime(
      worklets::WorkletRuntime::getWeakRuntimeFromJSIRuntime(runtime));
}

bool WorkletRuntime::isAlive() const noexcept {
  return !runtime_.expired();
}

uint64_t WorkletRuntime::id() const {
  return requireRuntime()->getRuntimeId();
}

std::string WorkletRuntime::name() const {
  return requireRuntime()->getRuntimeName();
}

std::shared_ptr<worklets::WorkletRuntime> WorkletRuntime::requireRuntime() const {
  auto runtime = runtime_.lock();
  if (!runtime) {
    throw CodedError(
        "ERR_WORKLET_RUNTIME_DESTROYED", "The Worklets runtime has been destroyed.");
  }
  return runtime;
}

}  // namespace expo::harmony
