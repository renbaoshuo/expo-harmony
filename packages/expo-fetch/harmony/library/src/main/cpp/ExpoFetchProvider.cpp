#include "ExpoFetchProvider.h"

#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <jsi/JSIDynamic.h>

#include <common/EventEmitter.h>

namespace jsi = facebook::jsi;

namespace expo::harmony::fetch {
namespace {
constexpr const char *kService = "ExpoFetchService";
constexpr char kBase64Alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::vector<uint8_t> base64Decode(const std::string &value) {
  std::array<int, 256> lookup{};
  lookup.fill(-1);

  for (int index = 0; index < 64; ++index) {
    lookup[static_cast<unsigned char>(kBase64Alphabet[index])] = index;
  }

  std::vector<uint8_t> result;
  result.reserve(value.size() / 4 * 3);
  uint32_t accumulator = 0;
  int bits = 0;

  for (const auto character : value) {
    if (character == '=') {
      break;
    }
    const auto decoded = lookup[static_cast<unsigned char>(character)];
    if (decoded < 0) {
      throw CodedError("ERR_FETCH_RESPONSE", "Harmony returned invalid base64 response bytes.");
    }
    accumulator = (accumulator << 6) | static_cast<uint32_t>(decoded);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      result.push_back(static_cast<uint8_t>((accumulator >> bits) & 0xff));
    }
  }
  return result;
}

std::string base64Encode(const std::vector<uint8_t> &bytes) {
  std::string result;
  result.reserve((bytes.size() + 2) / 3 * 4);

  for (size_t index = 0; index < bytes.size(); index += 3) {
    const uint32_t first = bytes[index];
    const uint32_t second = index + 1 < bytes.size() ? bytes[index + 1] : 0;
    const uint32_t third = index + 2 < bytes.size() ? bytes[index + 2] : 0;
    const uint32_t value = (first << 16) | (second << 8) | third;
    result.push_back(kBase64Alphabet[(value >> 18) & 63]);
    result.push_back(kBase64Alphabet[(value >> 12) & 63]);
    result.push_back(index + 1 < bytes.size() ? kBase64Alphabet[(value >> 6) & 63] : '=');
    result.push_back(index + 2 < bytes.size() ? kBase64Alphabet[value & 63] : '=');
  }
  return result;
}

std::vector<uint8_t> bytesFromDynamic(const folly::dynamic &value) {
  std::vector<uint8_t> bytes;

  if (value.isString()) {
    return base64Decode(value.asString());
  }
  if (!value.isArray()) {
    return bytes;
  }
  if (value.size() > 0 && value[0].isString()) {
    for (const auto &item : value) {
      if (!item.isString()) {
        throw CodedError("ERR_FETCH_RESPONSE", "Harmony returned mixed response chunk types.");
      }
      auto chunk = base64Decode(item.asString());
      bytes.insert(bytes.end(), chunk.begin(), chunk.end());
    }

    return bytes;
  }

  bytes.reserve(value.size());
  for (const auto &item : value) {
    const double byte = item.isInt()
                          ? static_cast<double>(item.asInt())
                      : item.isDouble() ? item.asDouble()
                                        : -1;
    if (!std::isfinite(byte) || std::trunc(byte) != byte || byte < 0 || byte > 255) {
      throw CodedError("ERR_FETCH_RESPONSE", "Harmony returned invalid response bytes.");
    }
    bytes.push_back(static_cast<uint8_t>(byte));
  }
  return bytes;
}

std::vector<uint8_t> bytesFromValue(
    jsi::Runtime &runtime,
    const jsi::Value &value) {
  if (value.isUndefined() || value.isNull()) {
    return {};
  }
  if (value.isString()) {
    return base64Decode(value.getString(runtime).utf8(runtime));
  }

  if (value.isObject()) {
    auto object = value.getObject(runtime);
    if (object.isArrayBuffer(runtime)) {
      auto buffer = object.getArrayBuffer(runtime);
      std::vector<uint8_t> bytes(buffer.size(runtime));
      if (!bytes.empty()) {
        std::memcpy(bytes.data(), buffer.data(runtime), bytes.size());
      }
      return bytes;
    }
  }

  return bytesFromDynamic(jsi::dynamicFromValue(runtime, value));
}

jsi::Value arrayBufferFromValue(
    jsi::Runtime &runtime,
    const jsi::Value &value) {
  if (value.isObject() && value.getObject(runtime).isArrayBuffer(runtime)) {
    return jsi::Value(runtime, value);
  }

  const auto bytes = bytesFromValue(runtime, value);
  auto constructor = runtime.global().getPropertyAsFunction(runtime, "ArrayBuffer");
  auto result = constructor.callAsConstructor(runtime, static_cast<double>(bytes.size()));
  auto object = result.getObject(runtime);
  auto buffer = object.getArrayBuffer(runtime);

  if (!bytes.empty()) {
    std::memcpy(buffer.data(runtime), bytes.data(), bytes.size());
  }
  return std::move(result);
}

struct StreamPacket final {
  std::vector<uint8_t> data;
  bool done{false};
  bool completed{false};
  std::string error;
};

StreamPacket parsePacket(jsi::Runtime &runtime, const jsi::Value &value) {
  if (!value.isObject()) {
    throw CodedError("ERR_FETCH_RESPONSE", "Harmony returned an invalid stream packet.");
  }

  auto object = value.getObject(runtime);
  StreamPacket packet;
  packet.data = bytesFromValue(runtime, object.getProperty(runtime, "data"));

  auto done = object.getProperty(runtime, "done");
  auto completed = object.getProperty(runtime, "completed");
  auto error = object.getProperty(runtime, "error");
  packet.done = done.isBool() && done.getBool();
  packet.completed = completed.isBool() && completed.getBool();
  if (error.isString()) {
    packet.error = error.getString(runtime).utf8(runtime);
  }
  return packet;
}

std::string rejectionMessage(jsi::Runtime &runtime, const jsi::Value *arguments, size_t count) {
  if (count == 0) {
    return "Harmony fetch failed.";
  }

  try {
    return arguments[0].toString(runtime).utf8(runtime);
  } catch (...) {
    return "Harmony fetch failed.";
  }
}

jsi::Object platformPromise(
    const std::shared_ptr<RuntimeContext> &context,
    jsi::Runtime &runtime,
    const std::string &method,
    folly::dynamic arguments) {
  auto value = context->invokePlatformService(kService, method, std::move(arguments));
  if (!value.isObject()) {
    throw CodedError("ERR_FETCH_PLATFORM", "Harmony fetch service did not return a Promise.");
  }

  auto object = value.getObject(runtime);
  if (!object.getProperty(runtime, "then").isObject()) {
    throw CodedError("ERR_FETCH_PLATFORM", "Harmony fetch service returned an invalid Promise.");
  }
  return object;
}

class NativeResponse final : public NativeSharedObject {
public:
  void attach(std::string requestId) {
    std::scoped_lock lock(mutex_);
    requestId_ = std::move(requestId);
  }

