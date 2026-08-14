#include "ModulesHostObject.h"

#include <algorithm>
#include <unordered_set>

#include "api/ModuleDefinition.h"
#include "api/Promise.h"
#include "common/EventEmitter.h"
#include "common/JSI/JSIUtils.h"
#include "common/LazyObject.h"
#include "common/NativeModule.h"
#include "common/SharedObject.h"
#include "common/SharedRef.h"
#include "errors/CodedError.h"
#include "objects/BridgeCodec.h"
#include "runtime/ModuleRegistry.h"
#include "runtime/RuntimeContext.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

ExceptionOrigin originForPath(const std::string &path) {
  auto separator = path.find('.');
  return ExceptionOrigin{
      separator == std::string::npos ? path : path.substr(0, separator),
      path};
}

template <typename Observer>
bool shouldNotifyObserver(
    const Observer &observer,
    const std::string &eventName,
    size_t observedEventCount,
    bool starting) {
  if (observer.everyEvent) {
    return true;
  }
  if (observer.eventName) {
    return *observer.eventName == eventName;
  }
  return starting ? observedEventCount == 1 : observedEventCount == 0;
}

std::vector<const ClassDefinition *> orderedClasses(
    const ModuleDefinition &module) {
  std::vector<const ClassDefinition *> result;
  result.reserve(module.classes.size());
  std::unordered_set<std::string> completed;
  while (result.size() < module.classes.size()) {
    bool progressed = false;
    for (const auto &candidate : module.classes) {
      if (completed.contains(candidate.name)) {
        continue;
      }
      auto baseModule = module.name;
      auto baseClass = candidate.baseClassName;
      auto separator = baseClass.find('.');
      if (separator != std::string::npos) {
        baseModule = baseClass.substr(0, separator);
        baseClass = baseClass.substr(separator + 1);
      }
      const bool nativeBase = baseClass == "SharedObject" || baseClass == "SharedRef";
      const bool localBase = std::any_of(
          module.classes.begin(),
          module.classes.end(),
          [&](const ClassDefinition &definition) {
            return baseModule == module.name && definition.name == baseClass;
          });
      if (!nativeBase && localBase && !completed.contains(baseClass)) {
        continue;
      }
      result.push_back(&candidate);
      completed.insert(candidate.name);
      progressed = true;
    }
    if (!progressed) {
      throw CodedError(
          "ERR_CLASS_INHERITANCE_CYCLE",
          "Module '" + module.name + "' contains a native class inheritance cycle.");
    }
  }
  return result;
}

template <typename Body>
jsi::Value translateErrors(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context,
    const std::string &path,
    bool async,
    Body body) {
  try {
    return body();
  } catch (const CodedError &error) {
    auto contextual = error.withOrigin(originForPath(path), path);
    if (async) {
      return Promise::create(
          runtime,
          context,
          [contextual = std::move(contextual)](
              const std::shared_ptr<Promise> &promise) mutable {
            promise->reject(std::move(contextual));
          });
    }
    throw makeJSError(runtime, contextual);
  } catch (const jsi::JSError &) {
    throw;
  } catch (const std::exception &error) {
    if (async) {
      return Promise::rejected(
          runtime, context, "ERR_UNEXPECTED", path + " failed: " + error.what());
    }
    throw makeJSError(
        runtime, "ERR_UNEXPECTED", path + " failed: " + error.what());
  }
}

