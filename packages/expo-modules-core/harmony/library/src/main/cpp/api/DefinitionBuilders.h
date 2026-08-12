#pragma once

#include <concepts>
#include <memory>
#include <optional>
#include <string>
#include <type_traits>
#include <utility>

#include "api/ModuleDefinition.h"
#include "api/TypeConverter.h"

namespace expo::harmony {

template <typename T, typename Factory>
std::pair<std::string, ValueFactory> typedConstant(
    std::string name,
    Factory factory) {
  return {
      std::move(name),
      [factory = std::move(factory)](Invocation &invocation) mutable {
        return convertToJS(invocation.sharedContext(), factory());
      }};
}

template <typename T, typename Getter>
PropertyDefinition typedProperty(std::string name, Getter getter) {
  return PropertyDefinition{
      .name = std::move(name),
      .getter = [getter = std::move(getter)](Invocation &invocation) mutable {
        return convertToJS(invocation.sharedContext(), getter());
      }};
}

template <typename T, typename Getter, typename Setter>
PropertyDefinition typedProperty(
    std::string name,
    Getter getter,
    Setter setter) {
  return PropertyDefinition{
      .name = std::move(name),
      .getter = [getter = std::move(getter)](Invocation &invocation) mutable { return convertToJS(invocation.sharedContext(), getter()); },
      .setter = [setter = std::move(setter)](
                    Invocation &invocation,
                    const facebook::jsi::Value &value) mutable { setter(convertFromJS<T>(
                                                                     invocation.sharedContext(), value, invocation.path() + " value")); }};
}

class ObjectDefinitionBuilder final {
public:
  explicit ObjectDefinitionBuilder(std::string name) {
    definition_.name = std::move(name);
  }

  ObjectDefinitionBuilder &constant(std::string name, ValueFactory factory) {
    definition_.constants.emplace_back(std::move(name), std::move(factory));
    return *this;
  }

  template <typename T, typename Factory>
  ObjectDefinitionBuilder &constant(std::string name, Factory factory) {
    definition_.constants.push_back(
        typedConstant<T>(std::move(name), std::move(factory)));
    return *this;
  }

  ObjectDefinitionBuilder &function(FunctionDefinition definition) {
    definition_.functions.push_back(std::move(definition));
    return *this;
  }

  ObjectDefinitionBuilder &property(PropertyDefinition definition) {
    definition_.properties.push_back(std::move(definition));
    return *this;
  }

  ObjectDefinition build() && {
    return std::move(definition_);
  }

private:
  ObjectDefinition definition_;
};

/**
 * Builds an Expo JavaScript class without an associated NativeSharedObject.
 * Instance bodies can access the receiver through Invocation::thisValue().
 */
class JavaScriptClassDefinitionBuilder final {
public:
  explicit JavaScriptClassDefinitionBuilder(std::string name) {
    definition_.name = std::move(name);
  }

  JavaScriptClassDefinitionBuilder &constructor(
      FunctionBody body,
      size_t arity = 0,
      std::optional<size_t> requiredArity = std::nullopt) {
    definition_.constructorArity = arity;
    definition_.constructorRequiredArity = requiredArity.value_or(arity);
    definition_.javaScriptConstructor = std::move(body);
    return *this;
  }

  JavaScriptClassDefinitionBuilder &constant(
      std::string name,
      ValueFactory factory) {
    definition_.constants.emplace_back(std::move(name), std::move(factory));
    return *this;
  }

  template <typename T, typename Factory>
  JavaScriptClassDefinitionBuilder &constant(
      std::string name,
      Factory factory) {
    definition_.constants.push_back(
        typedConstant<T>(std::move(name), std::move(factory)));
    return *this;
  }

  JavaScriptClassDefinitionBuilder &function(FunctionDefinition definition) {
    definition_.javaScriptFunctions.push_back(std::move(definition));
    return *this;
  }

  JavaScriptClassDefinitionBuilder &property(PropertyDefinition definition) {
    definition_.javaScriptProperties.push_back(std::move(definition));
    return *this;
  }

  JavaScriptClassDefinitionBuilder &staticFunction(
      FunctionDefinition definition) {
    definition_.staticFunctions.push_back(std::move(definition));
    return *this;
  }