  void attachContext(const std::shared_ptr<RuntimeContext> &context) {
    std::scoped_lock lock(mutex_);
    context_ = context;
  }

  std::string requestId() const {
    std::scoped_lock lock(mutex_);
    if (requestId_.empty()) {
      throw CodedError("ERR_FETCH_REQUEST", "The response is not attached to a request.");
    }
    return requestId_;
  }

  void complete(const folly::dynamic &value) {
    if (!value.isObject()) {
      throw CodedError("ERR_FETCH_RESPONSE", "Harmony returned an invalid fetch response.");
    }

    std::scoped_lock lock(mutex_);
    status_ = value.count("status") ? value.at("status").asInt() : -1;
    statusText_ = value.count("statusText") ? value.at("statusText").asString() : "";
    url_ = value.count("url") ? value.at("url").asString() : "";
    redirected_ = value.count("redirected") && value.at("redirected").isBool() && value.at("redirected").asBool();
    headers_ = value.count("headers") && value.at("headers").isArray() ? value.at("headers") : folly::dynamic::array();
  }

  void beginBodyUse(bool streaming) {
    std::scoped_lock lock(mutex_);
    if (bodyUsed_) {
      throw CodedError("ERR_FETCH_BODY_USED", "The response body has already been consumed.");
    }

    bodyUsed_ = true;
    streaming_ = streaming;
  }

