#include "ArkTSModuleAdapter.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <functional>
#include <limits>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include <jsi/JSIDynamic.h>

#include <react/bridging/LongLivedObject.h>

#include "api/Promise.h"
#include "common/SharedObject.h"
#include "errors/CodedError.h"
#include "modules/ArkTSTypedBridge.h"
#include "modules/ViewHandle.h"
#include "modules/internal/ModuleDefinition.h"
#include "runtime/Protocol.h"
#include "runtime/RuntimeContext.h"

namespace jsi = facebook::jsi;
namespace react = facebook::react;

namespace expo::harmony {
namespace {

constexpr const char *kMarker = protocol::kSharedObjectMarker;
constexpr size_t kMaxValueDepth = 64;
constexpr double kMaxSafeTransportInteger = 9007199254740991.0;

const folly::dynamic &requireField(
    const folly::dynamic &object,
    const char *field,
    const std::string &path) {
  if (!object.isObject() || !object.count(field)) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR",
        path + " is missing required field '" + field + "'.");
  }
  return object.at(field);
}

const folly::dynamic &requireArray(
    const folly::dynamic &object,
    const char *field,
    const std::string &path) {
  const auto &value = requireField(object, field, path);
  if (!value.isArray()) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR",
        path + "." + field + " must be an array.");
  }
  return value;
}

std::string requireString(
    const folly::dynamic &object,
    const char *field,
    const std::string &path) {
  const auto &value = requireField(object, field, path);
  if (!value.isString() || value.asString().empty()) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR",
        path + "." + field + " must be a non-empty string.");
  }
  return value.asString();
}

std::optional<uint64_t> readTransportInteger(const folly::dynamic &value) {
  if (value.isInt()) {
    if (value.asInt() < 0) {
      return std::nullopt;
    }
    return static_cast<uint64_t>(value.asInt());
  }
  if (!value.isDouble()) {
    return std::nullopt;
  }
  const auto number = value.asDouble();
  if (!std::isfinite(number) || std::trunc(number) != number || number < 0 || number > kMaxSafeTransportInteger) {
    return std::nullopt;
  }
  return static_cast<uint64_t>(number);
}

size_t requireArity(const folly::dynamic &object, const std::string &path) {
  const auto arity = readTransportInteger(requireField(object, "arity", path));
  if (!arity || *arity > std::numeric_limits<size_t>::max()) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR",
        path + ".arity must be a non-negative integer.");
  }
  return static_cast<size_t>(*arity);
}

size_t requireArityField(
    const folly::dynamic &object,
    const char *field,
    const std::string &path) {
  const auto arity = readTransportInteger(requireField(object, field, path));
  if (!arity || *arity > std::numeric_limits<size_t>::max()) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR",
        path + "." + field + " must be a non-negative integer.");
  }
  return static_cast<size_t>(*arity);
}

bool requireBoolean(
    const folly::dynamic &object,
    const char *field,
    const std::string &path) {
  const auto &value = requireField(object, field, path);
  if (!value.isBool()) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR",
        path + "." + field + " must be a boolean.");
  }
  return value.asBool();
}

class ArkTSSharedObject final : public NativeSharedObject {
public:
  ArkTSSharedObject(
      std::weak_ptr<RuntimeContext> context,
      std::string runtimeEpoch,
      std::string moduleName,
      std::string className,
      std::string nativeRefType)
      : context_(std::move(context)),
        runtimeEpoch_(std::move(runtimeEpoch)),
        moduleName_(std::move(moduleName)),
        className_(std::move(className)),
        nativeRefType_(std::move(nativeRefType)) {}

  void bindObjectId(long objectId) noexcept {
    objectId_ = objectId;
  }

  long objectId() const noexcept {
    return objectId_;
  }

  const std::string &runtimeEpoch() const noexcept {
    return runtimeEpoch_;
  }

  const std::string &moduleName() const noexcept {
    return moduleName_;
  }

  const std::string &className() const noexcept {
    return className_;
  }

  std::string nativeRefType() const override {
    return nativeRefType_;
  }

  void setAdditionalMemoryPressure(size_t value) noexcept {
    memoryPressure_ = value;
  }

  size_t getAdditionalMemoryPressure() const noexcept override {
    return memoryPressure_;
  }

  void onStartListeningToEvent(const std::string &eventName) override {
    setObserving(eventName, true);
  }

  void onStopListeningToEvent(const std::string &eventName) override {
    setObserving(eventName, false);
  }

  void sharedObjectWillRelease() override {
    if (!willReleaseNotified_.exchange(true, std::memory_order_acq_rel)) {
      if (auto context = context_.lock(); context && context->isAlive() && objectId_ > 0) {
        context->callPlatformSync(
            "expoSharedObjectWillRelease", {runtimeEpoch_, objectId_});
      }
    }
    NativeSharedObject::sharedObjectWillRelease();
  }

  void sharedObjectDidRelease() override {
    if (!releaseNotified_.exchange(true, std::memory_order_acq_rel)) {
      if (auto context = context_.lock(); context && context->isAlive() && objectId_ > 0) {
        context->callPlatformSync(
            "releaseExpoSharedObject", {runtimeEpoch_, objectId_});
      }
    }
    NativeSharedObject::sharedObjectDidRelease();
  }

private:
  void setObserving(const std::string &eventName, bool observing) {
    auto context = context_.lock();
    if (!context || !context->isAlive() || objectId_ <= 0 || releaseNotified_.load(std::memory_order_acquire)) {
      return;
    }
    context->callPlatformSync(
        "setExpoSharedObjectObserving",
        {runtimeEpoch_, objectId_, moduleName_, className_, eventName, observing});
  }

  std::weak_ptr<RuntimeContext> context_;
  std::string runtimeEpoch_;
  std::string moduleName_;
  std::string className_;
  std::string nativeRefType_;
  long objectId_{0};
  size_t memoryPressure_{0};
  std::atomic_bool willReleaseNotified_{false};
  std::atomic_bool releaseNotified_{false};
};

void loadMemoryPressure(
    const std::shared_ptr<RuntimeContext> &context,
    const std::shared_ptr<ArkTSSharedObject> &object) {
  auto value = context->callPlatformSync(
      "getExpoSharedObjectMemoryPressure",
      {object->runtimeEpoch(), object->objectId()});
  auto pressure = readTransportInteger(
      jsi::dynamicFromValue(context->runtime(), value));
  if (!pressure || *pressure > std::numeric_limits<size_t>::max()) {
    throw CodedError(
        "ERR_SHARED_OBJECT_MEMORY_PRESSURE",
        "ArkTS SharedObject memory pressure must be a non-negative safe integer.");
  }
  object->setAdditionalMemoryPressure(static_cast<size_t>(*pressure));
}

bool isArrayBufferView(jsi::Runtime &runtime, const jsi::Object &object) {
  auto arrayBuffer = runtime.global().getPropertyAsObject(runtime, "ArrayBuffer");
  auto isView = arrayBuffer.getPropertyAsFunction(runtime, "isView");
  auto result = isView.callWithThis(runtime, arrayBuffer, object);
  return result.isBool() && result.getBool();
}

std::vector<size_t> writableArgumentIndices(
    const folly::dynamic &descriptor, size_t arity, bool async, const std::string &path) {
  std::vector<size_t> indices;
  if (!descriptor.count("writableArguments")) {
    return indices;
  }
  for (const auto &value : requireArray(descriptor, "writableArguments", path)) {
    const auto index = readTransportInteger(value);
    if (!index || *index >= arity || (!indices.empty() && *index <= indices.back())) {
      throw CodedError("ERR_ARKTS_MODULE_DESCRIPTOR", path + ".writableArguments must contain increasing argument indices within arity.");
    }
    indices.push_back(static_cast<size_t>(*index));
  }
  if (async && !indices.empty()) {
    throw CodedError("ERR_ARKTS_MODULE_DESCRIPTOR", path + " cannot declare asynchronous writable arguments.");
  }
  return indices;
}

