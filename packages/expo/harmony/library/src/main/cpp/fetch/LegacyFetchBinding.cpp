/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "HttpTransfer.h"

#include <napi/native_api.h>

#include <cstring>
#include <memory>
#include <new>
#include <stdexcept>
#include <thread>

namespace expo::fetch {
namespace {

using Transfer = std::shared_ptr<HttpTransfer>;

void check(napi_status status) {
  if (status != napi_ok) throw std::runtime_error("Unable to marshal a HarmonyOS fetch event");
}

napi_value property(napi_env env, napi_value object, const char *name) {
  napi_value value;
  check(napi_get_named_property(env, object, name, &value));
  return value;
}

std::string readString(napi_env env, napi_value value) {
  size_t size;
  check(napi_get_value_string_utf8(env, value, nullptr, 0, &size));
  std::string result(size + 1, '\0');
  check(napi_get_value_string_utf8(env, value, result.data(), result.size(), &size));
  result.resize(size);
  return result;
}

napi_value stringValue(napi_env env, const std::string &text) {
  napi_value value;
  check(napi_create_string_utf8(env, text.data(), text.size(), &value));
  return value;
}

Request readRequest(napi_env env, napi_value options) {
  Request request;
  request.url = readString(env, property(env, options, "url"));
  request.method = readString(env, property(env, options, "method"));

  request.proxyHost = readString(env, property(env, options, "proxyHost"));
  request.proxyUsername = readString(env, property(env, options, "proxyUsername"));
  request.proxyPassword = readString(env, property(env, options, "proxyPassword"));
  int32_t port;
  check(napi_get_value_int32(env, property(env, options, "proxyPort"), &port));
  request.proxyPort = port;

  auto headers = property(env, options, "headers");
  uint32_t count;
  check(napi_get_array_length(env, headers, &count));

  for (uint32_t i = 0; i < count; ++i) {
    napi_value pair, name, value;
    check(napi_get_element(env, headers, i, &pair));
    check(napi_get_element(env, pair, 0, &name));
    check(napi_get_element(env, pair, 1, &value));

    request.headers.emplace_back(readString(env, name), readString(env, value));
  }

  auto body = property(env, options, "body");
  bool hasBody;
  check(napi_is_arraybuffer(env, body, &hasBody));

  if (hasBody) {
    void *source;
    size_t size;
    check(napi_get_arraybuffer_info(env, body, &source, &size));

    request.body.emplace(size);
    if (size) std::memcpy(request.body->data(), source, size);
  }

  return request;
}

void deliverEvent(napi_env env, napi_value callback, void *, void *data) {
  std::unique_ptr<Event> event(static_cast<Event *>(data));
  if (env == nullptr || callback == nullptr) return;

  try {
    napi_value value;
    check(napi_create_object(env, &value));

    if (event->status) {
      napi_value status, headers;
      check(napi_create_int32(env, static_cast<int32_t>(event->status), &status));
      check(napi_set_named_property(env, value, "status", status));
      check(napi_set_named_property(env, value, "statusText", stringValue(env, event->statusText)));
      check(napi_create_array_with_length(env, event->headers.size(), &headers));
      for (size_t i = 0; i < event->headers.size(); ++i) {
        napi_value pair;
        check(napi_create_array_with_length(env, 2, &pair));
        check(napi_set_element(env, pair, 0, stringValue(env, event->headers[i].first)));
        check(napi_set_element(env, pair, 1, stringValue(env, event->headers[i].second)));
        check(napi_set_element(env, headers, i, pair));
      }
      check(napi_set_named_property(env, value, "headers", headers));
    } else if (!event->data.empty()) {
      void *buffer;
      napi_value bytes;
      check(napi_create_arraybuffer(env, event->data.size(), &buffer, &bytes));
      std::memcpy(buffer, event->data.data(), event->data.size());
      check(napi_set_named_property(env, value, "data", bytes));
    } else if (!event->error.empty()) {
      check(napi_set_named_property(env, value, "error", stringValue(env, event->error)));
    }

    napi_value receiver;
    check(napi_get_undefined(env, &receiver));
    napi_call_function(env, receiver, callback, 1, &value, nullptr);
  } catch (const std::exception &) {
    // Native callbacks must not unwind through the JS event loop.
  }
}

napi_value cancel(napi_env env, napi_callback_info info) {
  void *data = nullptr;
  if (napi_get_cb_info(env, info, nullptr, nullptr, nullptr, &data) == napi_ok && data) {
    (*static_cast<Transfer *>(data))->cancel();
  }
  return nullptr;
}

napi_value start(napi_env env, napi_callback_info info) {
  napi_threadsafe_function callback = nullptr;

  try {
    size_t argc = 2;
    napi_value argv[2];
    check(napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr));
    if (argc != 2) throw std::invalid_argument("Expected fetch options and a callback");

    auto transfer = std::make_shared<HttpTransfer>(readRequest(env, argv[0]));
    auto handle = std::make_unique<Transfer>(transfer);
    napi_value stop;
    check(napi_create_function(env, "cancel", NAPI_AUTO_LENGTH, cancel, handle.get(), &stop));
    check(napi_add_finalizer(env, stop, handle.get(), [](napi_env, void *data, void *) {
      delete static_cast<Transfer *>(data);
    }, nullptr, nullptr));
    handle.release();

    auto cleanup = std::make_unique<Transfer>(transfer);
    check(napi_create_threadsafe_function(
        env, argv[1], nullptr, stringValue(env, "ExpoFetchLegacy"), 64, 1, cleanup.get(),
        [](napi_env, void *data, void *) {
          std::unique_ptr<Transfer> transfer(static_cast<Transfer *>(data));
          (*transfer)->cancel();
        }, nullptr, deliverEvent, &callback));
    cleanup.release();
    check(napi_unref_threadsafe_function(env, callback));

    std::thread([transfer, callback] {
      bool closing = false;
      transfer->run([callback, &closing](Event event) {
        if (closing) return false;

        std::unique_ptr<Event> queued(new (std::nothrow) Event(std::move(event)));
        if (!queued) return false;

        const auto status = napi_call_threadsafe_function(callback, queued.get(), napi_tsfn_blocking);
        if (status == napi_ok) queued.release();
        closing = status == napi_closing;

        return status == napi_ok;
      });

      if (!closing) napi_release_threadsafe_function(callback, napi_tsfn_release);
    }).detach();

    return stop;
  } catch (const std::exception &error) {
    if (callback) napi_release_threadsafe_function(callback, napi_tsfn_abort);

    napi_throw_error(env, "ERR_FETCH_REQUEST", error.what());
    return nullptr;
  }
}

napi_value init(napi_env env, napi_value exports) {
  napi_property_descriptor methods[] = {
      {"start", nullptr, start, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, 1, methods);
  return exports;
}

napi_module module = {1, 0, nullptr, init, "expo_fetch_legacy", nullptr, {nullptr}};

}  // namespace
}  // namespace expo::fetch

extern "C" __attribute__((constructor)) void RegisterExpoFetchLegacy() {
  napi_module_register(&expo::fetch::module);
}