jsi::Value invokeFunction(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context,
    const std::string &path,
    const FunctionDefinition &definition,
    const jsi::Value &thisValue,
    const jsi::Value *arguments,
    size_t argumentCount) {
  if (definition.async && definition.asyncBody) {
    auto retainedThis = std::make_shared<jsi::Value>(runtime, thisValue);
    auto retainedArguments = std::make_shared<std::vector<jsi::Value>>();
    retainedArguments->reserve(argumentCount);
    for (size_t index = 0; index < argumentCount; ++index) {
      retainedArguments->emplace_back(runtime, arguments[index]);
    }
    return Promise::create(
        runtime,
        context,
        [context,
         path,
         definition = &definition,
         retainedThis = std::move(retainedThis),
         retainedArguments = std::move(retainedArguments)](
            const std::shared_ptr<Promise> &promise) {
          auto &currentRuntime = context->runtime();
          Invocation invocation(
              context,
              path,
              currentRuntime,
              *retainedThis,
              retainedArguments->data(),
              retainedArguments->size());
          try {
            invocation.requireArgumentCount(
                definition->requiredArity.value_or(definition->arity),
                definition->arity);
            definition->asyncBody(invocation, promise);
          } catch (const CodedError &error) {
            throw error.withOrigin(originForPath(path), path);
          }
        });
  }
  return translateErrors(runtime, context, path, definition.async, [&]() {
    Invocation invocation(
        context, path, runtime, thisValue, arguments, argumentCount);
    invocation.requireArgumentCount(
        definition.requiredArity.value_or(definition.arity),
        definition.arity);
    auto result = definition.body(invocation);
    if (!definition.async) {
      return result;
    }
    if (result.isObject()) {
      auto then = result.getObject(runtime).getProperty(runtime, "then");
      if (then.isObject() && then.getObject(runtime).isFunction(runtime)) {
        return result;
      }
    }
    auto retained = std::make_shared<jsi::Value>(runtime, result);
    return Promise::create(
        runtime,
        context,
        [retained](const std::shared_ptr<Promise> &promise) {
          promise->resolve([retained](jsi::Runtime &rt) {
            return jsi::Value(rt, *retained);
          });
        });
  });
}

void defineFunction(
    jsi::Runtime &runtime,
    jsi::Object &target,
    const std::shared_ptr<RuntimeContext> &context,
    std::string path,
    const FunctionDefinition &definition) {
  auto propertyName = jsi::PropNameID::forUtf8(runtime, definition.name);
  auto function = jsi::Function::createFromHostFunction(
      runtime,
      propertyName,
      definition.arity,
      [context, path = std::move(path), definition = &definition](
          jsi::Runtime &rt,
          const jsi::Value &thisValue,
          const jsi::Value *arguments,
          size_t argumentCount) {
        return invokeFunction(
            rt,
            context,
            path,
            *definition,
            thisValue,
            arguments,
            argumentCount);
      });
  if (definition.enumerable) {
    target.setProperty(runtime, propertyName, std::move(function));
  } else {
    expo::common::defineProperty(runtime, &target, definition.name.c_str(), {.configurable = false, .enumerable = false, .writable = false, .value = std::move(function)});
  }
}

void defineProperty(
    jsi::Runtime &runtime,
    jsi::Object &target,
    const std::shared_ptr<RuntimeContext> &context,
    std::string path,
    const PropertyDefinition &definition) {
  std::function<jsi::Value(jsi::Runtime &, jsi::Object)> getter;
  if (definition.getter) {
    getter = [context, path, definition = &definition](
                 jsi::Runtime &rt, jsi::Object receiver) {
      return translateErrors(rt, context, path, false, [&]() {
        Invocation invocation(
            context,
            path,
            rt,
            jsi::Value(rt, receiver),
            nullptr,
            0);
        return definition->getter(invocation);
      });
    };
  }
  std::function<void(jsi::Runtime &, jsi::Object, jsi::Value)> setter;
  if (definition.setter) {
    setter = [context, path, definition = &definition](
                 jsi::Runtime &rt, jsi::Object receiver, jsi::Value value) {
      translateErrors(rt, context, path, false, [&]() {
        Invocation invocation(
            context,
            path,
            rt,
            jsi::Value(rt, receiver),
            nullptr,
            0);
        definition->setter(invocation, value);
        return jsi::Value::undefined();
      });
    };
  }
  expo::common::defineProperty(
      runtime,
      &target,
      definition.name.c_str(),
      {
          .configurable = false,
          .enumerable = definition.enumerable,
          .get = std::move(getter),
          .set = std::move(setter),
      });
}