struct TypedEncodedArguments final {
  std::vector<jsi::Value> values;
  std::vector<std::shared_ptr<NativeSharedObject>> sharedObjects;
};

jsi::Value makeTypedMarker(
    jsi::Runtime &runtime,
    const NativeSharedObjectIdentity &identity) {
  jsi::Object metadata(runtime);
  metadata.setProperty(
      runtime,
      "runtimeEpoch",
      jsi::String::createFromUtf8(runtime, identity.runtimeEpoch));
  metadata.setProperty(runtime, "objectId", static_cast<double>(identity.objectId));
  metadata.setProperty(runtime, "authorId", 0.0);
  metadata.setProperty(
      runtime,
      "moduleName",
      jsi::String::createFromUtf8(runtime, identity.moduleName));
  metadata.setProperty(
      runtime,
      "className",
      jsi::String::createFromUtf8(runtime, identity.className));
  metadata.setProperty(
      runtime,
      "nativeRefType",
      jsi::String::createFromUtf8(runtime, identity.nativeRefType));
  jsi::Array classLineage(runtime, identity.classLineage.size());
  for (size_t index = 0; index < identity.classLineage.size(); ++index) {
    const auto &classIdentity = identity.classLineage[index];
    jsi::Object classValue(runtime);
    classValue.setProperty(
        runtime,
        "moduleName",
        jsi::String::createFromUtf8(runtime, classIdentity.moduleName));
    classValue.setProperty(
        runtime,
        "className",
        jsi::String::createFromUtf8(runtime, classIdentity.className));
    classLineage.setValueAtIndex(runtime, index, std::move(classValue));
  }
  metadata.setProperty(runtime, "classLineage", std::move(classLineage));
  jsi::Object result(runtime);
  result.setProperty(runtime, kMarker, std::move(metadata));
  return result;
}

jsi::Value encodeTypedJSIValue(
    const std::shared_ptr<RuntimeContext> &context,
    jsi::Runtime &runtime,
    const jsi::Value &value,
    std::vector<std::shared_ptr<NativeSharedObject>> &sharedObjects,
    size_t depth) {
  if (depth > kMaxValueDepth) {
    throw CodedError(
        "ERR_ARKTS_MODULE_VALUE",
        "An ArkTS Expo module argument exceeds the maximum nesting depth.");
  }
  if (!value.isObject()) {
    return jsi::Value(runtime, value);
  }
  auto object = value.getObject(runtime);
  if (object.hasNativeState<expo::SharedObject::NativeState>(runtime)) {
    auto nativeState = object.getNativeState<expo::SharedObject::NativeState>(runtime);
    if (nativeState->isReleased() || nativeState->objectId <= 0) {
      throw CodedError(
          "ERR_SHARED_OBJECT_RELEASED",
          "Cannot pass a released SharedObject to an ArkTS Expo module.");
    }
    auto native = context->getNativeSharedObject(nativeState->objectId);
    auto identity = context->nativeSharedObjectIdentity(native);
    if (identity.runtimeEpoch != context->runtimeEpochString()) {
      throw CodedError(
          "ERR_SHARED_OBJECT_TYPE",
          "A SharedObject cannot cross RuntimeContext epochs.");
    }
    sharedObjects.push_back(native);
    return makeTypedMarker(runtime, identity);
  }
  if (object.isFunction(runtime) || object.isArrayBuffer(runtime) || isArrayBufferView(runtime, object)) {
    return jsi::Value(runtime, value);
  }
  if (object.isArray(runtime)) {
    auto source = object.getArray(runtime);
    jsi::Array result(runtime, source.size(runtime));
    for (size_t index = 0; index < source.size(runtime); ++index) {
      auto item = source.getValueAtIndex(runtime, index);
      result.setValueAtIndex(
          runtime,
          index,
          encodeTypedJSIValue(
              context,
              runtime,
              item,
              sharedObjects,
              depth + 1));
    }
    return result;
  }
  jsi::Object result(runtime);
  auto names = object.getPropertyNames(runtime);
  for (size_t index = 0; index < names.size(runtime); ++index) {
    auto nameValue = names.getValueAtIndex(runtime, index);
    if (!nameValue.isString()) {
      continue;
    }
    auto name = nameValue.getString(runtime);
    if (name.utf8(runtime) == kMarker) {
      throw CodedError(
          "ERR_ARKTS_MODULE_VALUE",
          "Plain objects cannot use the reserved Expo SharedObject marker key.");
    }
    auto property = object.getProperty(runtime, name);
    result.setProperty(
        runtime,
        name,
        encodeTypedJSIValue(
            context,
            runtime,
            property,
            sharedObjects,
            depth + 1));
  }
  return result;
}

TypedEncodedArguments encodeTypedArguments(
    Invocation &invocation,
    const std::shared_ptr<NativeSharedObject> &receiver = nullptr) {
  TypedEncodedArguments encoded;
  encoded.values.reserve(invocation.argumentCount());
  if (receiver) {
    encoded.sharedObjects.push_back(receiver);
  }
  for (size_t index = 0; index < invocation.argumentCount(); ++index) {
    encoded.values.push_back(encodeTypedJSIValue(
        invocation.sharedContext(),
        invocation.runtime(),
        invocation.argument(index),
        encoded.sharedObjects,
        0));
  }
  return encoded;
}

jsi::Value takeTypedArgumentArray(
    jsi::Runtime &runtime,
    std::vector<jsi::Value> values) {
  jsi::Array result(runtime, values.size());
  for (size_t index = 0; index < values.size(); ++index) {
    result.setValueAtIndex(runtime, index, std::move(values[index]));
  }
  return result;
}

void appendTypedArgument(
    std::vector<jsi::Value> &arguments,
    jsi::Runtime &runtime,
    const std::string &value) {
  arguments.emplace_back(jsi::String::createFromUtf8(runtime, value));
}

void appendTypedArgument(
    std::vector<jsi::Value> &arguments,
    jsi::Runtime &,
    long value) {
  arguments.emplace_back(static_cast<double>(value));
}

void appendTypedArgument(
    std::vector<jsi::Value> &arguments,
    jsi::Runtime &,
    bool value) {
  arguments.emplace_back(value);
}

template <typename... PrefixArguments>
std::vector<jsi::Value> makeTypedArguments(
    jsi::Runtime &runtime,
    PrefixArguments &&...prefixArguments) {
  std::vector<jsi::Value> arguments;
  arguments.reserve(sizeof...(PrefixArguments));
  (appendTypedArgument(
       arguments,
       runtime,
       std::forward<PrefixArguments>(prefixArguments)),
   ...);
  return arguments;
}

template <typename... PrefixArguments>
std::vector<jsi::Value> makeTypedValueArguments(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    PrefixArguments &&...prefixArguments) {
  auto arguments = makeTypedArguments(
      runtime, std::forward<PrefixArguments>(prefixArguments)...);
  arguments.emplace_back(runtime, value);
  return arguments;
}

jsi::Value decodeTypedValueGraph(
    const std::shared_ptr<RuntimeContext> &context,
    const jsi::Value &value,
    const std::function<void()> &commit = {});

jsi::Value decodeTypedResult(
    const std::shared_ptr<RuntimeContext> &context,
    jsi::Value result) {
  return decodeTypedValueGraph(context, result);
}

class ArkTSTypedResultHolder final : public react::LongLivedObject {
public:
  ArkTSTypedResultHolder(jsi::Runtime &runtime, jsi::Value value)
      : react::LongLivedObject(runtime), value_(std::move(value)) {}

  jsi::Value take() {
    if (!value_) {
      throw CodedError(
          "ERR_ARKTS_MODULE_VALUE",
          "The ArkTS Promise result has already been consumed.");
    }
    auto result = std::move(*value_);
    value_.reset();
    allowRelease();
    return result;
  }

private:
  std::optional<jsi::Value> value_;
};