  JavaScriptClassDefinitionBuilder &staticProperty(
      PropertyDefinition definition) {
    definition_.staticProperties.push_back(std::move(definition));
    return *this;
  }

  ClassDefinition build() && {
    return std::move(definition_);
  }

private:
  ClassDefinition definition_;
};

template <typename Native, typename Return, typename... Arguments, typename Body, size_t... Indices>
facebook::jsi::Value invokeTypedSharedBody(
    Invocation &invocation,
    const std::shared_ptr<NativeSharedObject> &object,
    Body &body,
    std::index_sequence<Indices...>) {
  static_assert(std::derived_from<Native, NativeSharedObject>);
  invocation.requireArgumentCount(
      requiredArgumentCount<Arguments...>(), sizeof...(Arguments));
  auto owner = std::dynamic_pointer_cast<Native>(object);
  if (!owner) {
    throw CodedError(
        "ERR_SHARED_OBJECT_TYPE",
        invocation.path() + " received an incompatible native owner.");
  }
  ArgumentReader reader(invocation);
  if constexpr (std::is_void_v<Return>) {
    body(*owner, reader.template get<Arguments>(Indices)...);
    return facebook::jsi::Value::undefined();
  } else {
    return convertToJS(
        invocation.sharedContext(),
        body(*owner, reader.template get<Arguments>(Indices)...));
  }
}

template <typename Native, typename Return, typename... Arguments, typename Body>
SharedObjectFunctionDefinition typedSharedFunction(
    std::string name,
    Body body) {
  SharedObjectFunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = sizeof...(Arguments);
  definition.requiredArity = requiredArgumentCount<Arguments...>();
  definition.body = [body = std::move(body)](
                        Invocation &invocation,
                        const std::shared_ptr<NativeSharedObject> &object) mutable {
    return invokeTypedSharedBody<Native, Return, Arguments...>(
        invocation,
        object,
        body,
        std::index_sequence_for<Arguments...>{});
  };
  return definition;
}

template <typename Native, typename Return, typename... Arguments, typename Body>
SharedObjectFunctionDefinition typedSharedAsyncFunction(
    std::string name,
    Body body,
    FunctionQueue queue = FunctionQueue::Modules) {
  static_assert(std::derived_from<Native, NativeSharedObject>);
  SharedObjectFunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = sizeof...(Arguments);
  definition.requiredArity = requiredArgumentCount<Arguments...>();
  definition.async = true;
  definition.queue = queue;
  definition.asyncBody =
      [body = std::move(body), queue](
          Invocation &invocation,
          const std::shared_ptr<NativeSharedObject> &object,
          const std::shared_ptr<Promise> &promise) mutable {
        if (queue != FunctionQueue::JavaScript && (isJavaScriptBound<Return> || (isJavaScriptBound<Arguments> || ...))) {
          throw CodedError(
              "ERR_WRONG_THREAD",
              invocation.path() + " uses a JSI-bound type and must run on the JavaScript queue.");
        }
        auto owner = std::dynamic_pointer_cast<Native>(object);
        if (!owner) {
          throw CodedError(
              "ERR_SHARED_OBJECT_TYPE",
              invocation.path() + " received an incompatible native owner.");
        }
        auto context = invocation.sharedContext();
        auto arguments = readTypedArguments<Arguments...>(
            invocation, std::index_sequence_for<Arguments...>{});
        context->dispatch(
            queue,
            [body,
             context,
             owner = std::move(owner),
             arguments = std::move(arguments),
             promise]() mutable {
              try {
                promise->cancellationToken()->throwIfCancellationRequested();
                if constexpr (std::is_void_v<Return>) {
                  std::apply(
                      [&](auto &&...values) {
                        body(*owner, std::forward<decltype(values)>(values)...);
                      },
                      std::move(arguments));
                  promise->resolveUndefined();
                } else {
                  auto result = std::apply(
                      [&](auto &&...values) {
                        return body(
                            *owner, std::forward<decltype(values)>(values)...);
                      },
                      std::move(arguments));
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
                    "The native SharedObject function threw a non-standard exception.");
              }
            });
      };
  return definition;
}

template <typename Native, typename T, typename Getter>
SharedObjectPropertyDefinition typedSharedProperty(
    std::string name,
    Getter getter) {
  static_assert(std::derived_from<Native, NativeSharedObject>);
  return SharedObjectPropertyDefinition{
      .name = std::move(name),
      .getter = [getter = std::move(getter)](
                    Invocation &invocation,
                    const std::shared_ptr<NativeSharedObject> &object) mutable {
        auto owner = std::dynamic_pointer_cast<Native>(object);
        if (!owner) {
          throw CodedError(
              "ERR_SHARED_OBJECT_TYPE",
              invocation.path() + " received an incompatible native owner.");
        }
        return convertToJS(invocation.sharedContext(), getter(*owner));
      }};
}

template <typename Native, typename T, typename Getter, typename Setter>
SharedObjectPropertyDefinition typedSharedProperty(
    std::string name,
    Getter getter,
    Setter setter) {
  auto definition = typedSharedProperty<Native, T>(
      std::move(name), std::move(getter));
  definition.setter = [setter = std::move(setter)](
                          Invocation &invocation,
                          const std::shared_ptr<NativeSharedObject> &object,
                          const facebook::jsi::Value &value) mutable {
    auto owner = std::dynamic_pointer_cast<Native>(object);
    if (!owner) {
      throw CodedError(
          "ERR_SHARED_OBJECT_TYPE",
          invocation.path() + " received an incompatible native owner.");
    }
    setter(
        *owner,
        convertFromJS<T>(
            invocation.sharedContext(), value, invocation.path() + " value"));
  };
  return definition;
}

template <typename Native>
class ClassDefinitionBuilder final {
public:
  static_assert(std::derived_from<Native, NativeSharedObject>);

