#include "ModuleDefinition.h"

#include <utility>

#include "errors/CodedError.h"
#include "runtime/RuntimeContext.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

Invocation::Invocation(
    std::shared_ptr<RuntimeContext> context,
    std::string path,
    jsi::Runtime &runtime,
    const jsi::Value &thisValue,
    const jsi::Value *arguments,
    size_t argumentCount)
    : context_(std::move(context)),
      path_(std::move(path)),
      runtime_(&runtime),
      thisValue_(runtime, thisValue),
      arguments_(arguments),
      argumentCount_(argumentCount) {}

RuntimeContext &Invocation::context() const {
  return *context_;
}

std::shared_ptr<RuntimeContext> Invocation::sharedContext() const {
  return context_;
}

jsi::Runtime &Invocation::runtime() const {
  context_->assertRuntimeThread();
  return *runtime_;
}

const std::string &Invocation::path() const noexcept {
  return path_;
}

const jsi::Value &Invocation::thisValue() const noexcept {
  return thisValue_;
}

size_t Invocation::argumentCount() const noexcept {
  return argumentCount_;
}

const jsi::Value &Invocation::argument(size_t index) const {
  if (index >= argumentCount_) {
    throw CodedError(
        "ERR_INVALID_ARGS_NUMBER",
        path_ + " is missing argument " + std::to_string(index) + ".");
  }
  return arguments_[index];
}

void Invocation::requireArgumentCount(size_t required, size_t desired) const {
  if (argumentCount_ < required || argumentCount_ > desired) {
    throw CodedError(
        "ERR_INVALID_ARGS_NUMBER",
        path_ + " expected " + (required == desired ? std::to_string(desired) : std::to_string(required) + " to " + std::to_string(desired)) + " arguments, received " + std::to_string(argumentCount_) + ".");
  }
}

std::string NativeSharedObject::nativeRefType() const {
  return "SharedObject";
}

size_t NativeSharedObject::getAdditionalMemoryPressure() const noexcept {
  return 0;
}

void NativeSharedObject::deallocate() {}

void NativeSharedObject::sharedObjectDidRelease() {
  deallocate();
}

void NativeSharedObject::bindToRuntime(
    std::weak_ptr<RuntimeContext> context,
    long objectId) {
  std::scoped_lock lock(runtimeBindingMutex_);
  runtimeContext_ = std::move(context);
  objectId_ = objectId;
}

void NativeSharedObject::unbindFromRuntime() noexcept {
  std::scoped_lock lock(runtimeBindingMutex_);
  runtimeContext_.reset();
  objectId_ = 0;
}

void NativeSharedObject::sendEvent(
    std::string eventName,
    std::vector<folly::dynamic> arguments) const {
  std::shared_ptr<RuntimeContext> context;
  long objectId = 0;
  {
    std::scoped_lock lock(runtimeBindingMutex_);
    context = runtimeContext_.lock();
    objectId = objectId_;
  }
  if (!context || !context->isAlive() || objectId == 0) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot emit an event from a SharedObject detached from its runtime.");
  }
  context->emitSharedObjectEvent(
      objectId, std::move(eventName), std::move(arguments));
}