  bool bodyUsed() const {
    std::scoped_lock lock(mutex_);
    return bodyUsed_;
  }

  void cancelStreaming() {
    std::scoped_lock lock(mutex_);
    streamingCancelled_ = true;
  }

  bool streamingCancelled() const {
    std::scoped_lock lock(mutex_);
    return streamingCancelled_;
  }

  int status() const {
    std::scoped_lock lock(mutex_);
    return status_;
  }

  std::string statusText() const {
    std::scoped_lock lock(mutex_);
    return statusText_;
  }

  std::string url() const {
    std::scoped_lock lock(mutex_);
    return url_;
  }

  bool redirected() const {
    std::scoped_lock lock(mutex_);
    return redirected_;
  }

  folly::dynamic headers() const {
    std::scoped_lock lock(mutex_);
    return headers_;
  }

  void notifyUnusedCompletion() {
    bool shouldFinalize = false;
    {
      std::scoped_lock lock(mutex_);
      shouldFinalize = !bodyUsed_ && !finalized_;
      if (shouldFinalize) {
        finalized_ = true;
      }
    }
    if (shouldFinalize) {
      sendEvent("readyForJSFinalization");
    }
  }

  void finalize() {
    bool shouldFinalize = false;
    {
      std::scoped_lock lock(mutex_);
      shouldFinalize = !finalized_;
      finalized_ = true;
    }
    if (shouldFinalize) {
      sendEvent("readyForJSFinalization");
    }
  }

  void deallocate() override {
    std::shared_ptr<RuntimeContext> context;
    std::string requestId;

    {
      std::scoped_lock lock(mutex_);
      context = context_.lock();
      requestId = requestId_;
    }
    if (!context || !context->isAlive() || requestId.empty()) {
      return;
    }

    try {
      context->invokePlatformService(kService, "discard", folly::dynamic::array(requestId));
    } catch (...) {
    }
  }

private:
  mutable std::mutex mutex_;
  std::string requestId_;
  std::weak_ptr<RuntimeContext> context_;
  int status_{-1};
  std::string statusText_;
  std::string url_;
  bool redirected_{false};
  folly::dynamic headers_{folly::dynamic::array()};
  bool bodyUsed_{false};
  bool streaming_{false};
  bool streamingCancelled_{false};
  bool finalized_{false};
};

class NativeRequest final : public NativeSharedObject {
public:
  explicit NativeRequest(std::shared_ptr<NativeResponse> response)
      : response_(std::move(response)), id_("expo-fetch-" + std::to_string(nextId_.fetch_add(1))) {
    if (!response_) {
      throw CodedError("ERR_FETCH_RESPONSE", "NativeRequest requires a response.");
    }

    response_->attach(id_);
  }

  const std::shared_ptr<NativeResponse> &response() const {
    return response_;
  }

  const std::string &id() const {
    return id_;
  }

  void cancel(RuntimeContext &context) {
    if (cancelled_.exchange(true)) {
      return;
    }

    context.invokePlatformService(kService, "cancel", folly::dynamic::array(id_));
  }