std::shared_ptr<ArkTSSharedObject> requireArkTSObject(
    const std::shared_ptr<NativeSharedObject> &object,
    const std::string &path) {
  auto result = std::dynamic_pointer_cast<ArkTSSharedObject>(object);
  if (!result) {
    throw CodedError(
        "ERR_SHARED_OBJECT_TYPE",
        path + " received a SharedObject that is not backed by ArkTS.");
  }
  return result;
}

std::shared_ptr<void> retainInvocationLeases(
    const std::shared_ptr<RuntimeContext> &context,
    const std::vector<std::shared_ptr<NativeSharedObject>> &objects) {
  if (objects.empty()) {
    return nullptr;
  }
  auto leases = context->acquireSharedObjectInvocations(objects);
  return std::make_shared<SharedObjectInvocationLeaseBundle>(std::move(leases));
}

void collectAuthorIds(
    const folly::dynamic &value,
    std::vector<uint64_t> &result,
    size_t depth = 0) {
  if (depth > kMaxValueDepth) {
    return;
  }
  if (value.isArray()) {
    for (const auto &item : value) {
      collectAuthorIds(item, result, depth + 1);
    }
    return;
  }
  if (!value.isObject()) {
    return;
  }
  if (value.count(kMarker) && value.at(kMarker).isObject()) {
    const auto &marker = value.at(kMarker);
    if (marker.count("authorId")) {
      auto authorId = readTransportInteger(marker.at("authorId"));
      if (authorId && *authorId > 0) {
        result.push_back(*authorId);
      }
    }
    return;
  }
  for (const auto &item : value.items()) {
    collectAuthorIds(item.second, result, depth + 1);
  }
}

void discardAuthorIds(
    const std::shared_ptr<RuntimeContext> &context,
    const std::vector<uint64_t> &ids) noexcept {
  try {
    if (ids.empty() || !context || !context->isAlive()) {
      return;
    }
    auto values = folly::dynamic::array();
    for (auto id : ids) {
      values.push_back(static_cast<int64_t>(id));
    }
    context->callPlatformSync(
        "discardExpoSharedObjects",
        {context->runtimeEpochString(), std::move(values)});
  } catch (...) {
  }
}

void discardAuthorIds(
    const std::shared_ptr<RuntimeContext> &context,
    const folly::dynamic &value) noexcept {
  try {
    std::vector<uint64_t> ids;
    collectAuthorIds(value, ids);
    discardAuthorIds(context, ids);
  } catch (...) {
  }
}

void rollbackStagedObjects(
    const std::shared_ptr<RuntimeContext> &context,
    const std::unordered_set<long> &createdObjectIds) noexcept {
  for (const auto objectId : createdObjectIds) {
    try {
      context->releaseSharedObject(objectId);
    } catch (...) {
    }
  }
}

void rollbackStagedObject(
    const std::shared_ptr<RuntimeContext> &context,
    long objectId) noexcept {
  try {
    context->releaseSharedObject(objectId);
  } catch (...) {
  }
}

jsi::Value decodeArkTSValue(
    const std::shared_ptr<RuntimeContext> &context,
    const folly::dynamic &value,
    std::unordered_map<uint64_t, std::shared_ptr<ArkTSSharedObject>> &staged,
    std::unordered_set<long> &createdObjectIds,
    size_t depth) {
  if (depth > kMaxValueDepth) {
    throw CodedError(
        "ERR_ARKTS_MODULE_VALUE",
        "An ArkTS Expo module result exceeds the maximum nesting depth.");
  }
  auto &runtime = context->runtime();
  if (value.isNull()) {
    return jsi::Value::null();
  }
  if (value.isBool()) {
    return jsi::Value(value.asBool());
  }
  if (value.isInt()) {
    return jsi::Value(static_cast<double>(value.asInt()));
  }
  if (value.isDouble()) {
    return jsi::Value(value.asDouble());
  }
  if (value.isString()) {
    return jsi::String::createFromUtf8(runtime, value.asString());
  }
  if (value.isArray()) {
    jsi::Array result(runtime, value.size());
    for (size_t index = 0; index < value.size(); ++index) {
      result.setValueAtIndex(
          runtime,
          index,
          decodeArkTSValue(
              context,
              value.at(index),
              staged,
              createdObjectIds,
              depth + 1));
    }
    return result;
  }
  if (!value.isObject()) {
    throw CodedError(
        "ERR_ARKTS_MODULE_VALUE", "ArkTS returned an unsupported value.");
  }
  if (value.count(kMarker)) {
    const auto &marker = value.at(kMarker);
    if (!marker.isObject()) {
      throw CodedError(
          "ERR_ARKTS_MODULE_VALUE", "ArkTS returned an invalid SharedObject marker.");
    }
    auto runtimeEpoch = requireString(marker, "runtimeEpoch", "SharedObject marker");
    const auto &moduleNameValue = requireField(marker, "moduleName", "SharedObject marker");
    if (!moduleNameValue.isString()) {
      throw CodedError(
          "ERR_SHARED_OBJECT_TYPE",
          "SharedObject marker.moduleName must be a string.");
    }
    auto moduleName = moduleNameValue.asString();
    auto className = requireString(marker, "className", "SharedObject marker");
    auto nativeRefType = requireString(marker, "nativeRefType", "SharedObject marker");
    auto objectIdValue = readTransportInteger(
        requireField(marker, "objectId", "SharedObject marker"));
    auto authorIdValue = readTransportInteger(
        requireField(marker, "authorId", "SharedObject marker"));
    if (!objectIdValue || !authorIdValue || runtimeEpoch != context->runtimeEpochString() || *objectIdValue > static_cast<uint64_t>(std::numeric_limits<long>::max())) {
      throw CodedError(
          "ERR_SHARED_OBJECT_TYPE",
          "ArkTS returned a SharedObject for another or invalid runtime identity.");
    }
    if (moduleName.empty()) {
      throw CodedError(
          "ERR_SHARED_OBJECT_TYPE",
          "A SharedObject marker must identify its owning Expo module.");
    }
    if (*objectIdValue > 0) {
      if (*authorIdValue != 0) {
        throw CodedError(
            "ERR_SHARED_OBJECT_TYPE",
            "ArkTS returned a bound SharedObject with an author identity.");
      }
      auto native = context->getNativeSharedObject(
          static_cast<long>(*objectIdValue), moduleName, className);
      const auto identity = context->nativeSharedObjectIdentity(native);
      if (identity.runtimeEpoch != runtimeEpoch || identity.objectId != static_cast<long>(*objectIdValue) || identity.moduleName != moduleName || identity.className != className || identity.nativeRefType != nativeRefType) {
        throw CodedError(
            "ERR_SHARED_OBJECT_TYPE", "ArkTS returned mismatched SharedObject metadata.");
      }
      auto cached = context->getSharedObject(static_cast<long>(*objectIdValue));
      if (!cached.isUndefined()) {
        return cached;
      }
      return context->materializeNativeSharedObject(
          identity.moduleName, identity.className, std::move(native));
    }
    if (*authorIdValue == 0) {
      throw CodedError(
          "ERR_SHARED_OBJECT_TYPE",
          "ArkTS returned an unbound SharedObject without an author identity.");
    }
    if (auto iterator = staged.find(*authorIdValue); iterator != staged.end()) {
      auto cached = context->getSharedObject(iterator->second->objectId());
      if (!cached.isUndefined()) {
        return cached;
      }
      return context->materializeNativeSharedObject(
          iterator->second->moduleName(),
          iterator->second->className(),
          iterator->second);
    }
    auto object = std::make_shared<ArkTSSharedObject>(
        context, runtimeEpoch, moduleName, className, nativeRefType);
    auto objectId = context->registerNativeSharedObject(object);
    object->bindObjectId(objectId);
    try {
      auto canonicalValue = context->callPlatformSync(
          "bindExpoSharedObject",
          {runtimeEpoch,
           static_cast<int64_t>(*authorIdValue),
           objectId,
           moduleName,
           className,
           nativeRefType});
      auto canonicalObjectId = readTransportInteger(
          jsi::dynamicFromValue(runtime, canonicalValue));
      if (!canonicalObjectId || *canonicalObjectId == 0 || *canonicalObjectId > static_cast<uint64_t>(std::numeric_limits<long>::max())) {
        throw CodedError(
            "ERR_SHARED_OBJECT_TYPE",
            "ArkTS returned an invalid canonical SharedObject identity.");
      }
      if (*canonicalObjectId != static_cast<uint64_t>(objectId)) {
        context->releaseSharedObject(objectId);
        auto canonicalNative = context->getNativeSharedObject(
            static_cast<long>(*canonicalObjectId), moduleName, className);
        object = requireArkTSObject(
            canonicalNative, moduleName + "." + className);
        if (object->runtimeEpoch() != runtimeEpoch || object->nativeRefType() != nativeRefType) {
          throw CodedError(
              "ERR_SHARED_OBJECT_TYPE",
              "ArkTS returned mismatched canonical SharedObject metadata.");
        }
      } else {
        loadMemoryPressure(context, object);
        createdObjectIds.insert(objectId);
      }
      staged.emplace(*authorIdValue, object);
      return context->materializeNativeSharedObject(
          moduleName, className, std::move(object));
    } catch (const CodedError &error) {
      rollbackStagedObject(context, objectId);
      throw CodedError(error);
    } catch (const jsi::JSError &error) {
      rollbackStagedObject(context, objectId);
      throw jsi::JSError(error);
    } catch (const std::exception &error) {
      rollbackStagedObject(context, objectId);
      throw std::runtime_error(error.what());
    } catch (...) {
      rollbackStagedObject(context, objectId);
      throw std::runtime_error(
          "Unknown native exception while decoding an ArkTS SharedObject.");
    }
  }
  jsi::Object result(runtime);
  for (const auto &item : value.items()) {
    if (!item.first.isString()) {
      throw CodedError(
          "ERR_ARKTS_MODULE_VALUE",
          "ArkTS returned an object with a non-string key.");
    }
    result.setProperty(
        runtime,
        item.first.asString().c_str(),
        decodeArkTSValue(
            context,
            item.second,
            staged,
            createdObjectIds,
            depth + 1));
  }
  return result;
}

