/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "RuntimeInstaller.h"

#include <cmath>
#include <limits>
#include <common/EventEmitter.h>
#include <common/JSI/JSIUtils.h>
#include <common/NativeModule.h>
#include <common/SharedObject.h>
#include <common/SharedRef.h>

#include "errors/CodedError.h"
#include "modules/ModulesHostObject.h"
#include "runtime/ModuleRegistry.h"
#include "runtime/Protocol.h"
#include "runtime/RuntimeContext.h"
#include "worklets/WorkletRuntimeInstaller.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

class RuntimeContextNativeState final : public jsi::NativeState {
public:
  explicit RuntimeContextNativeState(std::shared_ptr<RuntimeContext> context)
      : context_(std::move(context)) {}

  ~RuntimeContextNativeState() override {
    context_->invalidate();
  }

  std::shared_ptr<RuntimeContext> context() const {
    return context_;
  }

private:
  std::shared_ptr<RuntimeContext> context_;
};

void defineReadOnly(
    jsi::Runtime &runtime,
    jsi::Object &object,
    const char *name,
    jsi::Value value,
    bool enumerable = true) {
  expo::common::defineProperty(runtime, &object, name, {.configurable = false, .enumerable = enumerable, .writable = false, .value = std::move(value)});
}

void defineCoreAlias(
    jsi::Runtime &runtime,
    jsi::Object &expoObject,
    const char *name) {
  expo::common::defineProperty(
      runtime,
      &expoObject,
      name,
      {
          .configurable = false,
          .enumerable = true,
          .get = [property = std::string(name)](jsi::Runtime &rt, jsi::Object) {
            auto expo = rt.global().getPropertyAsObject(rt, "expo");
            auto modules = expo.getPropertyAsObject(rt, "modules");
            auto core = modules.getPropertyAsObject(rt, "ExpoModulesCore");
            return core.getProperty(rt, property.c_str());
          },
      });
}

}  // namespace

std::shared_ptr<RuntimeContext> RuntimeInstaller::installedContext(
    jsi::Runtime &runtime, bool requireAcceptingTasks) {
  auto existing = runtime.global().getProperty(runtime, "expo");
  if (!existing.isObject()) {
    return nullptr;
  }

  auto expoObject = existing.getObject(runtime);
  auto marker = expoObject.getProperty(runtime, "__expo_harmony_runtime_context__");
  if (!marker.isBool() || !marker.getBool() || !expoObject.hasNativeState<RuntimeContextNativeState>(runtime)) {
    return nullptr;
  }

  auto nativeState = expoObject.getNativeState<RuntimeContextNativeState>(runtime);
  auto context = nativeState ? nativeState->context() : nullptr;

  return context && context->isAlive() && (!requireAcceptingTasks || context->isAcceptingTasks())
           ? context
           : nullptr;
}

void RuntimeInstaller::uninstall(
    jsi::Runtime &runtime,
    const RuntimeContext *context) {
  auto value = runtime.global().getProperty(runtime, "expo");
  if (!value.isObject()) {
    return;
  }

  auto object = value.getObject(runtime);
  if (!object.hasNativeState<RuntimeContextNativeState>(runtime) || object.getNativeState<RuntimeContextNativeState>(runtime)->context().get() != context) {
    return;
  }

  auto global = runtime.global();
  expo::common::defineProperty(runtime, &global, "expo", {.configurable = true, .enumerable = true, .writable = true, .value = jsi::Value::undefined()});
}

