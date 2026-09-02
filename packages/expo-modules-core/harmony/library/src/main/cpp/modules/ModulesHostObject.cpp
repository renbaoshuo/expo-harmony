#include "ModulesHostObject.h"

#include <algorithm>
#include <unordered_set>

#include "api/Promise.h"
#include "common/EventEmitter.h"
#include "common/JSI/JSIUtils.h"
#include "common/LazyObject.h"
#include "common/NativeModule.h"
#include "common/SharedObject.h"
#include "common/SharedRef.h"
#include "errors/CodedError.h"
#include "modules/internal/ModuleDefinition.h"
#include "runtime/ModuleRegistry.h"
#include "runtime/RuntimeContext.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

long requireSharedObjectId(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    const std::string &className) {
  if (!value.isObject()) {
    throw CodedError(
        "ERR_SHARED_OBJECT_TYPE",
        className + " method called with a non-object receiver.");
  }

  auto object = value.getObject(runtime);
  if (!object.hasNativeState<expo::SharedObject::NativeState>(runtime)) {
    throw CodedError(
        "ERR_SHARED_OBJECT_TYPE",
        className + " method called with an incompatible receiver.");
  }

  const auto objectId = object.getNativeState<expo::SharedObject::NativeState>(runtime)->objectId;
  if (objectId <= 0) {
    throw CodedError(
        "ERR_INVALID_SHARED_OBJECT_ID",
        className + " method called with an unbound shared object.");
  }

  return objectId;
}

ExceptionOrigin originForPath(const std::string &path) {
  const auto firstSeparator = path.find('.');
  const auto lastSeparator = path.rfind('.');
  if (firstSeparator == std::string::npos) {
    return ExceptionOrigin{path, "", path};
  }

  const auto className = firstSeparator == lastSeparator
                           ? std::string{}
                           : path.substr(
                                 firstSeparator + 1,
                                 lastSeparator - firstSeparator - 1);
  return ExceptionOrigin{
      path.substr(0, firstSeparator),
      className,
      path.substr(lastSeparator + 1)};
}