void collectTypedAuthorIds(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    std::vector<uint64_t> &result,
    size_t depth) {
  if (depth > kMaxValueDepth || !value.isObject()) {
    return;
  }
  auto object = value.getObject(runtime);
  if (object.isFunction(runtime) || object.isArrayBuffer(runtime) || isArrayBufferView(runtime, object)) {
    return;
  }
  if (object.hasProperty(runtime, kMarker)) {
    collectAuthorIds(jsi::dynamicFromValue(runtime, value), result);
    return;
  }
  if (object.isArray(runtime)) {
    auto array = object.getArray(runtime);
    for (size_t index = 0; index < array.size(runtime); ++index) {
      collectTypedAuthorIds(
          runtime, array.getValueAtIndex(runtime, index), result, depth + 1);
    }
    return;
  }
  auto names = object.getPropertyNames(runtime);
  for (size_t index = 0; index < names.size(runtime); ++index) {
    auto name = names.getValueAtIndex(runtime, index);
    if (!name.isString()) {
      continue;
    }
    collectTypedAuthorIds(
        runtime,
        object.getProperty(runtime, name.getString(runtime)),
        result,
        depth + 1);
  }
}

void discardTypedAuthorIds(
    const std::shared_ptr<RuntimeContext> &context,
    jsi::Runtime &runtime,
    const jsi::Value &value) noexcept {
  try {
    std::vector<uint64_t> authorIds;
    collectTypedAuthorIds(runtime, value, authorIds, 0);
    discardAuthorIds(context, authorIds);
  } catch (...) {
  }
}

jsi::Value decodeTypedArkTSValue(
    const std::shared_ptr<RuntimeContext> &context,
    const jsi::Value &value,
    std::unordered_map<uint64_t, std::shared_ptr<ArkTSSharedObject>> &staged,
    std::unordered_set<long> &createdObjectIds,
    size_t depth) {
  if (depth > kMaxValueDepth) {
    throw CodedError(
        "ERR_ARKTS_MODULE_VALUE",
        "An ArkTS Expo module typed value exceeds the maximum nesting depth.");
  }
  auto &runtime = context->runtime();
  if (!value.isObject()) {
    return jsi::Value(runtime, value);
  }
  auto object = value.getObject(runtime);
  if (object.isFunction(runtime) || object.isArrayBuffer(runtime) || isArrayBufferView(runtime, object)) {
    return jsi::Value(runtime, value);
  }
  if (object.hasProperty(runtime, kMarker)) {
    // Preserve TypedArrays when decoding records containing SharedObjects.
    return decodeArkTSValue(
        context,
        jsi::dynamicFromValue(runtime, value),
        staged,
        createdObjectIds,
        depth);
  }
  if (object.isArray(runtime)) {
    auto source = object.getArray(runtime);
    jsi::Array result(runtime, source.size(runtime));
    for (size_t index = 0; index < source.size(runtime); ++index) {
      auto item = source.getValueAtIndex(runtime, index);
      result.setValueAtIndex(
          runtime,
          index,
          decodeTypedArkTSValue(
              context, item, staged, createdObjectIds, depth + 1));
    }
    return result;
  }
  jsi::Object result(runtime);
  auto names = object.getPropertyNames(runtime);
  for (size_t index = 0; index < names.size(runtime); ++index) {
    auto nameValue = names.getValueAtIndex(runtime, index);
    if (!nameValue.isString()) {
      continue;
    }
    auto name = nameValue.getString(runtime);
    auto property = object.getProperty(runtime, name);
    result.setProperty(
        runtime,
        name,
        decodeTypedArkTSValue(
            context, property, staged, createdObjectIds, depth + 1));
  }
  return result;
}

jsi::Value decodeTypedValueGraph(
    const std::shared_ptr<RuntimeContext> &context,
    const jsi::Value &value,
    const std::function<void()> &commit) {
  auto &runtime = context->runtime();
  std::unordered_map<uint64_t, std::shared_ptr<ArkTSSharedObject>> staged;
  std::unordered_set<long> createdObjectIds;
  try {
    auto result = decodeTypedArkTSValue(
        context, value, staged, createdObjectIds, 0);
    if (commit) {
      commit();
    }
    return result;
  } catch (const CodedError &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardTypedAuthorIds(context, runtime, value);
    throw CodedError(error);
  } catch (const jsi::JSError &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardTypedAuthorIds(context, runtime, value);
    throw jsi::JSError(error);
  } catch (const std::exception &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardTypedAuthorIds(context, runtime, value);
    throw std::runtime_error(error.what());
  } catch (...) {
    rollbackStagedObjects(context, createdObjectIds);
    discardTypedAuthorIds(context, runtime, value);
    throw std::runtime_error(
        "Unknown native exception while decoding an ArkTS typed value.");
  }
}

std::vector<jsi::Value> decodeTypedValueArray(
    const std::shared_ptr<RuntimeContext> &context,
    const jsi::Value &values) {
  auto &runtime = context->runtime();
  if (!values.isObject() || !values.getObject(runtime).isArray(runtime)) {
    throw CodedError(
        "ERR_ARKTS_MODULE_VALUE",
        "ArkTS Expo module typed event arguments must be an array.");
  }
  auto array = values.getObject(runtime).getArray(runtime);
  std::unordered_map<uint64_t, std::shared_ptr<ArkTSSharedObject>> staged;
  std::unordered_set<long> createdObjectIds;
  std::vector<jsi::Value> result;
  result.reserve(array.size(runtime));
  try {
    for (size_t index = 0; index < array.size(runtime); ++index) {
      auto item = array.getValueAtIndex(runtime, index);
      result.push_back(decodeTypedArkTSValue(
          context, item, staged, createdObjectIds, 0));
    }
    return result;
  } catch (const CodedError &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardTypedAuthorIds(context, runtime, values);
    throw CodedError(error);
  } catch (const jsi::JSError &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardTypedAuthorIds(context, runtime, values);
    throw jsi::JSError(error);
  } catch (const std::exception &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardTypedAuthorIds(context, runtime, values);
    throw std::runtime_error(error.what());
  } catch (...) {
    rollbackStagedObjects(context, createdObjectIds);
    discardTypedAuthorIds(context, runtime, values);
    throw std::runtime_error(
        "Unknown native exception while decoding ArkTS typed arguments.");
  }
}

