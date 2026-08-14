#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include <folly/dynamic.h>

#include "api/TypeConverter.h"

namespace expo::harmony {

class ViewHandle final {
public:
  ViewHandle(
      std::weak_ptr<RuntimeContext> context,
      int64_t tag,
      std::string componentName)
      : context_(std::move(context)),
        tag_(tag),
        componentName_(std::move(componentName)) {}

  int64_t tag() const noexcept {
    return tag_;
  }

  const std::string &componentName() const noexcept {
    return componentName_;
  }

  void dispatchCommand(
      std::string commandName,
      folly::dynamic arguments = folly::dynamic::array()) const;
  void emitEvent(
      std::string eventName,
      folly::dynamic payload = folly::dynamic::object()) const;

private:
  std::weak_ptr<RuntimeContext> context_;
  int64_t tag_;
  std::string componentName_;
};

ViewHandle requireViewHandle(
    Invocation &invocation,
    const std::string &componentName);

template <typename Return, typename... Arguments, typename Body, size_t... Indices>
facebook::jsi::Value invokeTypedViewBody(
    Invocation &invocation,
    const std::string &componentName,
    Body &body,
    std::index_sequence<Indices...>) {
  invocation.requireArgumentCount(
      requiredArgumentCount<Arguments...>(), sizeof...(Arguments));
  auto handle = requireViewHandle(invocation, componentName);
  ArgumentReader reader(invocation);
  if constexpr (std::is_void_v<Return>) {
    body(handle, reader.template get<Arguments>(Indices)...);
    return facebook::jsi::Value::undefined();
  } else {
    return convertToJS(
        invocation.sharedContext(),
        body(handle, reader.template get<Arguments>(Indices)...));
  }
}

template <typename Return, typename... Arguments, typename Body>
FunctionDefinition typedViewFunction(
    std::string name,
    std::string componentName,
    Body body) {
  FunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = sizeof...(Arguments);
  definition.requiredArity = requiredArgumentCount<Arguments...>();
  definition.body = [body = std::move(body),
                     componentName = std::move(componentName)](
                        Invocation &invocation) mutable {
    return invokeTypedViewBody<Return, Arguments...>(
        invocation,
        componentName,
        body,
        std::index_sequence_for<Arguments...>{});
  };
  return definition;
}

template <typename Return, typename... Arguments, typename Body>
FunctionDefinition typedAsyncViewFunction(
    std::string name,
    std::string componentName,
    Body body,
    FunctionQueue queue = FunctionQueue::Main) {
  FunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = sizeof...(Arguments);
  definition.requiredArity = requiredArgumentCount<Arguments...>();
  definition.async = true;
  definition.queue = queue;
  definition.asyncBody =
      [body = std::move(body),
       componentName = std::move(componentName),
       queue](Invocation &invocation, const std::shared_ptr<Promise> &promise) mutable {
        if (queue != FunctionQueue::JavaScript && (isJavaScriptBound<Return> || (isJavaScriptBound<Arguments> || ...))) {
          throw CodedError(
              "ERR_WRONG_THREAD",
              invocation.path() + " uses a JSI-bound type and must run on the JavaScript queue.");
        }
        auto handle = requireViewHandle(invocation, componentName);
        auto context = invocation.sharedContext();
        auto arguments = readTypedArguments<Arguments...>(
            invocation, std::index_sequence_for<Arguments...>{});
        context->dispatch(
            queue,
            [body,
             context,
             handle = std::move(handle),
             arguments = std::move(arguments),
             promise]() mutable {
              try {
                promise->cancellationToken()->throwIfCancellationRequested();
                if constexpr (std::is_void_v<Return>) {
                  std::apply(
                      [&](auto &&...values) {
                        body(handle, std::forward<decltype(values)>(values)...);
                      },
                      std::move(arguments));
                  promise->resolveUndefined();
                } else {
                  auto result = std::apply(
                      [&](auto &&...values) {
                        return body(
                            handle, std::forward<decltype(values)>(values)...);
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
                    "The native view function threw a non-standard exception.");
              }
            });
      };
  return definition;
}

}  // namespace expo::harmony