  explicit ClassDefinitionBuilder(std::string name) {
    definition_.name = std::move(name);
    definition_.nativeType = std::type_index(typeid(Native));
  }

  ClassDefinitionBuilder &extends(std::string baseClassName) {
    definition_.baseClassName = std::move(baseClassName);
    return *this;
  }

  template <typename... Arguments, typename Body>
  ClassDefinitionBuilder &constructor(Body body) {
    definition_.constructorArity = sizeof...(Arguments);
    definition_.constructorRequiredArity = requiredArgumentCount<Arguments...>();
    definition_.constructor = [body = std::move(body)](Invocation &invocation) mutable {
      auto arguments = readTypedArguments<Arguments...>(
          invocation, std::index_sequence_for<Arguments...>{});
      auto result = std::apply(body, std::move(arguments));
      static_assert(
          std::convertible_to<decltype(result), std::shared_ptr<Native>>,
          "A SharedObject constructor must return std::shared_ptr<Native>.");
      return std::shared_ptr<NativeSharedObject>(std::move(result));
    };
    return *this;
  }

  ClassDefinitionBuilder &function(SharedObjectFunctionDefinition definition) {
    definition_.functions.push_back(std::move(definition));
    return *this;
  }

  ClassDefinitionBuilder &constant(
      std::string name,
      ValueFactory factory) {
    definition_.constants.emplace_back(std::move(name), std::move(factory));
    return *this;
  }

  template <typename T, typename Factory>
  ClassDefinitionBuilder &constant(std::string name, Factory factory) {
    definition_.constants.push_back(
        typedConstant<T>(std::move(name), std::move(factory)));
    return *this;
  }

  ClassDefinitionBuilder &property(SharedObjectPropertyDefinition definition) {
    definition_.properties.push_back(std::move(definition));
    return *this;
  }

  ClassDefinitionBuilder &staticFunction(FunctionDefinition definition) {
    definition_.staticFunctions.push_back(std::move(definition));
    return *this;
  }

  ClassDefinitionBuilder &staticProperty(PropertyDefinition definition) {
    definition_.staticProperties.push_back(std::move(definition));
    return *this;
  }

  ClassDefinitionBuilder &events(std::vector<std::string> names) {
    definition_.events.insert(
        std::make_move_iterator(names.begin()),
        std::make_move_iterator(names.end()));
    return *this;
  }

  ClassDefinitionBuilder &onStartObserving(
      SharedObjectObservationCallback callback) {
    definition_.startObservers.push_back({.everyEvent = true,
                                          .body = std::move(callback)});
    return *this;
  }