void requirePublicRuntime(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context,
    const std::string &path) {
  if (context && context->isAlive() && context->isAcceptingTasks()) {
    return;
  }

  throw CodedJSError(
      runtime,
      CodedError(
          "ERR_RUNTIME_DESTROYED",
          "Cannot invoke Expo module API '" + path + "' while its runtime is being destroyed.",
          originForPath(path),
          nullptr,
          {path}));
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
    // Gate authored entry points before invoking cached or native values.
    requirePublicRuntime(runtime, context, path);
    return body();
  } catch (const CodedError &error) {
    auto stack = error.nativeStack();
    stack.insert(stack.begin(), path);
    CodedError contextual(
        error.code(),
        error.what(),
        originForPath(path),
        error.cause(),
        std::move(stack));

    if (async) {
      return Promise::create(
          runtime,
          context,
          [contextual = std::move(contextual)](
              const std::shared_ptr<Promise> &promise) mutable {
            promise->reject(std::move(contextual));
          });
    }

    throw CodedJSError(runtime, contextual);
  } catch (const jsi::JSError &error) {
    throw jsi::JSError(error);
  } catch (const std::exception &error) {
    if (async) {
      return Promise::rejected(
          runtime, context, "ERR_UNEXPECTED", path + " failed: " + error.what());
    }

    throw CodedJSError(
        runtime, "ERR_UNEXPECTED", path + " failed: " + error.what());
  } catch (...) {
    if (async) {
      return Promise::rejected(
          runtime,
          context,
          "ERR_UNEXPECTED",
          path + " failed because native code threw a non-standard exception.");
    }

    throw CodedJSError(
        runtime,
        "ERR_UNEXPECTED",
        path + " failed because native code threw a non-standard exception.");
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
  // Reject before Promise::create after invalidation closes admission.
  requirePublicRuntime(runtime, context, path);
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
            auto stack = error.nativeStack();
            stack.insert(stack.begin(), path);
            throw CodedError(
                error.code(),
                error.what(),
                originForPath(path),
                error.cause(),
                std::move(stack));
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
         return translateErrors(rt, context, path, false, [&]() {
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
           auto value = (*factory)(invocation);
           *cachedValue = std::make_unique<jsi::Value>(rt, value);
           return value;
         });
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
            // Reject released SharedObjects before creating a Promise.
            requirePublicRuntime(rt, context, path);
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
                      auto stack = error.nativeStack();
                      stack.insert(stack.begin(), path);
                      throw CodedError(
                          error.code(),
                          error.what(),
                          originForPath(path),
                          error.cause(),
                          std::move(stack));
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
  } else {
    setter = [context, path, moduleName, className](
                 jsi::Runtime &rt, jsi::Object receiver, jsi::Value) {
      translateErrors(rt, context, path, false, [&]() -> jsi::Value {
        auto receiverValue = jsi::Value(rt, receiver);
        (void)context->getNativeSharedObject(
            requireSharedObjectId(rt, receiverValue, className),
            moduleName,
            className);
        throw CodedError(
            "ERR_PROPERTY_READ_ONLY",
            "Cannot assign to read-only Expo SharedObject property '" + path + "'.");
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
  try {
    if (!context_->isAlive() || !context_->isAcceptingTasks()) {
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

    auto lazyModule = std::make_shared<expo::LazyObject>(
        [self = shared_from_this(), definition](jsi::Runtime &rt) {
          return std::make_shared<jsi::Object>(
              self->createModule(rt, *definition));
        });
    auto object = jsi::Object::createFromHostObject(runtime, lazyModule);
    context_->retainModule(name, object);

    return jsi::Value(runtime, object);
  } catch (const jsi::JSError &error) {
    throw jsi::JSError(error);
  } catch (const CodedError &error) {
    throw CodedJSError(runtime, error);
  } catch (const std::exception &error) {
    throw CodedJSError(
        runtime,
        "ERR_MODULE_GET",
        "Could not access an Expo module: " + std::string(error.what()));
  } catch (...) {
    throw CodedJSError(
        runtime,
        "ERR_MODULE_GET",
        "Could not access an Expo module because native code threw an unknown exception.");
  }
}

void ModulesHostObject::set(
    jsi::Runtime &runtime,
    const jsi::PropNameID &name,
    const jsi::Value &) {
  throw CodedJSError(
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
    auto observedEvents = std::make_shared<std::unordered_set<std::string>>();
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
             observedEvents](
                jsi::Runtime &rt,
                const jsi::Value &,
                const jsi::Value *arguments,
                size_t count) {
              requirePublicRuntime(
                  rt, context, definition->name + ".startObserving");
              if (count == 1 && arguments[0].isString()) {
                const auto eventName = arguments[0].getString(rt).utf8(rt);
                if (!observedEvents->insert(eventName).second) {
                  return jsi::Value::undefined();
                }

                const auto finishObservers = [&](size_t first) noexcept {
                  for (size_t index = first;
                       index < definition->startObservers.size() && observedEvents->contains(eventName);
                       ++index) {
                    const auto &observer = definition->startObservers[index];
                    if (!observer) {
                      continue;
                    }
                    try {
                      observer(*context, eventName);
                    } catch (...) {
                    }
                  }
                };

                for (size_t index = 0;
                     index < definition->startObservers.size() && observedEvents->contains(eventName);
                     ++index) {
                  const auto &observer = definition->startObservers[index];
                  if (!observer) {
                    continue;
                  }
                  try {
                    observer(*context, eventName);
                  } catch (const CodedError &error) {
                    finishObservers(index + 1);
                    throw CodedJSError(rt, error);
                  } catch (const jsi::JSError &error) {
                    finishObservers(index + 1);
                    throw jsi::JSError(error);
                  } catch (const std::exception &error) {
                    finishObservers(index + 1);
                    throw std::runtime_error(error.what());
                  } catch (...) {
                    finishObservers(index + 1);
                    throw std::runtime_error(
                        definition->name + ".startObserving failed.");
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
             observedEvents](
                jsi::Runtime &rt,
                const jsi::Value &,
                const jsi::Value *arguments,
                size_t count) {
              if (count == 1 && arguments[0].isString()) {
                const auto eventName = arguments[0].getString(rt).utf8(rt);
                if (observedEvents->erase(eventName) == 0) {
                  return jsi::Value::undefined();
                }

                const auto finishObservers = [&](size_t first) noexcept {
                  for (size_t index = first;
                       index < definition->stopObservers.size();
                       ++index) {
                    const auto &observer = definition->stopObservers[index];
                    if (!observer) {
                      continue;
                    }
                    try {
                      observer(*context, eventName);
                    } catch (...) {
                    }
                  }
                };

                for (size_t index = 0;
                     index < definition->stopObservers.size();
                     ++index) {
                  const auto &observer = definition->stopObservers[index];
                  if (!observer) {
                    continue;
                  }
                  try {
                    observer(*context, eventName);
                  } catch (const CodedError &error) {
                    finishObservers(index + 1);
                    throw CodedJSError(rt, error);
                  } catch (const jsi::JSError &error) {
                    finishObservers(index + 1);
                    throw jsi::JSError(error);
                  } catch (const std::exception &error) {
                    finishObservers(index + 1);
                    throw std::runtime_error(error.what());
                  } catch (...) {
                    finishObservers(index + 1);
                    throw std::runtime_error(
                        definition->name + ".stopObserving failed.");
                  }
                }
              }
              return jsi::Value::undefined();
            }));
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
        auto nativeObject = classDefinition->constructor(invocation);
        if (!thisValue.isObject()) {
          throw CodedError(
              "ERR_INVALID_ARGUMENT",
              classPath + ".constructor received a non-object receiver.");
        }
        const auto identity = context->captureSharedObjectInvocation(nativeObject);
        const auto rollback = [&]() noexcept {
          try {
            context->releaseSharedObject(identity.objectId);
          } catch (...) {
          }
        };
        try {
          return context->bindNativeSharedObject(
              moduleName,
              classDefinition->name,
              std::move(nativeObject),
              thisValue.getObject(rt));
        } catch (const CodedError &error) {
          rollback();
          throw CodedError(error);
        } catch (const jsi::JSError &error) {
          rollback();
          throw jsi::JSError(error);
        } catch (const std::exception &error) {
          rollback();
          throw std::runtime_error(error.what());
        } catch (...) {
          rollback();
          throw std::runtime_error(
              classPath + ".constructor failed to bind its shared object.");
        }
      });
    };
    jsi::Function klass = [&]() {
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
        throw CodedError(
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
    if (!classDefinition.events.empty()) {
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
                requirePublicRuntime(
                    rt,
                    context,
                    moduleName + "." + classDefinition->name + ".startObserving");
                if (count == 1 && arguments[0].isString()) {
                  const auto objectId = requireSharedObjectId(
                      rt, thisValue, classDefinition->name);
                  auto nativeObject = context->getNativeSharedObject(
                      objectId,
                      moduleName,
                      classDefinition->name);
                  const auto eventName = arguments[0].getString(rt).utf8(rt);
                  const auto observedEventCount = context->beginObservingSharedObject(
                      objectId,
                      eventName,
                      [nativeObject](
                          const std::string &stoppedEventName,
                          size_t remainingEventCount) {
                        (void)remainingEventCount;
                        nativeObject->onStopListeningToEvent(stoppedEventName);
                      });
                  if (observedEventCount == 0) {
                    return jsi::Value::undefined();
                  }

                  try {
                    nativeObject->onStartListeningToEvent(eventName);
                  } catch (const CodedError &error) {
                    throw CodedJSError(rt, error);
                  } catch (const jsi::JSError &error) {
                    throw jsi::JSError(error);
                  } catch (const std::exception &error) {
                    throw std::runtime_error(error.what());
                  } catch (...) {
                    throw std::runtime_error(
                        moduleName + "." + classDefinition->name + ".startObserving failed.");
                  }

                  if (!context->isObservingSharedObject(objectId, eventName)) {
                    return jsi::Value::undefined();
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
               classDefinition = &classDefinition](
                  jsi::Runtime &rt,
                  const jsi::Value &thisValue,
                  const jsi::Value *arguments,
                  size_t count) {
                if (count == 1 && arguments[0].isString()) {
                  const auto objectId = requireSharedObjectId(
                      rt, thisValue, classDefinition->name);
                  const auto eventName = arguments[0].getString(rt).utf8(rt);
                  context->endObservingSharedObject(objectId, eventName);
                }
                return jsi::Value::undefined();
              }));
    }
    module.setProperty(runtime, classDefinition.name.c_str(), std::move(klass));
  }

  jsi::Object viewPrototypes(runtime);
  for (const auto &view : definition.views) {
    const auto createPrototype = [&]() {
      jsi::Object prototype(runtime);
      for (const auto &function : view.functions) {
        defineFunction(
            runtime,
            prototype,
            context_,
            definition.name + "." + view.name + "." + function.name,
            function);
      }
      return prototype;
    };
    viewPrototypes.setProperty(
        runtime, view.prototypeName.c_str(), createPrototype());
    if (view.defaultView && view.prototypeName != definition.name) {
      viewPrototypes.setProperty(
          runtime, definition.name.c_str(), createPrototype());
    }
  }
  module.setProperty(runtime, "ViewPrototypes", std::move(viewPrototypes));
  return module;
}

}  // namespace expo::harmony