void defineConstant(
    jsi::Runtime &runtime,
    jsi::Object &target,
    const std::shared_ptr<RuntimeContext> &context,
    std::string path,
    const std::string &name,
    const ValueFactory &factory) {
  auto cachedValue = std::make_shared<std::unique_ptr<jsi::Value>>();
  expo::common::defineProperty(
      runtime,
      &target,
      name.c_str(),
      {.configurable = false, .enumerable = true, .get = [context, path = std::move(path), factory = &factory, cachedValue](jsi::Runtime &rt, jsi::Object) {
         if (*cachedValue) {
           return jsi::Value(rt, **cachedValue);
         }
         Invocation invocation(
             context,
             path,
             rt,
             jsi::Value::undefined(),
             nullptr,
             0);
         auto value = translateErrors(
             rt,
             context,
             path,
             false,
             [&invocation, factory]() { return (*factory)(invocation); });
         *cachedValue = std::make_unique<jsi::Value>(rt, value);
         return value;
       }});
}

void defineSharedFunction(
    jsi::Runtime &runtime,
    jsi::Object &target,
    const std::shared_ptr<RuntimeContext> &context,
    std::string path,
    std::string moduleName,
    std::string className,
    const SharedObjectFunctionDefinition &definition) {
  auto propertyName = jsi::PropNameID::forUtf8(runtime, definition.name);
  target.setProperty(
      runtime,
      propertyName,
      jsi::Function::createFromHostFunction(
          runtime,
          propertyName,
          definition.arity,
          [context,
           path = std::move(path),
           moduleName = std::move(moduleName),
           className = std::move(className),
           definition = &definition](
              jsi::Runtime &rt,
              const jsi::Value &thisValue,
              const jsi::Value *arguments,
              size_t argumentCount) {
            if (definition->async && definition->asyncBody) {
              auto objectId = requireSharedObjectId(rt, thisValue, className);
              auto nativeObject = context->getNativeSharedObject(
                  objectId, moduleName, className);
              auto retainedThis = std::make_shared<jsi::Value>(rt, thisValue);
              auto retainedArguments = std::make_shared<std::vector<jsi::Value>>();
              retainedArguments->reserve(argumentCount);
              for (size_t index = 0; index < argumentCount; ++index) {
                retainedArguments->emplace_back(rt, arguments[index]);
              }
              return Promise::create(
                  rt,
                  context,
                  [context,
                   path,
                   definition,
                   nativeObject = std::move(nativeObject),
                   retainedThis = std::move(retainedThis),
                   retainedArguments = std::move(retainedArguments)](
                      const std::shared_ptr<Promise> &promise) {
                    auto &currentRuntime = context->runtime();
                    Invocation invocation(
                        context,
                        path,
                        currentRuntime,
                        *retainedThis,
                        retainedArguments->data(),
                        retainedArguments->size());
                    try {
                      invocation.requireArgumentCount(
                          definition->requiredArity.value_or(definition->arity),
                          definition->arity);
                      definition->asyncBody(invocation, nativeObject, promise);
                    } catch (const CodedError &error) {
                      throw error.withOrigin(originForPath(path), path);
                    }
                  });
            }
            return translateErrors(rt, context, path, definition->async, [&]() {
              auto objectId = requireSharedObjectId(rt, thisValue, className);
              auto nativeObject = context->getNativeSharedObject(
                  objectId, moduleName, className);
              Invocation invocation(
                  context, path, rt, thisValue, arguments, argumentCount);
              invocation.requireArgumentCount(
                  definition->requiredArity.value_or(definition->arity),
                  definition->arity);
              auto result = definition->body(invocation, nativeObject);
              if (!definition->async) {
                return result;
              }
              if (result.isObject()) {
                auto then = result.getObject(rt).getProperty(rt, "then");
                if (then.isObject() && then.getObject(rt).isFunction(rt)) {
                  return result;
                }
              }
              auto retained = std::make_shared<jsi::Value>(rt, result);
              return Promise::create(
                  rt,
                  context,
                  [retained](const std::shared_ptr<Promise> &promise) {
                    promise->resolve([retained](jsi::Runtime &currentRuntime) {
                      return jsi::Value(currentRuntime, *retained);
                    });
                  });
            });
          }));
}