struct DecodedRejection final {
  std::string code;
  std::string message;
  std::optional<std::string> path;
  std::shared_ptr<const CodedError> cause;
};

DecodedRejection decodeRejectionValue(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    size_t depth) {
  DecodedRejection result{
      "ERR_ARKTS_MODULE",
      depth == 0
          ? "The ArkTS Expo module rejected its Promise."
          : "The ArkTS Expo module reported an underlying error.",
      std::nullopt,
      nullptr};

  if (value.isString()) {
    result.message = value.getString(runtime).utf8(runtime);
    return result;
  }
  if (!value.isObject()) {
    return result;
  }

  auto error = value.getObject(runtime);
  auto codeValue = error.getProperty(runtime, "code");
  auto messageValue = error.getProperty(runtime, "message");
  auto pathValue = error.getProperty(runtime, "path");
  if (codeValue.isString()) {
    result.code = codeValue.getString(runtime).utf8(runtime);
  }
  if (messageValue.isString()) {
    result.message = messageValue.getString(runtime).utf8(runtime);
  }
  if (pathValue.isString()) {
    result.path = pathValue.getString(runtime).utf8(runtime);
  }

  if (depth >= kMaxValueDepth) {
    return result;
  }
  auto causeValue = error.getProperty(runtime, "cause");
  if (!causeValue.isString() && !causeValue.isObject()) {
    return result;
  }
  auto decodedCause = decodeRejectionValue(runtime, causeValue, depth + 1);
  result.cause = std::make_shared<CodedError>(
      std::move(decodedCause.code),
      std::move(decodedCause.message),
      std::move(decodedCause.path),
      std::move(decodedCause.cause));
  return result;
}

DecodedRejection decodeRejection(
    jsi::Runtime &runtime,
    const jsi::Value *arguments,
    size_t count) noexcept {
  if (count == 0) {
    return {
        "ERR_ARKTS_MODULE",
        "The ArkTS Expo module rejected its Promise.",
        std::nullopt,
        nullptr};
  }
  try {
    return decodeRejectionValue(runtime, arguments[0], 0);
  } catch (...) {
  }
  return {
      "ERR_ARKTS_MODULE",
      "The ArkTS Expo module rejected its Promise.",
      std::nullopt,
      nullptr};
}

void adoptArkTSPromise(
    const std::shared_ptr<RuntimeContext> &context,
    const std::string &path,
    jsi::Value platformResult,
    const std::shared_ptr<Promise> &promise) {
  auto &runtime = context->runtime();
  if (!platformResult.isObject()) {
    throw CodedError("ERR_ARKTS_MODULE", path + " did not return a Promise.");
  }
  auto platformPromise = platformResult.getObject(runtime);
  auto thenValue = platformPromise.getProperty(runtime, "then");
  if (!thenValue.isObject() || !thenValue.getObject(runtime).isFunction(runtime)) {
    throw CodedError("ERR_ARKTS_MODULE", path + " did not return a Promise.");
  }
  auto onFulfilled = jsi::Function::createFromHostFunction(
      runtime,
      jsi::PropNameID::forAscii(runtime, "resolveArkTSExpoModulePromise"),
      1,
      [context, promise](
          jsi::Runtime &callbackRuntime,
          const jsi::Value &,
          const jsi::Value *arguments,
          size_t count) {
        try {
          auto value = count == 0
                         ? jsi::Value::undefined()
                         : jsi::Value(callbackRuntime, arguments[0]);
          auto holder = std::make_shared<ArkTSTypedResultHolder>(
              callbackRuntime, std::move(value));
          react::LongLivedObjectCollection::get(callbackRuntime).add(holder);
          auto accepted = promise->tryResolve(
              [context,
               weakHolder = std::weak_ptr<ArkTSTypedResultHolder>(holder)](
                  jsi::Runtime &) {
                auto resultHolder = weakHolder.lock();
                if (!resultHolder) {
                  throw CodedError(
                      "ERR_RUNTIME_DESTROYED",
                      "The ArkTS Promise result was released with its JavaScript runtime.");
                }
                return decodeTypedResult(context, resultHolder->take());
              });
          if (!accepted) {
            holder->allowRelease();
          }
        } catch (const std::exception &error) {
          promise->reject(
              "ERR_ARKTS_MODULE_VALUE",
              "The ArkTS Expo module returned an unsupported value: " + std::string(error.what()));
        } catch (...) {
          promise->reject(
              "ERR_ARKTS_MODULE_VALUE",
              "The ArkTS Expo module returned an unsupported value.");
        }
        return jsi::Value::undefined();
      });
  auto onRejected = jsi::Function::createFromHostFunction(
      runtime,
      jsi::PropNameID::forAscii(runtime, "rejectArkTSExpoModulePromise"),
      1,
      [promise](
          jsi::Runtime &callbackRuntime,
          const jsi::Value &,
          const jsi::Value *arguments,
          size_t count) {
        auto rejection = decodeRejection(callbackRuntime, arguments, count);
        promise->reject(CodedError(
            std::move(rejection.code),
            std::move(rejection.message),
            std::move(rejection.path),
            std::move(rejection.cause)));
        return jsi::Value::undefined();
      });
  thenValue.getObject(runtime).getFunction(runtime).callWithThis(
      runtime,
      platformPromise,
      std::move(onFulfilled),
      std::move(onRejected));
}

template <typename Invoke>
void invokeAsync(
    Invocation &invocation,
    const std::shared_ptr<Promise> &promise,
    const std::shared_ptr<NativeSharedObject> &receiver,
    Invoke invoke) {
  auto context = invocation.sharedContext();
  auto encoded = encodeTypedArguments(invocation, receiver);
  auto leases = retainInvocationLeases(context, encoded.sharedObjects);
  if (leases) {
    promise->retainUntilSettled(std::move(leases));
  }
  auto &runtime = invocation.runtime();
  jsi::Array arguments(runtime, encoded.values.size());
  for (size_t index = 0; index < encoded.values.size(); ++index) {
    arguments.setValueAtIndex(
        runtime, index, std::move(encoded.values[index]));
  }
  auto platformResult = invoke(
      context, jsi::Value(std::move(arguments)));
  adoptArkTSPromise(context, invocation.path(), std::move(platformResult), promise);
}

std::vector<std::string> requireEvents(
    const folly::dynamic &object,
    const std::string &path) {
  const auto &events = requireArray(object, "events", path);
  std::unordered_set<std::string> seen;
  std::vector<std::string> result;
  for (const auto &event : events) {
    if (!event.isString() || event.asString().empty() || !seen.insert(event.asString()).second) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          path + ".events must contain unique non-empty strings.");
    }
    result.push_back(event.asString());
  }
  return result;
}

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ArkTSModuleAdapter::createModules(
    const std::shared_ptr<RuntimeContext> &context) {
  const auto runtimeEpoch = context->runtimeEpochString();
  try {
    context->callPlatformSync("bindExpoModuleRuntime", {runtimeEpoch});
  } catch (const CodedError &error) {
    throw CodedError(error);
  } catch (const std::exception &error) {
    throw CodedError(
        "ERR_ARKTS_MODULE_RUNTIME_BIND",
        "The ArkTS Expo module runtime could not be bound: " + std::string(error.what()));
  }

  jsi::Value value;
  try {
    value = context->callPlatformSync(
        "getExpoModuleDescriptors", {runtimeEpoch});
  } catch (const CodedError &error) {
    throw CodedError(error);
  } catch (const std::exception &error) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR_READ",
        "The ArkTS Expo module descriptors could not be read: " + std::string(error.what()));
  }

  folly::dynamic descriptors;
  try {
    descriptors = jsi::dynamicFromValue(context->runtime(), value);
  } catch (const std::exception &error) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR_TRANSPORT",
        "The ArkTS Expo module descriptors could not cross the JSI copy-value boundary: " + std::string(error.what()));
  }
  if (!descriptors.isArray()) {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR",
        "ExpoModulesCore.getExpoModuleDescriptors() must return an array.");
  }
  std::vector<std::shared_ptr<ExpoModule>> result;
  result.reserve(descriptors.size());
  for (auto &descriptor : descriptors) {
    result.push_back(
        std::make_shared<ArkTSModuleAdapter>(std::move(descriptor)));
  }
  return result;
}