bool RuntimeInstaller::install(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context,
    bool workletRuntime) {
  auto existing = runtime.global().getProperty(runtime, "expo");
  if (existing.isObject()) {
    auto existingObject = existing.getObject(runtime);
    auto marker = existingObject.getProperty(runtime, "__expo_harmony_runtime_context__");
    if (marker.isBool() && marker.getBool()) {
      return false;
    }
  }

  jsi::Object expoObject(runtime);
  expo::common::defineProperty(
      runtime,
      &expoObject,
      "__expo_harmony_runtime_context__",
      {
          .configurable = true,
          .enumerable = false,
          .writable = true,
          .value = false,
      });

  auto global = runtime.global();
  expo::common::defineProperty(runtime, &global, "expo", {.configurable = true, .enumerable = true, .writable = true, .value = jsi::Value(runtime, expoObject)});
  const auto rollback = [&] {
    context->invalidate();
    global.setProperty(runtime, "expo", jsi::Value::undefined());
  };

  try {
    expo::EventEmitter::installClass(runtime);
    expo::NativeModule::installClass(runtime);
    expo::SharedObject::installBaseClass(
        runtime,
        [weakContext = std::weak_ptr<RuntimeContext>(context)](long objectId) {
          if (auto locked = weakContext.lock()) {
            locked->scheduleSharedObjectRelease(objectId);
          }
        });
    expo::SharedRef::installBaseClass(runtime);

    expoObject = runtime.global().getPropertyAsObject(runtime, "expo");
    expoObject.setNativeState(
        runtime, std::make_shared<RuntimeContextNativeState>(context));
    if (!workletRuntime) {
      defineReadOnly(runtime, expoObject, "__expo_app_identifier__",
                     jsi::String::createFromUtf8(runtime, context->runtimeEpochString()));
      context->initializeModuleRegistry();
      auto modulesHost = std::make_shared<ModulesHostObject>(context);
      expoObject.setProperty(
          runtime,
          "modules",
          jsi::Object::createFromHostObject(runtime, std::move(modulesHost)));

      const auto *coreDefinition = context->moduleRegistry().find("ExpoModulesCore");
      auto coreValue = expoObject.getPropertyAsObject(runtime, "modules")
                           .getProperty(runtime, "ExpoModulesCore");
      if (!coreDefinition || !coreValue.isObject()) {
        throw CodedError(
            "ERR_INVALID_DEFINITION",
            "The native ExpoModulesCore definition was not registered.");
      }

      auto core = coreValue.getObject(runtime);
      defineReadOnly(
          runtime,
          expoObject,
          "expoModulesCoreVersion",
          core.getProperty(runtime, "expoModulesCoreVersion"));
      for (const auto &property : coreDefinition->properties) {
        if (property.name != "expoModulesCoreVersion") {
          defineCoreAlias(runtime, expoObject, property.name.c_str());
        }
      }
      for (const auto &[name, _] : coreDefinition->constants) {
        defineCoreAlias(runtime, expoObject, name.c_str());
      }
      for (const auto &function : coreDefinition->functions) {
        const auto *name = function.name.c_str();
        expoObject.setProperty(runtime, name, core.getProperty(runtime, name));
      }
    } else {
      expoObject.setProperty(runtime, "modules",
          jsi::Object::createFromHostObject(runtime, std::make_shared<ModulesHostObject>(context)));
      auto sharedObject = expoObject.getPropertyAsObject(runtime, "SharedObject");
      sharedObject.setProperty(runtime, protocol::kResolveSharedObjectInWorklet,
          jsi::Function::createFromHostFunction(runtime,
              jsi::PropNameID::forAscii(runtime, protocol::kResolveSharedObjectInWorklet), 1,
              [weakContext = std::weak_ptr<RuntimeContext>(context)](
                  jsi::Runtime &rt, const jsi::Value &, const jsi::Value *args, size_t count) -> jsi::Value {
                try {
                  auto context = weakContext.lock();
                  if (!context || !context->isAlive() || !context->isAcceptingTasks()) {
                    throw CodedError("ERR_RUNTIME_DESTROYED", "The Expo worklet runtime was destroyed.");
                  }

                  if (count != 1 || !args[0].isNumber() || !std::isfinite(args[0].getNumber()) ||
                      args[0].getNumber() <= 0 || args[0].getNumber() > 9007199254740991.0 ||
                      args[0].getNumber() > static_cast<double>(std::numeric_limits<long>::max()) ||
                      std::trunc(args[0].getNumber()) != args[0].getNumber()) {
                    throw CodedError("ERR_INVALID_SHARED_OBJECT_ID", "__resolveInWorklet expects a positive safe integer SharedObject ID.");
                  }

                  return context->resolveWorkletSharedObject(static_cast<long>(args[0].getNumber()));
                } catch (const CodedError &error) {
                  throw CodedJSError(rt, error);
                }
              }));
    }

    defineReadOnly(
        runtime,
        expoObject,
        "__expo_harmony_runtime_context__",
        true,
        false);
    expo::common::defineProperty(runtime, &global, "expo", {.configurable = true, .enumerable = true, .writable = false, .value = jsi::Value(runtime, expoObject)});

    return true;
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
    throw CodedError(
        "ERR_RUNTIME_INSTALLATION",
        "Expo Modules could not install the native runtime because native code threw an unknown exception.");
  }
}

}  // namespace expo::harmony