void defineSharedProperty(
    jsi::Runtime &runtime,
    jsi::Object &target,
    const std::shared_ptr<RuntimeContext> &context,
    std::string path,
    std::string moduleName,
    std::string className,
    const SharedObjectPropertyDefinition &definition) {
  std::function<jsi::Value(jsi::Runtime &, jsi::Object)> getter;
  if (definition.getter) {
    getter = [context, path, moduleName, className, definition = &definition](
                 jsi::Runtime &rt, jsi::Object receiver) {
      return translateErrors(rt, context, path, false, [&]() {
        auto receiverValue = jsi::Value(rt, receiver);
        auto nativeObject = context->getNativeSharedObject(
            requireSharedObjectId(rt, receiverValue, className),
            moduleName,
            className);
        Invocation invocation(
            context, path, rt, receiverValue, nullptr, 0);
        return definition->getter(invocation, nativeObject);
      });
    };
  }
  std::function<void(jsi::Runtime &, jsi::Object, jsi::Value)> setter;
  if (definition.setter) {
    setter = [context, path, moduleName, className, definition = &definition](
                 jsi::Runtime &rt, jsi::Object receiver, jsi::Value value) {
      translateErrors(rt, context, path, false, [&]() {
        auto receiverValue = jsi::Value(rt, receiver);
        auto nativeObject = context->getNativeSharedObject(
            requireSharedObjectId(rt, receiverValue, className),
            moduleName,
            className);
        Invocation invocation(
            context, path, rt, receiverValue, nullptr, 0);
        definition->setter(invocation, nativeObject, value);
        return jsi::Value::undefined();
      });
    };
  }
  expo::common::defineProperty(
      runtime,
      &target,
      definition.name.c_str(),
      {
          .configurable = false,
          .enumerable = definition.enumerable,
          .get = std::move(getter),
          .set = std::move(setter),
      });
}

}  // namespace

ModulesHostObject::ModulesHostObject(std::shared_ptr<RuntimeContext> context)
    : context_(std::move(context)) {}

jsi::Value ModulesHostObject::get(
    jsi::Runtime &runtime,
    const jsi::PropNameID &property) {
  if (!context_->isAlive()) {
    return jsi::Value::undefined();
  }
  auto name = property.utf8(runtime);
  auto cached = context_->getModule(name);
  if (!cached.isUndefined()) {
    return cached;
  }
  const auto *definition = context_->moduleRegistry().find(name);
  if (!definition) {
    return jsi::Value::undefined();
  }
  auto lazy = std::make_shared<expo::LazyObject>(
      [this, definition](jsi::Runtime &currentRuntime) {
        return std::make_shared<jsi::Object>(
            createModule(currentRuntime, *definition));
      });
  auto object = jsi::Object::createFromHostObject(runtime, std::move(lazy));
  context_->retainModule(name, object);
  return jsi::Value(runtime, object);
}

void ModulesHostObject::set(
    jsi::Runtime &runtime,
    const jsi::PropNameID &name,
    const jsi::Value &) {
  throw makeJSError(
      runtime,
      "ERR_MODULE_OVERRIDE",
      "Cannot override the native Expo module '" + name.utf8(runtime) + "'.");
}

std::vector<jsi::PropNameID> ModulesHostObject::getPropertyNames(
    jsi::Runtime &runtime) {
  std::vector<jsi::PropNameID> result;
  const auto &names = context_->moduleRegistry().names();
  result.reserve(names.size());
  for (const auto &name : names) {
    result.push_back(jsi::PropNameID::forUtf8(runtime, name));
  }
  return result;
}

