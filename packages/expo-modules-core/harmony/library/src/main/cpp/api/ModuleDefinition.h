#pragma once

#include <cstddef>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <typeindex>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <jsi/jsi.h>

#include <folly/dynamic.h>

#include "api/SharedObjectEventArgument.h"

namespace expo::harmony {

class RuntimeContext;
class Promise;

enum class FunctionQueue {
  JavaScript,
  Main,
  Modules,
  Background,
  UI,
};

class Invocation final {
public:
  Invocation(
      std::shared_ptr<RuntimeContext> context,
      std::string path,
      facebook::jsi::Runtime &runtime,
      const facebook::jsi::Value &thisValue,
      const facebook::jsi::Value *arguments,
      size_t argumentCount);

  RuntimeContext &context() const;
  std::shared_ptr<RuntimeContext> sharedContext() const;
  facebook::jsi::Runtime &runtime() const;
  const std::string &path() const noexcept;
  const facebook::jsi::Value &thisValue() const noexcept;
  size_t argumentCount() const noexcept;
  const facebook::jsi::Value &argument(size_t index) const;
  void requireArgumentCount(size_t required, size_t desired) const;

private:
  std::shared_ptr<RuntimeContext> context_;
  std::string path_;
  facebook::jsi::Runtime *runtime_;
  facebook::jsi::Value thisValue_;
  const facebook::jsi::Value *arguments_;
  size_t argumentCount_;
};

class NativeSharedObject {
public:
  virtual ~NativeSharedObject() = default;
  virtual std::string nativeRefType() const;
  virtual size_t getAdditionalMemoryPressure() const noexcept;
  virtual void deallocate();
  virtual void sharedObjectWillRelease();
  virtual void sharedObjectDidRelease();
  virtual void onStartListeningToEvent(const std::string &eventName);
  virtual void onStopListeningToEvent(const std::string &eventName);
  void sendEvent(
      std::string eventName,
      std::vector<folly::dynamic> arguments = {}) const;