  void deallocate() override {}

private:
  inline static std::atomic_uint64_t nextId_{1};
  std::shared_ptr<NativeResponse> response_;
  std::string id_;
  std::atomic_bool cancelled_{false};
};

void emitBytes(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context,
    const std::shared_ptr<NativeResponse> &response,
    const std::vector<uint8_t> &bytes) {
  auto emitterValue = convertToJS(context, response);
  auto emitter = emitterValue.getObject(runtime);
  std::vector<jsi::Value> arguments;

  arguments.emplace_back(convertToJS(context, bytes));
  expo::EventEmitter::emitEvent(runtime, emitter, "didReceiveResponseData", arguments);
}

void emitStreamFailure(const std::shared_ptr<NativeResponse> &response, const std::string &error) {
  response->sendEvent("didFailWithError", {error});
  response->finalize();
}

void pumpStream(
    const std::shared_ptr<RuntimeContext> &context,
    const std::shared_ptr<NativeResponse> &response) {
  auto &runtime = context->runtime();
  auto promise = platformPromise(context, runtime, "readChunk", folly::dynamic::array(response->requestId()));
  auto then = promise.getPropertyAsFunction(runtime, "then");

  auto onFulfilled = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "readExpoFetchChunk"), 1, [context, response](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) {
        if (response->streamingCancelled()) {
          response->finalize();
          return jsi::Value::undefined();
        }

        if (count == 0) {
          emitStreamFailure(response, "ERR_FETCH_RESPONSE: missing stream packet");
          return jsi::Value::undefined();
        }

        try {
          const auto packet = parsePacket(callbackRuntime, arguments[0]);

          if (!packet.error.empty()) {
            emitStreamFailure(response, packet.error);
          } else if (packet.done) {
            response->sendEvent("didComplete");
            response->finalize();
          } else {
            if (!packet.data.empty()) {
              emitBytes(callbackRuntime, context, response, packet.data);
            }
            pumpStream(context, response);
          }
        } catch (const std::exception &error) {
          emitStreamFailure(response, error.what());
        }
        return jsi::Value::undefined();
      });
  auto onRejected = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "failExpoFetchChunk"), 1, [response](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) {
        if (response->streamingCancelled()) {
          response->finalize();
          return jsi::Value::undefined();
        }
        emitStreamFailure(response, rejectionMessage(callbackRuntime, arguments, count));
        return jsi::Value::undefined();
      });
  then.callWithThis(runtime, promise, std::move(onFulfilled), std::move(onRejected));
}

void watchCompletion(
    const std::shared_ptr<RuntimeContext> &context,
    const std::shared_ptr<NativeResponse> &response) {
  auto &runtime = context->runtime();
  auto promise = platformPromise(context, runtime, "waitForCompletion", folly::dynamic::array(response->requestId()));
  auto then = promise.getPropertyAsFunction(runtime, "then");

  auto onSettled = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "finishUnusedExpoFetch"), 1, [response](jsi::Runtime &, const jsi::Value &, const jsi::Value *, size_t) {
        response->notifyUnusedCompletion();
        return jsi::Value::undefined();
      });
  auto onRejected = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "finishFailedUnusedExpoFetch"), 1, [response](jsi::Runtime &, const jsi::Value &, const jsi::Value *, size_t) {
        response->notifyUnusedCompletion();
        return jsi::Value::undefined();
      });
  then.callWithThis(runtime, promise, std::move(onSettled), std::move(onRejected));
}

jsi::Value startRequest(Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
  invocation.requireArgumentCount(3, 3);

  auto request = std::dynamic_pointer_cast<NativeRequest>(object);
  if (!request) {
    throw CodedError("ERR_SHARED_OBJECT_TYPE", "NativeRequest.start received an invalid owner.");
  }

  const auto url = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
  const auto init = jsi::dynamicFromValue(invocation.runtime(), invocation.argument(1));

  auto body = folly::dynamic(nullptr);
  if (!invocation.argument(2).isNull() && !invocation.argument(2).isUndefined()) {
    body = base64Encode(convertFromJS<std::vector<uint8_t>>(
        invocation.sharedContext(), invocation.argument(2), invocation.path()));
  }

  auto input = folly::dynamic::object("id", request->id())("url", url)("init", init)("bodyBase64", std::move(body));
  auto context = invocation.sharedContext();
  request->response()->attachContext(context);

  auto &runtime = invocation.runtime();
  auto promise = platformPromise(context, runtime, "start", folly::dynamic::array(std::move(input)));
  auto then = promise.getPropertyAsFunction(runtime, "then");
  auto response = request->response();

  auto onFulfilled = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "completeExpoFetch"), 1, [context, response](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) {
        if (count == 0) {
          throw makeJSError(callbackRuntime, "ERR_FETCH_RESPONSE", "Missing fetch response.");
        }

        try {
          response->complete(jsi::dynamicFromValue(callbackRuntime, arguments[0]));
          watchCompletion(context, response);
          return jsi::Value::undefined();
        } catch (const CodedError &error) {
          response->finalize();
          throw makeJSError(callbackRuntime, error);
        } catch (const std::exception &error) {
          response->finalize();
          throw makeJSError(callbackRuntime, "ERR_FETCH_RESPONSE", error.what());
        }
      });
  auto onRejected = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "failExpoFetch"), 1, [response](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) -> jsi::Value {
        response->finalize();
        if (count > 0 && arguments[0].isObject()) {
          auto error = arguments[0].getObject(callbackRuntime);
          auto code = error.getProperty(callbackRuntime, "code");
          auto message = error.getProperty(callbackRuntime, "message");
          if (code.isString() && message.isString()) {
            throw makeJSError(
                callbackRuntime,
                code.getString(callbackRuntime).utf8(callbackRuntime),
                message.getString(callbackRuntime).utf8(callbackRuntime));
          }
        }

        throw makeJSError(
            callbackRuntime,
            "ERR_FETCH_PLATFORM",
            rejectionMessage(callbackRuntime, arguments, count));
      });
  return then.callWithThis(runtime, promise, std::move(onFulfilled), std::move(onRejected));
}