jsi::Object ModulesHostObject::createModule(
    jsi::Runtime &runtime,
    const ModuleDefinition &definition) {
  auto module = expo::NativeModule::createInstance(runtime);
  expo::common::defineProperty(runtime, &module, "__expo_module_name__", {.value = jsi::String::createFromUtf8(runtime, definition.name)});

  for (const auto &constant : definition.constants) {
    const auto &name = constant.first;
    defineConstant(
        runtime,
        module,
        context_,
        definition.name + "." + name,
        name,
        constant.second);
  }
  for (const auto &function : definition.functions) {
    defineFunction(
        runtime,
        module,
        context_,
        definition.name + "." + function.name,
        function);
  }
  for (const auto &property : definition.properties) {
    defineProperty(
        runtime,
        module,
        context_,
        definition.name + "." + property.name,
        property);
  }

  if (!definition.startObservers.empty() || !definition.stopObservers.empty()) {
    auto observedEventCount = std::make_shared<size_t>(0);
    auto startName = jsi::PropNameID::forAscii(runtime, "startObserving");
    module.setProperty(
        runtime,
        startName,
        jsi::Function::createFromHostFunction(
            runtime,
            startName,
            1,
            [context = context_,
             definition = &definition,
             observedEventCount](
                jsi::Runtime &rt,
                const jsi::Value &,
                const jsi::Value *arguments,
                size_t count) {
              if (count == 1 && arguments[0].isString()) {
                const auto eventName = arguments[0].getString(rt).utf8(rt);
                ++*observedEventCount;
                for (const auto &observer : definition->startObservers) {
                  if (observer.body && shouldNotifyObserver(observer, eventName, *observedEventCount, true)) {
                    observer.body(*context, eventName);
                  }
                }
              }
              return jsi::Value::undefined();
            }));
    auto stopName = jsi::PropNameID::forAscii(runtime, "stopObserving");
    module.setProperty(
        runtime,
        stopName,
        jsi::Function::createFromHostFunction(
            runtime,
            stopName,
            1,
            [context = context_,
             definition = &definition,
             observedEventCount](
                jsi::Runtime &rt,
                const jsi::Value &,
                const jsi::Value *arguments,
                size_t count) {
              if (count == 1 && arguments[0].isString()) {
                const auto eventName = arguments[0].getString(rt).utf8(rt);
                if (*observedEventCount > 0) {
                  --*observedEventCount;
                }
                for (const auto &observer : definition->stopObservers) {
                  if (observer.body && shouldNotifyObserver(observer, eventName, *observedEventCount, false)) {
                    observer.body(*context, eventName);
                  }
                }
              }
              return jsi::Value::undefined();
            }));
  }

  for (const auto &objectDefinition : definition.objects) {
    jsi::Object object(runtime);
    auto objectPath = definition.name + "." + objectDefinition.name;
    for (const auto &[name, factory] : objectDefinition.constants) {
      defineConstant(
          runtime,
          object,
          context_,
          objectPath + "." + name,
          name,
          factory);
    }
    for (const auto &function : objectDefinition.functions) {
      defineFunction(
          runtime, object, context_, objectPath + "." + function.name, function);
    }
    for (const auto &property : objectDefinition.properties) {
      defineProperty(
          runtime, object, context_, objectPath + "." + property.name, property);
    }
    module.setProperty(runtime, objectDefinition.name.c_str(), std::move(object));
  }

  for (const auto *classDefinitionPointer : orderedClasses(definition)) {
    const auto &classDefinition = *classDefinitionPointer;
    auto classPath = definition.name + "." + classDefinition.name;
    auto constructor = [context = context_,
                        moduleName = definition.name,
                        classDefinition = &classDefinition,
                        classPath](
                           jsi::Runtime &rt,
                           const jsi::Value &thisValue,
                           const jsi::Value *arguments,
                           size_t argumentCount) {
      return translateErrors(rt, context, classPath + ".constructor", false, [&]() {
        Invocation invocation(
            context,
            classPath + ".constructor",
            rt,
            thisValue,
            arguments,
            argumentCount);
        invocation.requireArgumentCount(
            classDefinition->constructorRequiredArity.value_or(
                classDefinition->constructorArity),
            classDefinition->constructorArity);
        if (classDefinition->nativeType != std::type_index(typeid(void))) {
          auto nativeObject = classDefinition->constructor(invocation);
          if (!thisValue.isObject()) {
            throw CodedError(
                "ERR_INVALID_ARGUMENT",
                classPath + ".constructor received a non-object receiver.");
          }
          return context->bindNativeSharedObject(
              moduleName,
              classDefinition->name,
              std::move(nativeObject),
              thisValue.getObject(rt));
        }
        if (!thisValue.isObject()) {
          throw CodedError(
              "ERR_INVALID_ARGUMENT",
              classPath + ".constructor received a non-object receiver.");
        }
        auto receiver = thisValue.getObject(rt);
        if (classDefinition->javaScriptConstructor) {
          (void)classDefinition->javaScriptConstructor(invocation);
        }
        return jsi::Value(rt, receiver);
      });
    };
    jsi::Function klass = [&]() {
      if (classDefinition.baseClassName.empty()) {
        return expo::common::createClass(
            runtime, classDefinition.name.c_str(), constructor);
      }
      if (classDefinition.baseClassName == "SharedRef") {
        return expo::SharedRef::createClass(
            runtime, classDefinition.name.c_str(), constructor);
      }
      if (classDefinition.baseClassName == "SharedObject") {
        return expo::SharedObject::createClass(
            runtime, classDefinition.name.c_str(), constructor);
      }
      auto baseModuleName = definition.name;
      auto baseClassName = classDefinition.baseClassName;
      auto separator = baseClassName.find('.');
      if (separator != std::string::npos) {
        baseModuleName = baseClassName.substr(0, separator);
        baseClassName = baseClassName.substr(separator + 1);
      }
      if (baseModuleName != definition.name) {
        auto modules = runtime.global()
                           .getPropertyAsObject(runtime, "expo")
                           .getPropertyAsObject(runtime, "modules");
        auto baseModuleValue = modules.getProperty(
            runtime, baseModuleName.c_str());
        if (baseModuleValue.isObject()) {
          baseModuleValue.getObject(runtime).getProperty(
              runtime, baseClassName.c_str());
        }
      }
      auto baseValue = context_->getClass(baseModuleName, baseClassName);
      if (!baseValue.isObject() || !baseValue.getObject(runtime).isFunction(runtime)) {
        throw makeJSError(
            runtime,
            "ERR_CLASS_NOT_FOUND",
            "Base class '" + baseModuleName + "." + baseClassName + "' must be registered before '" + classPath + "'.");
      }
      auto baseClass = baseValue.getObject(runtime).getFunction(runtime);
      return expo::common::createInheritingClass(
          runtime,
          classDefinition.name.c_str(),
          baseClass,
          constructor);
    }();
    context_->retainClass(definition.name, classDefinition.name, klass);

    for (const auto &function : classDefinition.staticFunctions) {
      defineFunction(
          runtime, klass, context_, classPath + "." + function.name, function);
    }
    for (const auto &property : classDefinition.staticProperties) {
      defineProperty(
          runtime, klass, context_, classPath + "." + property.name, property);
    }
    auto prototype = klass.getPropertyAsObject(runtime, "prototype");
    for (const auto &[name, factory] : classDefinition.constants) {
      defineConstant(
          runtime,
          prototype,
          context_,
          classPath + "." + name,
          name,
          factory);
    }
    for (const auto &function : classDefinition.javaScriptFunctions) {
      defineFunction(
          runtime,
          prototype,
          context_,
          classPath + "." + function.name,
          function);
    }
    for (const auto &property : classDefinition.javaScriptProperties) {
      defineProperty(
          runtime,
          prototype,
          context_,
          classPath + "." + property.name,
          property);
    }
    for (const auto &function : classDefinition.functions) {
      defineSharedFunction(
          runtime,
          prototype,
          context_,
          classPath + "." + function.name,
          definition.name,
          classDefinition.name,
          function);
    }
    for (const auto &property : classDefinition.properties) {
      defineSharedProperty(
          runtime,
          prototype,
          context_,
          classPath + "." + property.name,
          definition.name,
          classDefinition.name,
          property);
    }
    if (!classDefinition.startObservers.empty() || !classDefinition.stopObservers.empty()) {
      auto startName = jsi::PropNameID::forAscii(
          runtime, "__expo_onStartListeningToEvent");
      prototype.setProperty(
          runtime,
          startName,
          jsi::Function::createFromHostFunction(
              runtime,
              startName,
              1,
              [context = context_,
               moduleName = definition.name,
               classDefinition = &classDefinition](
                  jsi::Runtime &rt,
                  const jsi::Value &thisValue,
                  const jsi::Value *arguments,
                  size_t count) {
                if (count == 1 && arguments[0].isString()) {
                  const auto objectId = requireSharedObjectId(
                      rt, thisValue, classDefinition->name);
                  auto nativeObject = context->getNativeSharedObject(
                      objectId,
                      moduleName,
                      classDefinition->name);
                  const auto eventName = arguments[0].getString(rt).utf8(rt);
                  const auto observedEventCount = context->beginObservingSharedObject(objectId);
                  for (const auto &observer : classDefinition->startObservers) {
                    if (observer.body && shouldNotifyObserver(observer, eventName, observedEventCount, true)) {
                      observer.body(*context, nativeObject, eventName);
                    }
                  }
                }
                return jsi::Value::undefined();
              }));
      auto stopName = jsi::PropNameID::forAscii(
          runtime, "__expo_onStopListeningToEvent");
      prototype.setProperty(
          runtime,
          stopName,
          jsi::Function::createFromHostFunction(
              runtime,
              stopName,
              1,
              [context = context_,
               moduleName = definition.name,
               classDefinition = &classDefinition](
                  jsi::Runtime &rt,
                  const jsi::Value &thisValue,
                  const jsi::Value *arguments,
                  size_t count) {
                if (count == 1 && arguments[0].isString()) {
                  const auto objectId = requireSharedObjectId(
                      rt, thisValue, classDefinition->name);
                  auto nativeObject = context->getNativeSharedObject(
                      objectId,
                      moduleName,
                      classDefinition->name);
                  const auto eventName = arguments[0].getString(rt).utf8(rt);
                  const auto observedEventCount = context->endObservingSharedObject(objectId);
                  for (const auto &observer : classDefinition->stopObservers) {
                    if (observer.body && shouldNotifyObserver(observer, eventName, observedEventCount, false)) {
                      observer.body(*context, nativeObject, eventName);
                    }
                  }
                }
                return jsi::Value::undefined();
              }));
    }
    if (classDefinition.baseClassName == "SharedRef") {
      expo::common::defineProperty(runtime, &prototype, "nativeRefType", {.configurable = false, .enumerable = true, .get = [context = context_, moduleName = definition.name, className = classDefinition.name](jsi::Runtime &rt, jsi::Object receiver) {
                                                                            auto receiverValue = jsi::Value(rt, receiver);
                                                                            auto nativeObject = context->getNativeSharedObject(
                                                                                requireSharedObjectId(rt, receiverValue, className),
                                                                                moduleName,
                                                                                className);
                                                                            return jsi::String::createFromUtf8(rt, nativeObject->nativeRefType());
                                                                          }});
    }
    module.setProperty(runtime, classDefinition.name.c_str(), std::move(klass));
  }

  jsi::Object viewPrototypes(runtime);
  for (const auto &view : definition.views) {
    jsi::Object prototype(runtime);
    for (const auto &function : view.functions) {
      defineFunction(
          runtime,
          prototype,
          context_,
          definition.name + "." + view.name + "." + function.name,
          function);
    }
    viewPrototypes.setProperty(
        runtime, view.prototypeName.c_str(), std::move(prototype));
  }
  module.setProperty(runtime, "ViewPrototypes", std::move(viewPrototypes));
  return module;
}

}  // namespace expo::harmony