  ClassDefinitionBuilder &onStartObserving(
      SharedObjectLifecycleObservationCallback callback) {
    definition_.startObservers.push_back({.body = [callback = std::move(callback)](
                                                      RuntimeContext &context,
                                                      const std::shared_ptr<NativeSharedObject> &object,
                                                      const std::string &) { callback(context, object); }});
    return *this;
  }

  ClassDefinitionBuilder &onStartObserving(
      std::string eventName,
      SharedObjectObservationCallback callback) {
    definition_.startObservers.push_back({.eventName = std::move(eventName),
                                          .body = std::move(callback)});
    return *this;
  }

  ClassDefinitionBuilder &onStopObserving(
      SharedObjectObservationCallback callback) {
    definition_.stopObservers.push_back({.everyEvent = true,
                                         .body = std::move(callback)});
    return *this;
  }

  ClassDefinitionBuilder &onStopObserving(
      SharedObjectLifecycleObservationCallback callback) {
    definition_.stopObservers.push_back({.body = [callback = std::move(callback)](
                                                     RuntimeContext &context,
                                                     const std::shared_ptr<NativeSharedObject> &object,
                                                     const std::string &) { callback(context, object); }});
    return *this;
  }

  ClassDefinitionBuilder &onStopObserving(
      std::string eventName,
      SharedObjectObservationCallback callback) {
    definition_.stopObservers.push_back({.eventName = std::move(eventName),
                                         .body = std::move(callback)});
    return *this;
  }

  ClassDefinition build() && {
    return std::move(definition_);
  }

private:
  ClassDefinition definition_;
};

class ViewDefinitionBuilder final {
public:
  explicit ViewDefinitionBuilder(std::string name) {
    definition_.name = std::move(name);
  }

  ViewDefinitionBuilder &componentName(std::string name) {
    definition_.componentName = std::move(name);
    return *this;
  }

  ViewDefinitionBuilder &prototypeName(std::string name) {
    definition_.prototypeName = std::move(name);
    return *this;
  }

  ViewDefinitionBuilder &defaultView(bool value = true) {
    definition_.defaultView = value;
    return *this;
  }

  ViewDefinitionBuilder &prop(std::string name) {
    definition_.props.push_back(ViewPropDefinition{.name = std::move(name)});
    return *this;
  }

  ViewDefinitionBuilder &prop(
      std::string name,
      ViewPropCallback setter,
      folly::dynamic defaultValue = nullptr,
      bool hasDefaultValue = false) {
    definition_.props.push_back(ViewPropDefinition{
        .name = std::move(name),
        .defaultValue = std::move(defaultValue),
        .hasDefaultValue = hasDefaultValue,
        .setter = std::move(setter)});
    return *this;
  }

  ViewDefinitionBuilder &propGroup(
      std::vector<std::string> names,
      ViewPropCallback setter) {
    for (auto &name : names) {
      definition_.props.push_back(ViewPropDefinition{
          .name = std::move(name),
          .setter = setter});
    }
    return *this;
  }

  ViewDefinitionBuilder &events(std::vector<std::string> names) {
    definition_.events.insert(
        definition_.events.end(),
        std::make_move_iterator(names.begin()),
        std::make_move_iterator(names.end()));
    return *this;
  }

  ViewDefinitionBuilder &function(FunctionDefinition definition) {
    definition_.functions.push_back(std::move(definition));
    return *this;
  }

  ViewDefinitionBuilder &group(bool value = true) {
    definition_.group = value;
    return *this;
  }

  ViewDefinitionBuilder &onCreate(ViewLifecycleCallback callback) {
    definition_.onCreate = std::move(callback);
    return *this;
  }

  ViewDefinitionBuilder &onDidUpdateProps(ViewDidUpdateCallback callback) {
    definition_.onDidUpdateProps = std::move(callback);
    return *this;
  }

  ViewDefinitionBuilder &onDestroy(ViewLifecycleCallback callback) {
    definition_.onDestroy = std::move(callback);
    return *this;
  }

  ViewDefinition build() && {
    return std::move(definition_);
  }

private:
  ViewDefinition definition_;
};

class ModuleBuilder final {
public:
  explicit ModuleBuilder(std::string name) : builder_(std::move(name)) {}

