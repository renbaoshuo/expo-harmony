/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "napi/native_api.h"
#if EXPO_SQLITE_USE_LIBSQL
#include "libsql.h"
#else
#include "sqlite3.h"
#endif

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cmath>
#include <cstring>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <variant>
#include <vector>

namespace {
struct Connection;
struct Statement;
struct Session;
struct Resource {
  virtual ~Resource() = default;
  virtual std::shared_ptr<Connection> connection() = 0;
};
using Handle = std::shared_ptr<Resource>;
using Bytes = std::vector<unsigned char>;
struct Value {
  using Array = std::vector<Value>;
  using Record = std::map<std::string, Value>;
  std::variant<std::monostate, bool, double, std::string, Bytes, Array, Record, Handle> data;
  Value() = default;
  template <typename T> Value(T value) : data(std::move(value)) {}
  template <typename T> const T &get() const {
    const auto *value = std::get_if<T>(&data);
    if (!value) throw std::invalid_argument("Invalid SQLite native argument type");

    return *value;
  }
  bool isNull() const { return std::holds_alternative<std::monostate>(data); }
};

enum class Op {
  Open,
  Dispose,
  SyncLibSQL,
  Init,
  Close,
  Exec,
  InTransaction,
  Serialize,
  Prepare,
  CreateSession,
  LoadExtension,
  Backup,
  Run,
  Step,
  GetAll,
  Reset,
  Columns,
  Finalize,
  Attach,
  Enable,
  CloseSession,
  Changeset,
  InvertedChangeset,
  ApplyChangeset,
  InvertChangeset
};

struct Spec {
  const char *name;
  Op op;
  size_t argc;
  bool async;
};

struct Task {
  const Spec *spec;
  std::vector<Value> args;
  Value value;
  std::string error;
  std::string errorCode = "ERR_INTERNAL_SQLITE_ERROR";
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
};

struct NativeError : std::runtime_error {
  std::string code;
  NativeError(std::string code, std::string message) : std::runtime_error(std::move(message)), code(std::move(code)) {}
};

bool isInt64(double value) {
  // INT64_MAX rounds up to 2^63 as a double. Use an exclusive upper bound.
  constexpr double limit = -static_cast<double>(std::numeric_limits<int64_t>::min());
  return value >= -limit && value < limit && std::trunc(value) == value;
}

const std::string &cstring(const Value &value) {
  const auto &text = value.get<std::string>();
  if (text.find('\0') != std::string::npos) {
    throw NativeError("ERR_INVALID_ARGUMENTS", "SQLite C string argument contains a NUL byte");
  }

  return text;
}

struct EventSink {
  napi_threadsafe_function function = nullptr;
  napi_env env = nullptr;
  bool registered = false;
  std::mutex mutex;
  std::atomic<bool> listening{false};
  ~EventSink() {
    if (registered) napi_remove_env_cleanup_hook(env, cleanup, this);
    stop(napi_tsfn_abort);
  }

  void stop(napi_threadsafe_function_release_mode mode) {
    std::lock_guard<std::mutex> lock(mutex);
    listening.store(false);

    if (function) {
      napi_release_threadsafe_function(function, mode);
      function = nullptr;
    }
  }