  template <typename... Arguments>
  void sendEvent(std::string eventName, Arguments &&...arguments) const;

private:
  friend class RuntimeContext;
  void bindToRuntime(std::weak_ptr<RuntimeContext> context, long objectId);
  void unbindFromRuntime() noexcept;
  void sendEventWithArguments(
      std::string eventName,
      std::vector<SharedObjectEventArgument> arguments,
      bool containsJavaScriptValues) const;
  mutable std::mutex runtimeBindingMutex_;
  std::weak_ptr<RuntimeContext> runtimeContext_;
  long objectId_{0};
};

struct SharedObjectResult final {
  std::string moduleName;
  std::string className;
  std::shared_ptr<NativeSharedObject> object;
};

using ValueFactory = std::function<facebook::jsi::Value(Invocation &)>;
using FunctionBody = std::function<facebook::jsi::Value(Invocation &)>;
using AsyncFunctionBody = std::function<void(Invocation &, const std::shared_ptr<Promise> &)>;
using PropertyGetter = std::function<facebook::jsi::Value(Invocation &)>;
using PropertySetter = std::function<void(Invocation &, const facebook::jsi::Value &)>;
using SharedObjectConstructor = std::function<std::shared_ptr<NativeSharedObject>(Invocation &)>;
using SharedObjectFunctionBody = std::function<facebook::jsi::Value(
    Invocation &,
    const std::shared_ptr<NativeSharedObject> &)>;
using SharedObjectAsyncFunctionBody = std::function<void(
    Invocation &,
    const std::shared_ptr<NativeSharedObject> &,
    const std::shared_ptr<Promise> &)>;
using SharedObjectPropertyGetter = std::function<facebook::jsi::Value(
    Invocation &,
    const std::shared_ptr<NativeSharedObject> &)>;
using SharedObjectPropertySetter = std::function<void(
    Invocation &,
    const std::shared_ptr<NativeSharedObject> &,
    const facebook::jsi::Value &)>;
using SharedObjectObservationCallback = std::function<void(
    RuntimeContext &,
    const std::shared_ptr<NativeSharedObject> &,
    const std::string &)>;
using SharedObjectLifecycleObservationCallback = std::function<void(
    RuntimeContext &,
    const std::shared_ptr<NativeSharedObject> &)>;

struct ModuleEventObserver {
  std::optional<std::string> eventName;
  bool everyEvent{false};
  std::function<void(RuntimeContext &, const std::string &)> body;
};

struct SharedObjectEventObserver {
  std::optional<std::string> eventName;
  bool everyEvent{false};
  SharedObjectObservationCallback body;
};

struct FunctionDefinition {
  std::string name;
  size_t arity{0};
  std::optional<size_t> requiredArity;
  bool async{false};
  bool enumerable{true};
  FunctionQueue queue{FunctionQueue::JavaScript};
  FunctionBody body;
  AsyncFunctionBody asyncBody;
};

struct PropertyDefinition {
  std::string name;
  PropertyGetter getter;
  PropertySetter setter;
  bool enumerable{true};
};

struct SharedObjectFunctionDefinition {
  std::string name;
  size_t arity{0};
  std::optional<size_t> requiredArity;
  bool async{false};
  bool enumerable{true};
  FunctionQueue queue{FunctionQueue::JavaScript};
  SharedObjectFunctionBody body;
  SharedObjectAsyncFunctionBody asyncBody;
};

struct SharedObjectPropertyDefinition {
  std::string name;
  SharedObjectPropertyGetter getter;
  SharedObjectPropertySetter setter;
  bool enumerable{true};
};

struct ObjectDefinition {
  std::string name;
  std::vector<std::pair<std::string, ValueFactory>> constants;
  std::vector<FunctionDefinition> functions;
  std::vector<PropertyDefinition> properties;
};

struct ClassDefinition {
  std::string name;
  std::string baseClassName{"SharedObject"};
  std::type_index nativeType{typeid(void)};
  size_t constructorArity{0};
  std::optional<size_t> constructorRequiredArity;
  SharedObjectConstructor constructor;
  FunctionBody javaScriptConstructor;
  std::vector<std::pair<std::string, ValueFactory>> constants;
  std::vector<SharedObjectFunctionDefinition> functions;
  std::vector<SharedObjectPropertyDefinition> properties;
  std::vector<FunctionDefinition> javaScriptFunctions;
  std::vector<PropertyDefinition> javaScriptProperties;
  std::vector<FunctionDefinition> staticFunctions;
  std::vector<PropertyDefinition> staticProperties;
  std::unordered_set<std::string> events;
  std::vector<SharedObjectEventObserver> startObservers;
  std::vector<SharedObjectEventObserver> stopObservers;
};

using ViewLifecycleCallback = std::function<void(RuntimeContext &, int64_t, const std::string &)>;
using ViewPropCallback = std::function<void(
    RuntimeContext &,
    int64_t,
    const std::string &,
    const folly::dynamic &)>;
using ViewDidUpdateCallback = std::function<void(
    RuntimeContext &,
    int64_t,
    const std::string &,
    const folly::dynamic &)>;

struct ViewPropDefinition {
  std::string name;
  folly::dynamic defaultValue{nullptr};
  bool hasDefaultValue{false};
  ViewPropCallback setter;
};

struct ViewDefinition {
  std::string name;
  std::string componentName;
  std::string prototypeName;
  bool defaultView{false};
  bool group{false};
  std::vector<ViewPropDefinition> props;
  std::vector<std::string> events;
  std::vector<FunctionDefinition> functions;
  ViewLifecycleCallback onCreate;
  ViewDidUpdateCallback onDidUpdateProps;
  ViewLifecycleCallback onDestroy;
};

struct ModuleDefinition {
  std::string name;
  std::vector<std::pair<std::string, ValueFactory>> constants;
  std::vector<FunctionDefinition> functions;
  std::vector<PropertyDefinition> properties;
  std::unordered_set<std::string> events;
  std::vector<ObjectDefinition> objects;
  std::vector<ClassDefinition> classes;
  std::vector<ViewDefinition> views;
  std::function<void(RuntimeContext &)> onCreate;
  std::function<void(RuntimeContext &)> onRegisterActivityContracts;
  std::function<void(RuntimeContext &)> onDestroy;
  std::function<void(RuntimeContext &)> onForeground;
  std::function<void(RuntimeContext &)> onBackground;
  std::function<void(RuntimeContext &)> onUserLeaves;
  std::function<void(RuntimeContext &)> onActivityDestroy;
  std::function<void(RuntimeContext &, const folly::dynamic &)> onNewIntent;
  std::function<void(RuntimeContext &, int, int, const folly::dynamic &)>
      onActivityResult;
  std::vector<ModuleEventObserver> startObservers;
  std::vector<ModuleEventObserver> stopObservers;
};

class ModuleDefinitionBuilder final {
public:
  explicit ModuleDefinitionBuilder(std::string name);

  ModuleDefinitionBuilder &constant(std::string name, ValueFactory factory);
  ModuleDefinitionBuilder &function(FunctionDefinition definition);
  ModuleDefinitionBuilder &asyncFunction(FunctionDefinition definition);
  ModuleDefinitionBuilder &property(PropertyDefinition definition);
  ModuleDefinitionBuilder &events(std::vector<std::string> names);
  ModuleDefinitionBuilder &object(ObjectDefinition definition);
  ModuleDefinitionBuilder &klass(ClassDefinition definition);
  ModuleDefinitionBuilder &view(ViewDefinition definition);
  ModuleDefinitionBuilder &onCreate(std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onRegisterActivityContracts(
      std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onDestroy(std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onForeground(std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onBackground(std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onUserLeaves(std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onActivityDestroy(
      std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onNewIntent(
      std::function<void(RuntimeContext &, const folly::dynamic &)> body);
  ModuleDefinitionBuilder &onActivityResult(
      std::function<void(RuntimeContext &, int, int, const folly::dynamic &)> body);
  ModuleDefinitionBuilder &onStartObserving(
      std::function<void(RuntimeContext &, const std::string &)> body);
  ModuleDefinitionBuilder &onStartObserving(
      std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onStartObserving(
      std::string eventName,
      std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onStopObserving(
      std::function<void(RuntimeContext &, const std::string &)> body);
  ModuleDefinitionBuilder &onStopObserving(
      std::function<void(RuntimeContext &)> body);
  ModuleDefinitionBuilder &onStopObserving(
      std::string eventName,
      std::function<void(RuntimeContext &)> body);
  ModuleDefinition build() &&;

private:
  ModuleDefinition definition_;
};

void validateModuleDefinition(const ModuleDefinition &definition);

}  // namespace expo::harmony