  ModuleBuilder &constant(std::string name, ValueFactory factory) {
    builder_.constant(std::move(name), std::move(factory));
    return *this;
  }

  template <typename T, typename Factory>
  ModuleBuilder &constant(std::string name, Factory factory) {
    auto definition = typedConstant<T>(std::move(name), std::move(factory));
    builder_.constant(std::move(definition.first), std::move(definition.second));
    return *this;
  }

  ModuleBuilder &function(FunctionDefinition definition) {
    if (definition.async) {
      builder_.asyncFunction(std::move(definition));
    } else {
      builder_.function(std::move(definition));
    }
    return *this;
  }

  ModuleBuilder &property(PropertyDefinition definition) {
    builder_.property(std::move(definition));
    return *this;
  }

  ModuleBuilder &events(std::vector<std::string> names) {
    builder_.events(std::move(names));
    return *this;
  }

  ModuleBuilder &object(ObjectDefinition definition) {
    builder_.object(std::move(definition));
    return *this;
  }

  ModuleBuilder &klass(ClassDefinition definition) {
    builder_.klass(std::move(definition));
    return *this;
  }

  ModuleBuilder &view(ViewDefinition definition) {
    builder_.view(std::move(definition));
    return *this;
  }

  ModuleBuilder &onCreate(std::function<void(RuntimeContext &)> body) {
    builder_.onCreate(std::move(body));
    return *this;
  }

  ModuleBuilder &onRegisterActivityContracts(
      std::function<void(RuntimeContext &)> body) {
    builder_.onRegisterActivityContracts(std::move(body));
    return *this;
  }

  ModuleBuilder &onDestroy(std::function<void(RuntimeContext &)> body) {
    builder_.onDestroy(std::move(body));
    return *this;
  }

  ModuleBuilder &onForeground(std::function<void(RuntimeContext &)> body) {
    builder_.onForeground(std::move(body));
    return *this;
  }

  ModuleBuilder &onBackground(std::function<void(RuntimeContext &)> body) {
    builder_.onBackground(std::move(body));
    return *this;
  }

  ModuleBuilder &onUserLeaves(std::function<void(RuntimeContext &)> body) {
    builder_.onUserLeaves(std::move(body));
    return *this;
  }

  ModuleBuilder &onActivityDestroy(std::function<void(RuntimeContext &)> body) {
    builder_.onActivityDestroy(std::move(body));
    return *this;
  }

  ModuleBuilder &onNewIntent(
      std::function<void(RuntimeContext &, const folly::dynamic &)> body) {
    builder_.onNewIntent(std::move(body));
    return *this;
  }

  ModuleBuilder &onActivityResult(
      std::function<void(RuntimeContext &, int, int, const folly::dynamic &)> body) {
    builder_.onActivityResult(std::move(body));
    return *this;
  }

  ModuleBuilder &onStartObserving(
      std::function<void(RuntimeContext &, const std::string &)> body) {
    builder_.onStartObserving(std::move(body));
    return *this;
  }

  ModuleBuilder &onStartObserving(std::function<void(RuntimeContext &)> body) {
    builder_.onStartObserving(std::move(body));
    return *this;
  }

  ModuleBuilder &onStartObserving(
      std::string eventName,
      std::function<void(RuntimeContext &)> body) {
    builder_.onStartObserving(std::move(eventName), std::move(body));
    return *this;
  }

  ModuleBuilder &onStopObserving(
      std::function<void(RuntimeContext &, const std::string &)> body) {
    builder_.onStopObserving(std::move(body));
    return *this;
  }

  ModuleBuilder &onStopObserving(std::function<void(RuntimeContext &)> body) {
    builder_.onStopObserving(std::move(body));
    return *this;
  }

  ModuleBuilder &onStopObserving(
      std::string eventName,
      std::function<void(RuntimeContext &)> body) {
    builder_.onStopObserving(std::move(eventName), std::move(body));
    return *this;
  }

  ModuleDefinition build() && {
    return std::move(builder_).build();
  }

private:
  ModuleDefinitionBuilder builder_;
};

}  // namespace expo::harmony