ArkTSModuleAdapter::ArkTSModuleAdapter(folly::dynamic descriptor)
    : descriptor_(std::move(descriptor)) {}

jsi::Value ArkTSModuleAdapter::decodeValue(
    const std::shared_ptr<RuntimeContext> &context,
    const folly::dynamic &value) {
  std::unordered_map<uint64_t, std::shared_ptr<ArkTSSharedObject>> staged;
  std::unordered_set<long> createdObjectIds;
  try {
    return decodeArkTSValue(context, value, staged, createdObjectIds, 0);
  } catch (const CodedError &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardAuthorIds(context, value);
    throw CodedError(error);
  } catch (const jsi::JSError &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardAuthorIds(context, value);
    throw jsi::JSError(error);
  } catch (const std::exception &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardAuthorIds(context, value);
    throw std::runtime_error(error.what());
  } catch (...) {
    rollbackStagedObjects(context, createdObjectIds);
    discardAuthorIds(context, value);
    throw std::runtime_error(
        "Unknown native exception while decoding an ArkTS value.");
  }
}

std::vector<jsi::Value> ArkTSModuleAdapter::decodeValues(
    const std::shared_ptr<RuntimeContext> &context,
    const folly::dynamic &values) {
  if (!values.isArray()) {
    throw CodedError(
        "ERR_ARKTS_MODULE_VALUE",
        "ArkTS Expo module arguments must be an array.");
  }
  std::unordered_map<uint64_t, std::shared_ptr<ArkTSSharedObject>> staged;
  std::unordered_set<long> createdObjectIds;
  std::vector<jsi::Value> result;
  result.reserve(values.size());
  try {
    for (const auto &value : values) {
      result.push_back(
          decodeArkTSValue(context, value, staged, createdObjectIds, 0));
    }
    return result;
  } catch (const CodedError &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardAuthorIds(context, values);
    throw CodedError(error);
  } catch (const jsi::JSError &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardAuthorIds(context, values);
    throw jsi::JSError(error);
  } catch (const std::exception &error) {
    rollbackStagedObjects(context, createdObjectIds);
    discardAuthorIds(context, values);
    throw std::runtime_error(error.what());
  } catch (...) {
    rollbackStagedObjects(context, createdObjectIds);
    discardAuthorIds(context, values);
    throw std::runtime_error(
        "Unknown native exception while decoding ArkTS arguments.");
  }
}

std::vector<jsi::Value> ArkTSModuleAdapter::decodeTypedValues(
    const std::shared_ptr<RuntimeContext> &context,
    const jsi::Value &values) {
  return decodeTypedValueArray(context, values);
}

void ArkTSModuleAdapter::discardValues(
    const std::shared_ptr<RuntimeContext> &context,
    const folly::dynamic &values) noexcept {
  discardAuthorIds(context, values);
}