ModuleDefinitionBuilder::ModuleDefinitionBuilder(std::string name) {
  definition_.name = std::move(name);
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::constant(
    std::string name,
    ValueFactory factory) {
  definition_.constants.emplace_back(std::move(name), std::move(factory));
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::function(
    FunctionDefinition definition) {
  definition.async = false;
  definition_.functions.push_back(std::move(definition));
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::asyncFunction(
    FunctionDefinition definition) {
  definition.async = true;
  definition_.functions.push_back(std::move(definition));
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::property(
    PropertyDefinition definition) {
  definition_.properties.push_back(std::move(definition));
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::events(
    std::vector<std::string> names) {
  definition_.events.insert(
      std::make_move_iterator(names.begin()),
      std::make_move_iterator(names.end()));
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::object(
    ObjectDefinition definition) {
  definition_.objects.push_back(std::move(definition));
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::klass(
    ClassDefinition definition) {
  definition_.classes.push_back(std::move(definition));
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::view(
    ViewDefinition definition) {
  const auto defaultView = definition.defaultView || definition_.views.empty();
  definition.defaultView = defaultView;
  if (definition.componentName.empty()) {
    definition.componentName = "ViewManagerAdapter_" + definition_.name;
    if (!defaultView) {
      definition.componentName += "_" + definition.name;
    }
  }
  if (definition.prototypeName.empty()) {
    definition.prototypeName = definition_.name;
    if (!defaultView) {
      definition.prototypeName += "_" + definition.name;
    }
  }
  definition_.views.push_back(std::move(definition));
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onCreate(
    std::function<void(RuntimeContext &)> body) {
  definition_.onCreate = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onRegisterActivityContracts(
    std::function<void(RuntimeContext &)> body) {
  definition_.onRegisterActivityContracts = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onDestroy(
    std::function<void(RuntimeContext &)> body) {
  definition_.onDestroy = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onForeground(
    std::function<void(RuntimeContext &)> body) {
  definition_.onForeground = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onBackground(
    std::function<void(RuntimeContext &)> body) {
  definition_.onBackground = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onUserLeaves(
    std::function<void(RuntimeContext &)> body) {
  definition_.onUserLeaves = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onActivityDestroy(
    std::function<void(RuntimeContext &)> body) {
  definition_.onActivityDestroy = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onNewIntent(
    std::function<void(RuntimeContext &, const folly::dynamic &)> body) {
  definition_.onNewIntent = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onActivityResult(
    std::function<void(RuntimeContext &, int, int, const folly::dynamic &)> body) {
  definition_.onActivityResult = std::move(body);
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onStartObserving(
    std::function<void(RuntimeContext &, const std::string &)> body) {
  definition_.startObservers.push_back({.everyEvent = true,
                                        .body = std::move(body)});
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onStartObserving(
    std::function<void(RuntimeContext &)> body) {
  definition_.startObservers.push_back({.body = [body = std::move(body)](
                                                    RuntimeContext &context,
                                                    const std::string &) { body(context); }});
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onStartObserving(
    std::string eventName,
    std::function<void(RuntimeContext &)> body) {
  definition_.startObservers.push_back({.eventName = std::move(eventName),
                                        .body = [body = std::move(body)](
                                                    RuntimeContext &context,
                                                    const std::string &) { body(context); }});
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onStopObserving(
    std::function<void(RuntimeContext &, const std::string &)> body) {
  definition_.stopObservers.push_back({.everyEvent = true,
                                       .body = std::move(body)});
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onStopObserving(
    std::function<void(RuntimeContext &)> body) {
  definition_.stopObservers.push_back({.body = [body = std::move(body)](
                                                   RuntimeContext &context,
                                                   const std::string &) { body(context); }});
  return *this;
}

ModuleDefinitionBuilder &ModuleDefinitionBuilder::onStopObserving(
    std::string eventName,
    std::function<void(RuntimeContext &)> body) {
  definition_.stopObservers.push_back({.eventName = std::move(eventName),
                                       .body = [body = std::move(body)](
                                                   RuntimeContext &context,
                                                   const std::string &) { body(context); }});
  return *this;
}

ModuleDefinition ModuleDefinitionBuilder::build() && {
  validateModuleDefinition(definition_);
  return std::move(definition_);
}

namespace {

template <typename T>
void requireUniqueNames(
    const std::vector<T> &definitions,
    const std::string &owner,
    const char *kind) {
  std::unordered_set<std::string> names;
  for (const auto &definition : definitions) {
    if (definition.name.empty()) {
      throw CodedError(
          "ERR_INVALID_DEFINITION", owner + " has an unnamed " + kind + ".");
    }
    if (!names.insert(definition.name).second) {
      throw CodedError(
          "ERR_DUPLICATE_DEFINITION",
          owner + " defines " + kind + " '" + definition.name + "' twice.");
    }
  }
}

void validateFunctions(
    const std::vector<FunctionDefinition> &functions,
    const std::string &owner) {
  requireUniqueNames(functions, owner, "function");
  for (const auto &function : functions) {
    if ((!function.async && !function.body) || (function.async && !function.body && !function.asyncBody)) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + "." + function.name + " has no native body.");
    }
    if (!function.async && function.queue != FunctionQueue::JavaScript) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + "." + function.name + " is synchronous and must run on the JavaScript queue.");
    }
    if (function.async && !function.asyncBody && function.queue != FunctionQueue::JavaScript) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + "." + function.name + " returns a JavaScript Promise/thenable directly and must run on the JavaScript queue.");
    }
    const auto requiredArity = function.requiredArity.value_or(function.arity);
    if (requiredArity > function.arity) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + "." + function.name + " has an invalid required argument count.");
    }
  }
}

void validateProperties(
    const std::vector<PropertyDefinition> &properties,
    const std::string &owner) {
  requireUniqueNames(properties, owner, "property");
  for (const auto &property : properties) {
    if (!property.getter) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + "." + property.name + " has no getter.");
    }
  }
}

}  // namespace

void validateModuleDefinition(const ModuleDefinition &definition) {
  if (definition.name.empty()) {
    throw CodedError("ERR_INVALID_DEFINITION", "Expo module name cannot be empty.");
  }
  validateFunctions(definition.functions, definition.name);
  validateProperties(definition.properties, definition.name);
  requireUniqueNames(definition.objects, definition.name, "object");
  requireUniqueNames(definition.classes, definition.name, "class");
  requireUniqueNames(definition.views, definition.name, "view");
  std::unordered_set<std::string> moduleMembers{"ViewPrototypes"};
  auto requireUniqueMember = [&](const std::string &name) {
    if (!moduleMembers.insert(name).second) {
      throw CodedError(
          "ERR_DUPLICATE_DEFINITION",
          definition.name + " defines member '" + name + "' more than once.");
    }
  };
  std::unordered_set<std::string> constantNames;
  for (const auto &[name, factory] : definition.constants) {
    if (name.empty() || !factory || !constantNames.insert(name).second) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          definition.name + " contains an invalid or duplicate constant '" + name + "'.");
    }
    requireUniqueMember(name);
  }
  for (const auto &function : definition.functions) {
    requireUniqueMember(function.name);
  }
  for (const auto &property : definition.properties) {
    requireUniqueMember(property.name);
  }
  for (const auto &object : definition.objects) {
    requireUniqueMember(object.name);
  }
  for (const auto &klass : definition.classes) {
    requireUniqueMember(klass.name);
  }
  for (const auto &event : definition.events) {
    if (event.empty()) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          definition.name + " contains an empty event name.");
    }
  }
  for (const auto &object : definition.objects) {
    const auto owner = definition.name + "." + object.name;
    validateFunctions(object.functions, owner);
    validateProperties(object.properties, owner);
    std::unordered_set<std::string> names;
    for (const auto &[name, factory] : object.constants) {
      if (name.empty() || !factory || !names.insert(name).second) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            owner + " contains an invalid or duplicate constant '" + name + "'.");
      }
    }
    for (const auto &function : object.functions) {
      if (!names.insert(function.name).second) {
        throw CodedError(
            "ERR_DUPLICATE_DEFINITION",
            owner + " defines member '" + function.name + "' more than once.");
      }
    }
    for (const auto &property : object.properties) {
      if (!names.insert(property.name).second) {
        throw CodedError(
            "ERR_DUPLICATE_DEFINITION",
            owner + " defines member '" + property.name + "' more than once.");
      }
    }
  }
  for (const auto &klass : definition.classes) {
    const auto owner = definition.name + "." + klass.name;
    const bool nativeBacked = klass.nativeType != std::type_index(typeid(void));
    if (nativeBacked && !klass.constructor) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + " has no native constructor.");
    }
    if (!nativeBacked && klass.constructor) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + " cannot use a SharedObject constructor without a C++ native type.");
    }
    if (!nativeBacked && (klass.baseClassName == "SharedRef" || !klass.startObservers.empty() || !klass.stopObservers.empty() || (!klass.baseClassName.empty() && klass.baseClassName != "SharedObject"))) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + " cannot use native SharedRef/custom inheritance or observers.");
    }
    const auto constructorRequiredArity = klass.constructorRequiredArity.value_or(klass.constructorArity);
    if (constructorRequiredArity > klass.constructorArity) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + " has an invalid constructor argument count.");
    }
    requireUniqueNames(klass.functions, owner, "function");
    requireUniqueNames(klass.properties, owner, "property");
    validateFunctions(klass.javaScriptFunctions, owner);
    validateProperties(klass.javaScriptProperties, owner);
    validateFunctions(klass.staticFunctions, owner);
    validateProperties(klass.staticProperties, owner);
    std::unordered_set<std::string> instanceMembers;
    for (const auto &[name, factory] : klass.constants) {
      if (name.empty() || !factory || !instanceMembers.insert(name).second) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            owner + " contains an invalid or duplicate constant '" + name + "'.");
      }
    }
    for (const auto &function : klass.functions) {
      if (!instanceMembers.insert(function.name).second) {
        throw CodedError(
            "ERR_DUPLICATE_DEFINITION",
            definition.name + "." + klass.name + " defines instance member '" + function.name + "' more than once.");
      }
    }
    for (const auto &property : klass.properties) {
      if (!instanceMembers.insert(property.name).second) {
        throw CodedError(
            "ERR_DUPLICATE_DEFINITION",
            definition.name + "." + klass.name + " defines instance member '" + property.name + "' more than once.");
      }
    }
    for (const auto &function : klass.javaScriptFunctions) {
      if (!instanceMembers.insert(function.name).second) {
        throw CodedError(
            "ERR_DUPLICATE_DEFINITION",
            owner + " defines instance member '" + function.name + "' more than once.");
      }
    }
    for (const auto &property : klass.javaScriptProperties) {
      if (!instanceMembers.insert(property.name).second) {
        throw CodedError(
            "ERR_DUPLICATE_DEFINITION",
            owner + " defines instance member '" + property.name + "' more than once.");
      }
    }
    std::unordered_set<std::string> staticMembers;
    for (const auto &function : klass.staticFunctions) {
      if (!staticMembers.insert(function.name).second) {
        throw CodedError(
            "ERR_DUPLICATE_DEFINITION",
            definition.name + "." + klass.name + " defines static member '" + function.name + "' more than once.");
      }
    }
    for (const auto &property : klass.staticProperties) {
      if (!staticMembers.insert(property.name).second) {
        throw CodedError(
            "ERR_DUPLICATE_DEFINITION",
            definition.name + "." + klass.name + " defines static member '" + property.name + "' more than once.");
      }
    }
    for (const auto &event : klass.events) {
      if (event.empty()) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            definition.name + "." + klass.name + " contains an empty event name.");
      }
    }
    for (const auto &function : klass.functions) {
      if ((!function.async && !function.body) || (function.async && !function.body && !function.asyncBody)) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            definition.name + "." + klass.name + "." + function.name + " has no native body.");
      }
      if (!function.async && function.queue != FunctionQueue::JavaScript) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            definition.name + "." + klass.name + "." + function.name + " is synchronous and must run on the JavaScript queue.");
      }
      if (function.async && !function.asyncBody && function.queue != FunctionQueue::JavaScript) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            definition.name + "." + klass.name + "." + function.name + " returns a JavaScript Promise/thenable directly and must run on the JavaScript queue.");
      }
      const auto requiredArity = function.requiredArity.value_or(function.arity);
      if (requiredArity > function.arity) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            definition.name + "." + klass.name + "." + function.name + " has an invalid required argument count.");
      }
    }
    if (!nativeBacked && (!klass.functions.empty() || !klass.properties.empty())) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + " uses native SharedObject members without a C++ native type.");
    }
    if (nativeBacked && (!klass.javaScriptFunctions.empty() || !klass.javaScriptProperties.empty() || klass.javaScriptConstructor)) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + " mixes JavaScript-only members with a native SharedObject class.");
    }
  }
  size_t defaultViewCount = 0;
  std::unordered_set<std::string> componentNames;
  std::unordered_set<std::string> prototypeNames;
  for (const auto &view : definition.views) {
    const auto owner = definition.name + "." + view.name;
    if (view.defaultView) {
      ++defaultViewCount;
    }
    if (view.componentName.empty() || !componentNames.insert(view.componentName).second) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + " has an empty or duplicate Fabric component name.");
    }
    if (view.prototypeName.empty() || !prototypeNames.insert(view.prototypeName).second) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          owner + " has an empty or duplicate view prototype name.");
    }
    validateFunctions(view.functions, owner);
    std::unordered_set<std::string> props;
    for (const auto &prop : view.props) {
      if (prop.name.empty() || !props.insert(prop.name).second) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            owner + " contains an empty or duplicate prop '" + prop.name + "'.");
      }
    }
    std::unordered_set<std::string> events;
    for (const auto &event : view.events) {
      if (event.empty() || !events.insert(event).second) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            owner + " contains an empty or duplicate event '" + event + "'.");
      }
    }
  }
  if (!definition.views.empty() && defaultViewCount != 1) {
    throw CodedError(
        "ERR_INVALID_DEFINITION",
        definition.name + " must define exactly one default view.");
  }
}

}  // namespace expo::harmony