jsi::Value startStreaming(Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
  invocation.requireArgumentCount(0, 0);

  auto response = std::dynamic_pointer_cast<NativeResponse>(object);
  if (!response) {
    throw CodedError("ERR_SHARED_OBJECT_TYPE", "NativeResponse.startStreaming received an invalid owner.");
  }

  response->beginBodyUse(true);
  auto context = invocation.sharedContext();
  auto &runtime = invocation.runtime();
  auto promise = platformPromise(context, runtime, "startStreaming", folly::dynamic::array(response->requestId()));
  auto then = promise.getPropertyAsFunction(runtime, "then");

  auto onFulfilled = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "startExpoFetchStream"), 1, [context, response](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) {
        if (response->streamingCancelled()) {
          response->finalize();
          return jsi::Value(nullptr);
        }
        if (count == 0) {
          emitStreamFailure(response, "ERR_FETCH_RESPONSE: missing stream packet");
          return jsi::Value(nullptr);
        }

        try {
          const auto packet = parsePacket(callbackRuntime, arguments[0]);
          if (!packet.error.empty()) {
            emitStreamFailure(response, packet.error);
            return jsi::Value(nullptr);
          }
          if (packet.completed) {
            response->finalize();
            return convertToJS(context, packet.data);
          }
          if (!packet.data.empty()) {
            emitBytes(callbackRuntime, context, response, packet.data);
          }

          pumpStream(context, response);
          return jsi::Value(nullptr);
        } catch (const std::exception &error) {
          emitStreamFailure(response, error.what());
          return jsi::Value(nullptr);
        }
      });
  auto onRejected = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "failExpoFetchStream"), 1, [response](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) {
        if (response->streamingCancelled()) {
          response->finalize();
          return jsi::Value(nullptr);
        }
        emitStreamFailure(response, rejectionMessage(callbackRuntime, arguments, count));
        return jsi::Value(nullptr);
      });
  return then.callWithThis(runtime, promise, std::move(onFulfilled), std::move(onRejected));
}

jsi::Value consumeBody(
    Invocation &invocation,
    const std::shared_ptr<NativeSharedObject> &object,
    const std::string &method,
    bool arrayBuffer) {
  invocation.requireArgumentCount(0, 0);

  auto response = std::dynamic_pointer_cast<NativeResponse>(object);
  if (!response) {
    throw CodedError("ERR_SHARED_OBJECT_TYPE", "NativeResponse body method received an invalid owner.");
  }

  response->beginBodyUse(false);
  auto context = invocation.sharedContext();
  auto &runtime = invocation.runtime();
  auto promise = platformPromise(context, runtime, method, folly::dynamic::array(response->requestId()));
  auto then = promise.getPropertyAsFunction(runtime, "then");

  auto onFulfilled = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "consumeExpoFetchBody"), 1, [response, arrayBuffer](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) {
        response->finalize();
        if (count == 0) {
          return jsi::Value::undefined();
        }
        return arrayBuffer
                 ? arrayBufferFromValue(callbackRuntime, arguments[0])
                 : jsi::Value(callbackRuntime, arguments[0]);
      });
  auto onRejected = jsi::Function::createFromHostFunction(
      runtime, jsi::PropNameID::forAscii(runtime, "failExpoFetchBody"), 1, [response](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) -> jsi::Value {
        response->finalize();
        if (count > 0 && arguments[0].isObject()) {
          auto error = arguments[0].getObject(callbackRuntime);
          auto code = error.getProperty(callbackRuntime, "code");
          auto message = error.getProperty(callbackRuntime, "message");
          if (code.isString() && message.isString()) {
            throw makeJSError(
                callbackRuntime,
                code.getString(callbackRuntime).utf8(callbackRuntime),
                message.getString(callbackRuntime).utf8(callbackRuntime));
          }
        }

        throw makeJSError(
            callbackRuntime,
            "ERR_FETCH_PLATFORM",
            rejectionMessage(callbackRuntime, arguments, count));
      });
  return then.callWithThis(runtime, promise, std::move(onFulfilled), std::move(onRejected));
}

class ExpoFetchModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoFetchModule");
    ClassDefinitionBuilder<NativeResponse> response("NativeResponse");
    response.constructor<>([] { return std::make_shared<NativeResponse>(); });

    response.function(SharedObjectFunctionDefinition{.name = "startStreaming", .arity = 0, .async = true, .queue = FunctionQueue::JavaScript, .body = startStreaming});
    response.function(SharedObjectFunctionDefinition{
        .name = "cancelStreaming", .arity = 1, .requiredArity = 1, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          invocation.requireArgumentCount(1, 1);
          auto owner = std::dynamic_pointer_cast<NativeResponse>(object);
          if (!owner) {
            throw CodedError("ERR_SHARED_OBJECT_TYPE", "NativeResponse.cancelStreaming received an invalid owner.");
          }

          owner->cancelStreaming();
          invocation.context().invokePlatformService(kService, "cancelStreaming", folly::dynamic::array(owner->requestId()));
          return jsi::Value::undefined();
        }});
    response.function(SharedObjectFunctionDefinition{.name = "arrayBuffer", .arity = 0, .async = true, .queue = FunctionQueue::JavaScript, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) { return consumeBody(invocation, object, "consumeArrayBuffer", true); }});
    response.function(SharedObjectFunctionDefinition{.name = "text", .arity = 0, .async = true, .queue = FunctionQueue::JavaScript, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) { return consumeBody(invocation, object, "consumeText", false); }});
    response.property(typedSharedProperty<NativeResponse, bool>("bodyUsed", [](NativeResponse &owner) { return owner.bodyUsed(); }));
    response.property(SharedObjectPropertyDefinition{.name = "_rawHeaders", .getter = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) { return jsi::valueFromDynamic(invocation.runtime(), std::dynamic_pointer_cast<NativeResponse>(object)->headers()); }});
    response.property(typedSharedProperty<NativeResponse, int>("status", [](NativeResponse &owner) { return owner.status(); }));
    response.property(typedSharedProperty<NativeResponse, std::string>("statusText", [](NativeResponse &owner) { return owner.statusText(); }));
    response.property(typedSharedProperty<NativeResponse, std::string>("url", [](NativeResponse &owner) { return owner.url(); }));
    response.property(typedSharedProperty<NativeResponse, bool>("redirected", [](NativeResponse &owner) { return owner.redirected(); }));
    module.klass(std::move(response).build());

    ClassDefinitionBuilder<NativeRequest> request("NativeRequest");
    request.constructor<std::shared_ptr<NativeResponse>>([](std::shared_ptr<NativeResponse> response) { return std::make_shared<NativeRequest>(std::move(response)); });

    request.function(SharedObjectFunctionDefinition{.name = "start", .arity = 3, .requiredArity = 3, .async = true, .queue = FunctionQueue::JavaScript, .body = startRequest});
    request.function(SharedObjectFunctionDefinition{.name = "cancel", .arity = 0, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
                                                      std::dynamic_pointer_cast<NativeRequest>(object)->cancel(invocation.context());
                                                      return jsi::Value::undefined();
                                                    }});
    module.klass(std::move(request).build());
    module.onDestroy([](RuntimeContext &context) { context.invokePlatformService(kService, "destroy"); });
    return std::move(module).build();
  }
};
}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoFetchProvider::modules(const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoFetchModule>()};
}
}  // namespace expo::harmony::fetch