ModuleDefinition ArkTSModuleAdapter::definition() {
  const auto moduleName = requireString(
      descriptor_, "name", "ArkTS Expo module descriptor");
  if (moduleName == "ExpoModulesCore") {
    throw CodedError(
        "ERR_ARKTS_MODULE_DESCRIPTOR",
        "ArkTS Expo module '" + moduleName + "' uses a reserved module name.");
  }
  ModuleDefinitionBuilder builder(moduleName);
  const auto modulePath = "ArkTS Expo module '" + moduleName + "'";

  std::unordered_set<std::string> constantNames;
  for (const auto &constant : requireArray(descriptor_, "constants", modulePath)) {
    auto name = requireString(constant, "name", modulePath + " constant");
    if (!constantNames.insert(name).second) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          modulePath + " defines constant '" + name + "' more than once.");
    }
    builder.constant(
        name,
        [moduleName, name](Invocation &invocation) {
          auto context = invocation.sharedContext();
          auto result = context->callPlatformSyncTyped(
              "getExpoModuleConstant",
              makeTypedArguments(
                  invocation.runtime(),
                  context->runtimeEpochString(),
                  moduleName,
                  name));
          return decodeTypedResult(context, std::move(result));
        });
  }

  std::unordered_set<std::string> functionNames;
  for (const auto &function : requireArray(descriptor_, "functions", modulePath)) {
    auto name = requireString(function, "name", modulePath + " function");
    const auto path = modulePath + " function '" + name + "'";
    const auto arity = requireArity(function, path);
    const auto requiredArity = requireArityField(
        function, "requiredArity", path);
    if (requiredArity > arity) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          path + ".requiredArity cannot exceed .arity.");
    }
    const auto async = requireBoolean(function, "async", path);
    const auto writableIndices = writableArgumentIndices(function, arity, async, path);
    if (!functionNames.insert(name).second) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          modulePath + " defines function '" + name + "' more than once.");
    }
    if (async) {
      builder.asyncFunction(FunctionDefinition{
          .name = name,
          .arity = arity,
          .requiredArity = requiredArity,
          .async = true,
          .asyncBody = [moduleName, name](
                           Invocation &invocation,
                           const std::shared_ptr<Promise> &promise) {
            invokeAsync(
                invocation,
                promise,
                nullptr,
                [moduleName, name](
                    const std::shared_ptr<RuntimeContext> &context,
                    jsi::Value arguments) {
                  return context->callPlatformAsyncTyped(
                      "invokeExpoModuleAsync",
                      makeTypedValueArguments(
                          context->runtime(),
                          arguments,
                          context->runtimeEpochString(),
                          moduleName,
                          name));
                });
          },
      });
    } else {
      builder.function(FunctionDefinition{
          .name = name,
          .arity = arity,
          .requiredArity = requiredArity,
          .body = [moduleName, name, writableIndices](Invocation &invocation) {
            auto context = invocation.sharedContext();
            auto &runtime = invocation.runtime();
            std::optional<SynchronousBinaryWriteBack> writeBack;
            if (!writableIndices.empty()) {
              writeBack.emplace(runtime);
            }
            for (const auto index : writableIndices) {
              if (index >= invocation.argumentCount()) {
                throw CodedError("ERR_WRITABLE_ARGUMENT", "A writable binary argument is missing.");
              }
              writeBack->add(invocation.argument(index));
            }
            auto encoded = encodeTypedArguments(invocation);
            auto arguments = takeTypedArgumentArray(
                invocation.runtime(), std::move(encoded.values));
            auto result = context->callPlatformSyncTyped(
                "invokeExpoModuleSync",
                makeTypedValueArguments(
                    invocation.runtime(),
                    arguments,
                    context->runtimeEpochString(),
                    moduleName,
                    name),
                writeBack ? &*writeBack : nullptr);
            if (writableIndices.empty()) {
              return decodeTypedResult(context, std::move(result));
            }
            return decodeTypedValueGraph(context, result, [&]() {
              writeBack->commit(*context);
            });
          },
      });
    }
  }

  std::unordered_set<std::string> propertyNames;
  for (const auto &property : requireArray(descriptor_, "properties", modulePath)) {
    auto name = requireString(property, "name", modulePath + " property");
    if (!propertyNames.insert(name).second) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          modulePath + " defines property '" + name + "' more than once.");
    }
    const auto writable = requireBoolean(
        property, "writable", modulePath + " property '" + name + "'");
    PropertyDefinition definition{
        .name = name,
        .getter = [moduleName, name](Invocation &invocation) {
          auto context = invocation.sharedContext();
          auto result = context->callPlatformSyncTyped(
              "getExpoModuleProperty",
              makeTypedArguments(
                  invocation.runtime(),
                  context->runtimeEpochString(),
                  moduleName,
                  name));
          return decodeTypedResult(context, std::move(result));
        },
    };
    if (writable) {
      definition.setter = [moduleName, name](
                              Invocation &invocation,
                              const jsi::Value &value) {
        std::vector<std::shared_ptr<NativeSharedObject>> referenced;
        auto context = invocation.sharedContext();
        auto encoded = encodeTypedJSIValue(
            context, invocation.runtime(), value, referenced, 0);
        context->callPlatformSyncTyped(
            "setExpoModuleProperty",
            makeTypedValueArguments(
                invocation.runtime(),
                encoded,
                context->runtimeEpochString(),
                moduleName,
                name));
      };
    }
    builder.property(std::move(definition));
  }
  builder.events(requireEvents(descriptor_, modulePath));
  // Forward listener transitions to the runtime-scoped ArkTS definition.
  builder.onStartObserving(
      [moduleName](RuntimeContext &context, const std::string &eventName) {
        context.callPlatformSync(
            "setExpoModuleObserving",
            {context.runtimeEpochString(), moduleName, eventName, true});
      });
  builder.onStopObserving(
      [moduleName](RuntimeContext &context, const std::string &eventName) {
        context.callPlatformSync(
            "setExpoModuleObserving",
            {context.runtimeEpochString(), moduleName, eventName, false});
      });

  std::unordered_set<std::string> classNames;
  for (const auto &classDescriptor :
       requireArray(descriptor_, "classes", modulePath)) {
    auto className = requireString(
        classDescriptor, "name", modulePath + " class");
    const auto classPath = modulePath + " class '" + className + "'";
    if (!classNames.insert(className).second) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          modulePath + " defines class '" + className + "' more than once.");
    }
    ClassDefinition klass;
    klass.name = className;
    klass.baseClassName = requireString(
        classDescriptor, "baseClassName", classPath);
    const auto nativeRefType = requireString(
        classDescriptor, "nativeRefType", classPath);
    const auto constructible = requireBoolean(
        classDescriptor, "constructible", classPath);
    klass.constructorArity = requireArityField(
        classDescriptor, "constructorArity", classPath);
    klass.constructorRequiredArity = requireArityField(
        classDescriptor, "constructorRequiredArity", classPath);
    if (klass.constructorRequiredArity > klass.constructorArity) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          classPath + ".constructorRequiredArity cannot exceed .constructorArity.");
    }
    klass.constructor = [moduleName,
                         className,
                         nativeRefType,
                         constructible](Invocation &invocation) {
      if (!constructible) {
        throw CodedError(
            "ERR_SHARED_OBJECT_CONSTRUCTOR",
            "Expo SharedObject class '" + moduleName + "." + className + "' is not constructible from JavaScript.");
      }
      auto context = invocation.sharedContext();
      auto object = std::make_shared<ArkTSSharedObject>(
          context,
          context->runtimeEpochString(),
          moduleName,
          className,
          nativeRefType);
      auto objectId = context->registerNativeSharedObject(object);
      object->bindObjectId(objectId);
      try {
        auto encoded = encodeTypedArguments(invocation);
        auto arguments = takeTypedArgumentArray(
            invocation.runtime(), std::move(encoded.values));
        context->callPlatformSyncTyped(
            "constructExpoSharedObject",
            makeTypedValueArguments(
                invocation.runtime(),
                arguments,
                context->runtimeEpochString(),
                objectId,
                moduleName,
                className,
                nativeRefType));
        loadMemoryPressure(context, object);
        return std::shared_ptr<NativeSharedObject>(std::move(object));
      } catch (const CodedError &error) {
        rollbackStagedObject(context, objectId);
        throw CodedError(error);
      } catch (const jsi::JSError &error) {
        rollbackStagedObject(context, objectId);
        throw jsi::JSError(error);
      } catch (const std::exception &error) {
        rollbackStagedObject(context, objectId);
        throw std::runtime_error(error.what());
      } catch (...) {
        rollbackStagedObject(context, objectId);
        throw std::runtime_error(
            "Unknown native exception while constructing an ArkTS SharedObject.");
      }
    };

    std::unordered_set<std::string> classConstantNames;
    for (const auto &constant :
         requireArray(classDescriptor, "constants", classPath)) {
      auto name = requireString(constant, "name", classPath + " constant");
      if (!classConstantNames.insert(name).second) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR",
            classPath + " defines constant '" + name + "' more than once.");
      }
      klass.constants.emplace_back(
          name,
          [moduleName, className, name](Invocation &invocation) {
            auto context = invocation.sharedContext();
            auto result = context->callPlatformSyncTyped(
                "getExpoSharedObjectConstant",
                makeTypedArguments(
                    invocation.runtime(),
                    context->runtimeEpochString(),
                    moduleName,
                    className,
                    name));
            return decodeTypedResult(context, std::move(result));
          });
    }

    std::unordered_set<std::string> memberNames;
    for (const auto &function :
         requireArray(classDescriptor, "functions", classPath)) {
      auto name = requireString(function, "name", classPath + " function");
      const auto memberPath = classPath + " function '" + name + "'";
      const auto arity = requireArity(function, memberPath);
      const auto requiredArity = requireArityField(
          function, "requiredArity", memberPath);
      if (requiredArity > arity) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR",
            memberPath + ".requiredArity cannot exceed .arity.");
      }
      const auto async = requireBoolean(function, "async", memberPath);
      if (!memberNames.insert(name).second) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR", memberPath + " is duplicated.");
      }
      SharedObjectFunctionDefinition definition{
          .name = name,
          .arity = arity,
          .requiredArity = requiredArity,
          .async = async,
      };
      if (async) {
        definition.asyncBody = [moduleName, className, name](
                                   Invocation &invocation,
                                   const std::shared_ptr<NativeSharedObject> &receiver,
                                   const std::shared_ptr<Promise> &promise) {
          auto object = requireArkTSObject(receiver, invocation.path());
          invokeAsync(
              invocation,
              promise,
              object,
              [object, moduleName, className, name](
                  const std::shared_ptr<RuntimeContext> &context,
                  jsi::Value arguments) {
                return context->callPlatformAsyncTyped(
                    "invokeExpoSharedObjectAsync",
                    makeTypedValueArguments(
                        context->runtime(),
                        arguments,
                        context->runtimeEpochString(),
                        object->objectId(),
                        moduleName,
                        className,
                        name));
              });
        };
      } else {
        definition.body = [moduleName, className, name](
                              Invocation &invocation,
                              const std::shared_ptr<NativeSharedObject> &receiver) {
          auto object = requireArkTSObject(receiver, invocation.path());
          auto context = invocation.sharedContext();
          auto encoded = encodeTypedArguments(invocation, object);
          auto arguments = takeTypedArgumentArray(
              invocation.runtime(), std::move(encoded.values));
          auto result = context->callPlatformSyncTyped(
              "invokeExpoSharedObjectSync",
              makeTypedValueArguments(
                  invocation.runtime(),
                  arguments,
                  context->runtimeEpochString(),
                  object->objectId(),
                  moduleName,
                  className,
                  name));
          return decodeTypedResult(context, std::move(result));
        };
      }
      klass.functions.push_back(std::move(definition));
    }

    std::unordered_set<std::string> staticNames;
    for (const auto &function :
         requireArray(classDescriptor, "staticFunctions", classPath)) {
      auto name = requireString(
          function, "name", classPath + " static function");
      const auto memberPath = classPath + " static function '" + name + "'";
      const auto arity = requireArity(function, memberPath);
      const auto requiredArity = requireArityField(
          function, "requiredArity", memberPath);
      if (requiredArity > arity) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR",
            memberPath + ".requiredArity cannot exceed .arity.");
      }
      const auto async = requireBoolean(function, "async", memberPath);
      if (!staticNames.insert(name).second) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR", memberPath + " is duplicated.");
      }
      FunctionDefinition definition{
          .name = name,
          .arity = arity,
          .requiredArity = requiredArity,
          .async = async,
      };
      if (async) {
        definition.asyncBody = [moduleName, className, name](
                                   Invocation &invocation,
                                   const std::shared_ptr<Promise> &promise) {
          invokeAsync(
              invocation,
              promise,
              nullptr,
              [moduleName, className, name](
                  const std::shared_ptr<RuntimeContext> &context,
                  jsi::Value arguments) {
                return context->callPlatformAsyncTyped(
                    "invokeExpoSharedObjectStaticAsync",
                    makeTypedValueArguments(
                        context->runtime(),
                        arguments,
                        context->runtimeEpochString(),
                        moduleName,
                        className,
                        name));
              });
        };
      } else {
        definition.body = [moduleName, className, name](Invocation &invocation) {
          auto context = invocation.sharedContext();
          auto encoded = encodeTypedArguments(invocation);
          auto arguments = takeTypedArgumentArray(
              invocation.runtime(), std::move(encoded.values));
          auto result = context->callPlatformSyncTyped(
              "invokeExpoSharedObjectStaticSync",
              makeTypedValueArguments(
                  invocation.runtime(),
                  arguments,
                  context->runtimeEpochString(),
                  moduleName,
                  className,
                  name));
          return decodeTypedResult(context, std::move(result));
        };
      }
      klass.staticFunctions.push_back(std::move(definition));
    }

    std::unordered_set<std::string> propertyNames;
    for (const auto &property :
         requireArray(classDescriptor, "properties", classPath)) {
      auto name = requireString(property, "name", classPath + " property");
      if (!propertyNames.insert(name).second) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR",
            classPath + " property '" + name + "' is duplicated.");
      }
      const auto writable = requireBoolean(
          property, "writable", classPath + " property '" + name + "'");
      SharedObjectPropertyDefinition definition{
          .name = name,
          .getter = [moduleName, className, name](
                        Invocation &invocation,
                        const std::shared_ptr<NativeSharedObject> &receiver) {
            auto object = requireArkTSObject(receiver, invocation.path());
            auto context = invocation.sharedContext();
            auto result = context->callPlatformSyncTyped(
                "getExpoSharedObjectProperty",
                makeTypedArguments(
                    invocation.runtime(),
                    context->runtimeEpochString(),
                    object->objectId(),
                    moduleName,
                    className,
                    name));
            return decodeTypedResult(context, std::move(result));
          },
      };
      if (writable) {
        definition.setter = [moduleName, className, name](
                                Invocation &invocation,
                                const std::shared_ptr<NativeSharedObject> &receiver,
                                const jsi::Value &value) {
          auto object = requireArkTSObject(receiver, invocation.path());
          std::vector<std::shared_ptr<NativeSharedObject>> referenced{object};
          auto context = invocation.sharedContext();
          auto encoded = encodeTypedJSIValue(
              context, invocation.runtime(), value, referenced, 0);
          context->callPlatformSyncTyped(
              "setExpoSharedObjectProperty",
              makeTypedValueArguments(
                  invocation.runtime(),
                  encoded,
                  context->runtimeEpochString(),
                  object->objectId(),
                  moduleName,
                  className,
                  name));
        };
      }
      klass.properties.push_back(std::move(definition));
    }

    auto events = requireEvents(classDescriptor, classPath);
    klass.events.insert(events.begin(), events.end());
    builder.klass(std::move(klass));
  }

  std::unordered_set<std::string> viewNames;
  std::unordered_set<std::string> componentNames;
  std::unordered_set<std::string> prototypeNames;
  for (const auto &viewDescriptor :
       requireArray(descriptor_, "views", modulePath)) {
    auto viewName = requireString(
        viewDescriptor, "name", modulePath + " view");
    const auto viewPath = modulePath + " view '" + viewName + "'";
    if (!viewNames.insert(viewName).second) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          viewPath + " is duplicated.");
    }
    auto componentName = requireString(
        viewDescriptor, "componentName", viewPath);
    auto prototypeName = requireString(
        viewDescriptor, "prototypeName", viewPath);
    if (!componentNames.insert(componentName).second) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          viewPath + " duplicates Fabric component '" + componentName + "'.");
    }
    if (!prototypeNames.insert(prototypeName).second) {
      throw CodedError(
          "ERR_ARKTS_MODULE_DESCRIPTOR",
          viewPath + " duplicates prototype '" + prototypeName + "'.");
    }

    ViewDefinition view;
    view.name = std::move(viewName);
    view.componentName = componentName;
    view.prototypeName = std::move(prototypeName);
    view.usesGenericFabricComponent = true;
    view.defaultView = requireBoolean(viewDescriptor, "defaultView", viewPath);
    view.group = requireBoolean(viewDescriptor, "group", viewPath);
    std::vector<std::string> componentNames{componentName};
    if (view.defaultView) {
      auto defaultComponentName = "ViewManagerAdapter_" + moduleName;
      if (defaultComponentName != componentName) {
        componentNames.push_back(std::move(defaultComponentName));
      }
    }

    std::unordered_set<std::string> propNames;
    for (const auto &prop : requireArray(viewDescriptor, "props", viewPath)) {
      auto propName = requireString(prop, "name", viewPath + " prop");
      if (!propNames.insert(propName).second) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR",
            viewPath + " prop '" + propName + "' is duplicated.");
      }
      // Only prop names cross the native descriptor boundary.
      view.props.push_back(ViewPropDefinition{.name = std::move(propName)});
    }
    view.events = requireEvents(viewDescriptor, viewPath);

    std::unordered_set<std::string> viewFunctionNames;
    for (const auto &function :
         requireArray(viewDescriptor, "functions", viewPath)) {
      auto name = requireString(function, "name", viewPath + " function");
      const auto functionPath = viewPath + " function '" + name + "'";
      const auto arity = requireArity(function, functionPath);
      const auto requiredArity = requireArityField(
          function, "requiredArity", functionPath);
      if (requiredArity > arity) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR",
            functionPath + ".requiredArity cannot exceed .arity.");
      }
      const auto async = requireBoolean(function, "async", functionPath);
      if (!async) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR",
            functionPath + " must be async, matching Expo's View definition contract.");
      }
      if (!viewFunctionNames.insert(name).second) {
        throw CodedError(
            "ERR_ARKTS_MODULE_DESCRIPTOR",
            functionPath + " is duplicated.");
      }
      view.functions.push_back(FunctionDefinition{
          .name = name,
          .arity = arity,
          .requiredArity = requiredArity,
          .async = true,
          .asyncBody = [componentNames, name](
                           Invocation &invocation,
                           const std::shared_ptr<Promise> &promise) {
            const auto handle = requireViewHandle(invocation, componentNames);
            invokeAsync(
                invocation,
                promise,
                nullptr,
                [tag = handle.tag(),
                 componentName = handle.componentName(),
                 propsRevision = handle.propsRevision(),
                 name](
                    const std::shared_ptr<RuntimeContext> &context,
                    jsi::Value arguments) {
                  return context->callPlatformAsyncTyped(
                      "invokeExpoViewAsync",
                      makeTypedValueArguments(
                          context->runtime(),
                          arguments,
                          context->runtimeEpochString(),
                          tag,
                          componentName,
                          propsRevision,
                          name));
                });
          },
      });
    }
    builder.view(std::move(view));
  }
  return std::move(builder).build();
}

}  // namespace expo::harmony