  static void cleanup(void *data) {
    auto *sink = static_cast<EventSink *>(data);
    sink->stop(napi_tsfn_abort);
    sink->registered = false;
    sink->env = nullptr;
  }
  void emit(Value event) noexcept;
};
#if EXPO_SQLITE_USE_LIBSQL
#include "LibSQLBackend.h"
#else
#include "SQLiteBackend.h"
#endif

void perform(Task &task) noexcept {
  try {
    std::vector<std::shared_ptr<Connection>> connections;
    for (const auto &arg : task.args) {
      if (auto *handle = std::get_if<Handle>(&arg.data)) connections.push_back((*handle)->connection());
    }

    std::sort(connections.begin(), connections.end(),
              [](const auto &a, const auto &b) { return std::less<Connection *>{}(a.get(), b.get()); });
    connections.erase(std::unique(connections.begin(), connections.end()), connections.end());

    // Hold the connection locks for the whole operation, including every row of
    // getAll. Another run/reset/finalize must not take over its statement cursor.
    std::vector<std::unique_lock<std::recursive_mutex>> locks;
    for (auto &connection : connections)
      locks.emplace_back(connection->mutex);

    if (task.spec->op == Op::GetAll) {
      const Spec spec{"step", Op::Step, 2, false};
      Task step;
      step.spec = &spec;
      step.args = task.args;
      Value::Array rows;
      for (;;) {
        auto row = execute(step);
        if (row.isNull()) break;

        rows.push_back(std::move(row));
      }

      task.value = std::move(rows);
    } else task.value = execute(task);
  } catch (const NativeError &error) {
    task.error = error.what();
    task.errorCode = error.code;
  } catch (const std::exception &error) {
    task.error = error.what();
  } catch (...) {
    task.error = "Unknown SQLite native failure";
  }
}

void checkNapi(napi_status status) {
  if (status != napi_ok) throw std::runtime_error("SQLite Node-API conversion failed (" + std::to_string(status) + ")");
}
const napi_type_tag RESOURCE_TAG = {0x83c384ec451d4e66ULL, 0x9864b8515a013716ULL};
std::string stringValue(napi_env env, napi_value value) {
  size_t size = 0;
  checkNapi(napi_get_value_string_utf8(env, value, nullptr, 0, &size));

  std::string text(size + 1, '\0');
  checkNapi(napi_get_value_string_utf8(env, value, text.data(), text.size(), &size));
  text.resize(size);

  return text;
}

Value fromNapi(napi_env env, napi_value value, unsigned depth = 0) {
  if (depth > 16) throw std::invalid_argument("SQLite argument nesting is too deep");

  napi_valuetype type;
  checkNapi(napi_typeof(env, value, &type));

  switch (type) {
  case napi_null:
  case napi_undefined:
    return {};
  case napi_boolean: {
    bool result;
    checkNapi(napi_get_value_bool(env, value, &result));
    return result;
  }
  case napi_number: {
    double result;
    checkNapi(napi_get_value_double(env, value, &result));
    return result;
  }
  case napi_string:
    return stringValue(env, value);
  case napi_object: {
    bool tagged = false;
    checkNapi(napi_check_object_type_tag(env, value, &RESOURCE_TAG, &tagged));
    if (tagged) {
      void *wrapped = nullptr;
      checkNapi(napi_unwrap(env, value, &wrapped));
      if (!wrapped) throw std::invalid_argument("Invalid SQLite handle");

      return *static_cast<Handle *>(wrapped);
    }

    bool arrayBuffer = false;
    checkNapi(napi_is_arraybuffer(env, value, &arrayBuffer));
    if (arrayBuffer) {
      size_t size;
      void *data;
      checkNapi(napi_get_arraybuffer_info(env, value, &data, &size));
      if (size && !data) throw std::invalid_argument("Invalid ArrayBuffer data");

      // Own the bytes before queuing work; ArkTS memory stays on its JS thread.
      auto *bytes = static_cast<unsigned char *>(data);
      return size ? Bytes(bytes, bytes + size) : Bytes{};
    }

    bool typed = false;
    checkNapi(napi_is_typedarray(env, value, &typed));
    if (typed) {
      napi_typedarray_type kind;
      size_t size, offset;
      void *data;
      napi_value buffer;
      checkNapi(napi_get_typedarray_info(env, value, &kind, &size, &data, &buffer, &offset));
      if (kind != napi_uint8_array) throw std::invalid_argument("Expected Uint8Array");
      if (size && !data) throw std::invalid_argument("Invalid Uint8Array data");

      auto *bytes = static_cast<unsigned char *>(data);
      return size ? Bytes(bytes, bytes + size) : Bytes{};
    }

    napi_value keys;
    checkNapi(napi_get_property_names(env, value, &keys));
    uint32_t count;
    checkNapi(napi_get_array_length(env, keys, &count));
    Value::Record fields;

    for (uint32_t i = 0; i < count; ++i) {
      napi_value key, field;
      checkNapi(napi_get_element(env, keys, i, &key));
      checkNapi(napi_get_property(env, value, key, &field));

      napi_value text;
      checkNapi(napi_coerce_to_string(env, key, &text));
      fields.emplace(stringValue(env, text), fromNapi(env, field, depth + 1));
    }

    return fields;
  }
  default:
    throw std::invalid_argument("Unsupported SQLite argument");
  }
}

napi_value toNapi(napi_env env, const Value &value, bool bytesAsArrayBuffer = true) {
  napi_value result;
  if (value.isNull()) checkNapi(napi_get_null(env, &result));
  else if (auto *item = std::get_if<bool>(&value.data)) checkNapi(napi_get_boolean(env, *item, &result));
  else if (auto *item = std::get_if<double>(&value.data)) checkNapi(napi_create_double(env, *item, &result));
  else if (auto *item = std::get_if<std::string>(&value.data))
    checkNapi(napi_create_string_utf8(env, item->data(), item->size(), &result));
  else if (auto *item = std::get_if<Bytes>(&value.data)) {
    void *data;
    napi_value buffer;
    checkNapi(napi_create_arraybuffer(env, item->size(), &data, &buffer));
    if (!item->empty()) std::memcpy(data, item->data(), item->size());
    if (bytesAsArrayBuffer) result = buffer;
    else checkNapi(napi_create_typedarray(env, napi_uint8_array, item->size(), buffer, 0, &result));
  } else if (auto *item = std::get_if<Value::Array>(&value.data)) {
    checkNapi(napi_create_array_with_length(env, item->size(), &result));
    for (size_t i = 0; i < item->size(); ++i)
      checkNapi(napi_set_element(env, result, i, toNapi(env, (*item)[i], bytesAsArrayBuffer)));
  } else if (auto *item = std::get_if<Value::Record>(&value.data)) {
    checkNapi(napi_create_object(env, &result));
    for (const auto &[key, item] : *item)
      checkNapi(napi_set_named_property(env, result, key.c_str(), toNapi(env, item, bytesAsArrayBuffer)));
  } else {
    auto holder = std::make_unique<Handle>(value.get<Handle>());
    checkNapi(napi_create_object(env, &result));
    checkNapi(napi_type_tag_object(env, result, &RESOURCE_TAG));
    checkNapi(napi_wrap(
        env, result, holder.get(), [](napi_env, void *data, void *) { delete static_cast<Handle *>(data); }, nullptr,
        nullptr));
    holder.release();
  }

  return result;
}

void EventSink::emit(Value event) noexcept {
  try {
    std::lock_guard<std::mutex> lock(mutex);
    if (!function || !listening.load()) return;

    auto payload = std::make_unique<Value>(std::move(event));
    // Nonblocking dispatch: a synchronous caller can be waiting on this connection.
    if (napi_call_threadsafe_function(function, payload.get(), napi_tsfn_nonblocking) == napi_ok) payload.release();
  } catch (...) {
  }
}

napi_value observe(napi_env env, napi_callback_info info) {
  try {
    size_t argc = 3;
    napi_value args[3];
    checkNapi(napi_get_cb_info(env, info, &argc, args, nullptr, nullptr));
    if (argc != 3) throw std::invalid_argument("Expected database, callback and listener state");

    auto db = std::dynamic_pointer_cast<Connection>(fromNapi(env, args[0]).get<Handle>());
    if (!db) throw std::invalid_argument("Expected database");

    bool listening;
    checkNapi(napi_get_value_bool(env, args[2], &listening));

    napi_value result;
    checkNapi(napi_get_undefined(env, &result));
    if (!db->listen) return result;

    // The ArkTS side can still observe a handle while an async close completes.
    std::lock_guard<std::recursive_mutex> lock(db->mutex);
    if (!db->db) return result;

    if (!db->eventSink && listening) {
      auto sink = std::make_shared<EventSink>();
      checkNapi(napi_create_threadsafe_function(
          env, args[1], nullptr, toNapi(env, std::string("ExpoSQLite.onDatabaseChange")), 0, 1, nullptr, nullptr,
          nullptr,
          [](napi_env env, napi_value callback, void *, void *data) {
            std::unique_ptr<Value> event(static_cast<Value *>(data));
            if (!env || !callback) return;
            try {
              napi_value receiver, result, arg = toNapi(env, *event);
              checkNapi(napi_get_undefined(env, &receiver));
              checkNapi(napi_call_function(env, receiver, callback, 1, &arg, &result));
            } catch (...) { /* Never unwind through the Node-API event loop. */
            }
          },
          &sink->function));

      checkNapi(napi_unref_threadsafe_function(env, sink->function));
      sink->env = env;
      checkNapi(napi_add_env_cleanup_hook(env, EventSink::cleanup, sink.get()));
      sink->registered = true;
      db->eventSink = std::move(sink);
    }

    if (db->eventSink) db->eventSink->listening.store(listening);

    return result;
  } catch (const std::exception &error) {
    napi_throw_error(env, "ERR_INTERNAL_SQLITE_ERROR", error.what());
    return nullptr;
  }
}

napi_value outcome(napi_env env, const Task &task) {
  napi_value result;
  checkNapi(napi_create_object(env, &result));
  // SDK 57 returns BLOB columns and session changesets as ArrayBuffer. Database
  // serialization still returns Uint8Array in the upstream native contract.
  checkNapi(napi_set_named_property(env, result, "value", toNapi(env, task.value, task.spec->op != Op::Serialize)));
  checkNapi(napi_set_named_property(env, result, "errorCode", toNapi(env, task.errorCode)));
  checkNapi(napi_set_named_property(env, result, "error", toNapi(env, task.error)));

  return result;
}

napi_value invoke(napi_env env, napi_callback_info info) {
  try {
    size_t argc = 5;
    napi_value argv[5];
    void *data;
    checkNapi(napi_get_cb_info(env, info, &argc, argv, nullptr, &data));
    const auto *spec = static_cast<const Spec *>(data);
    if (argc != spec->argc) throw std::invalid_argument("Incorrect SQLite native argument count");

    auto task = std::make_unique<Task>();
    task->spec = spec;
    for (size_t i = 0; i < argc; ++i)
      task->args.push_back(fromNapi(env, argv[i]));

    if (!spec->async) {
      perform(*task);

      return outcome(env, *task);
    }

    napi_value promise;
    checkNapi(napi_create_promise(env, &task->deferred, &promise));
    checkNapi(napi_create_async_work(
        env, nullptr, toNapi(env, std::string(spec->name)),
        [](napi_env, void *data) { perform(*static_cast<Task *>(data)); },
        [](napi_env env, napi_status status, void *data) {
          std::unique_ptr<Task> task(static_cast<Task *>(data));
          try {
            if (status != napi_ok) throw std::runtime_error("SQLite async operation was cancelled");

            checkNapi(napi_resolve_deferred(env, task->deferred, outcome(env, *task)));
          } catch (const std::exception &error) {
            // A conversion failure may have installed a pending JS exception.
            napi_value exception;
            bool pending = false;
            napi_is_exception_pending(env, &pending);
            if (pending) napi_get_and_clear_last_exception(env, &exception);
            else {
              try {
                checkNapi(napi_create_error(env, toNapi(env, std::string("ERR_INTERNAL_SQLITE_ERROR")),
                                            toNapi(env, std::string(error.what())), &exception));
              } catch (...) {
                napi_get_undefined(env, &exception);
              }
            }

            napi_reject_deferred(env, task->deferred, exception);
          }

          napi_delete_async_work(env, task->work);
        },
        task.get(), &task->work));

    const auto queued = napi_queue_async_work(env, task->work);
    if (queued != napi_ok) {
      napi_delete_async_work(env, task->work);

      napi_value error;
      checkNapi(napi_create_error(env, toNapi(env, std::string("ERR_INTERNAL_SQLITE_ERROR")),
                                  toNapi(env, std::string("Unable to queue SQLite operation")), &error));
      napi_reject_deferred(env, task->deferred, error);

      return promise;
    }

    task.release();

    return promise;
  } catch (const std::exception &error) {
    bool pending = false;
    napi_is_exception_pending(env, &pending);
    if (!pending) napi_throw_error(env, "ERR_INTERNAL_SQLITE_ERROR", error.what());

    return nullptr;
  } catch (...) {
    napi_throw_error(env, "ERR_INTERNAL_SQLITE_ERROR", "Unknown SQLite bridge failure");
    return nullptr;
  }
}

#define PAIR(name, op, argc)                                                                                           \
  {name "Sync", Op::op, argc, false}, { name "Async", Op::op, argc, true }
const Spec SPECS[] = {{"open", Op::Open, 3, false},
                      {"dispose", Op::Dispose, 1, false},
                      {"syncLibSQL", Op::SyncLibSQL, 1, true},
                      PAIR("init", Init, 1),
                      PAIR("close", Close, 2),
                      PAIR("exec", Exec, 2),
                      PAIR("isInTransaction", InTransaction, 1),
                      PAIR("serialize", Serialize, 2),
                      PAIR("prepare", Prepare, 2),
                      PAIR("createSession", CreateSession, 2),
                      PAIR("loadExtension", LoadExtension, 3),
                      PAIR("backup", Backup, 4),
                      PAIR("run", Run, 5),
                      PAIR("step", Step, 2),
                      PAIR("getAll", GetAll, 2),
                      PAIR("reset", Reset, 2),
                      PAIR("getColumnNames", Columns, 1),
                      PAIR("finalize", Finalize, 2),
                      PAIR("attach", Attach, 3),
                      PAIR("enable", Enable, 3),
                      PAIR("closeSession", CloseSession, 2),
                      PAIR("createChangeset", Changeset, 2),
                      PAIR("createInvertedChangeset", InvertedChangeset, 2),
                      PAIR("applyChangeset", ApplyChangeset, 3),
                      PAIR("invertChangeset", InvertChangeset, 3)};
#undef PAIR
napi_value init(napi_env env, napi_value exports) {
  napi_property_descriptor listener{"observe", nullptr, observe, nullptr, nullptr, nullptr, napi_default, nullptr};
  if (napi_define_properties(env, exports, 1, &listener) != napi_ok) return nullptr;

  Value::Record extensions;
#if EXPO_SQLITE_WITH_VEC
  extensions.emplace("sqlite-vec", Value::Record{{"libPath", std::string("libexpo_sqlite_vec.so")},
                                                 {"entryPoint", std::string("sqlite3_vec_init")}});
#endif

  try {
    checkNapi(napi_set_named_property(env, exports, "bundledExtensions", toNapi(env, extensions)));
    checkNapi(napi_set_named_property(env, exports, "useLibSQL", toNapi(env, bool(EXPO_SQLITE_USE_LIBSQL))));
  } catch (const std::exception &error) {
    napi_throw_error(env, "ERR_INTERNAL_SQLITE_ERROR", error.what());
    return nullptr;
  }

  for (const auto &spec : SPECS) {
    napi_property_descriptor property{spec.name, nullptr, invoke,       nullptr,
                                      nullptr,   nullptr, napi_default, const_cast<Spec *>(&spec)};
    if (napi_define_properties(env, exports, 1, &property) != napi_ok) {
      napi_throw_error(env, "ERR_INTERNAL_SQLITE_ERROR", "Unable to register SQLite native API");
      return nullptr;
    }
  }

  return exports;
}
napi_module module = {1, 0, nullptr, init, "expo_sqlite", nullptr, {0}};
}

extern "C" __attribute__((constructor)) void RegisterExpoSQLite() { napi_module_register(&module); }
