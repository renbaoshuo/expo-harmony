/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

struct StatementState {
  exsqlite3_stmt *stmt = nullptr;
  // Empty or comment-only SQL prepares successfully without a sqlite3_stmt.
  bool finalized = false;
  bool finished = false;
};

struct SessionState {
  exsqlite3_session *session = nullptr;
};

struct Connection : Resource, std::enable_shared_from_this<Connection> {
  sqlite3 *db = nullptr;
  std::recursive_mutex mutex;
  // Track the native state independently of the wrappers. A wrapper's weak_ptr
  // would already be expired if its destructor were waiting on this mutex.
  std::unordered_set<std::shared_ptr<StatementState>> statements;
  std::unordered_set<std::shared_ptr<SessionState>> sessions;
  std::shared_ptr<EventSink> eventSink;
  bool listen = false;
  ~Connection() override {
    if (db) exsqlite3_close_v2(db);
  }
  std::shared_ptr<Connection> connection() override { return shared_from_this(); }
  void requireOpen() const {
    if (!db) throw NativeError("ERR_ACCESS_CLOSED_RESOURCE", "Access to closed resource");
  }
  void check(int code) const {
    if (code != SQLITE_OK) {
      throw std::runtime_error("Error code " + std::to_string(code) + ": " +
                               (db ? exsqlite3_errmsg(db) : exsqlite3_errstr(code)));
    }
  }
};

struct Statement : Resource {
  std::shared_ptr<Connection> owner;
  std::shared_ptr<StatementState> state = std::make_shared<StatementState>();
  explicit Statement(std::shared_ptr<Connection> db) : owner(std::move(db)) {}
  ~Statement() override {
    std::lock_guard<std::recursive_mutex> lock(owner->mutex);
    if (state->stmt) exsqlite3_finalize(state->stmt);
    owner->statements.erase(state);
  }
  std::shared_ptr<Connection> connection() override { return owner; }
  void requireOpen() const {
    owner->requireOpen();
    if (state->finalized) throw NativeError("ERR_ACCESS_CLOSED_RESOURCE", "Access to closed resource");
  }
};

struct Session : Resource {
  std::shared_ptr<Connection> owner;
  std::shared_ptr<SessionState> state = std::make_shared<SessionState>();
  explicit Session(std::shared_ptr<Connection> db) : owner(std::move(db)) {}
  ~Session() override {
    std::lock_guard<std::recursive_mutex> lock(owner->mutex);
    if (state->session) exsqlite3session_delete(state->session);
    owner->sessions.erase(state);
  }
  std::shared_ptr<Connection> connection() override { return owner; }
  void requireOpen() const {
    owner->requireOpen();
    if (!state->session) throw NativeError("ERR_ACCESS_CLOSED_RESOURCE", "Access to closed resource");
  }
};

template <typename T> std::shared_ptr<T> resource(const Value &value) {
  auto result = std::dynamic_pointer_cast<T>(value.get<Handle>());
  if (!result) throw std::invalid_argument("Incorrect SQLite native resource");
  result->requireOpen();

  return result;
}

int byteCount(size_t size) {
  if (size > static_cast<size_t>(std::numeric_limits<int>::max()))
    throw std::length_error("SQLite value exceeds INT_MAX bytes");

  return static_cast<int>(size);
}

void updateHook(void *context, int action, const char *schema, const char *table, sqlite3_int64 row) noexcept {
  auto *db = static_cast<Connection *>(context);
  if (!db->eventSink || !db->eventSink->listening.load()) return;

  try {
    const char *file = exsqlite3_db_filename(db->db, schema);
    db->eventSink->emit(Value::Record{{"databaseName", std::string(schema)},
                                      {"databaseFilePath", std::string(file ? file : "")},
                                      {"tableName", std::string(table)},
                                      {"rowId", static_cast<double>(row)},
                                      {"typeId", std::string(action == SQLITE_INSERT   ? "insert"
                                                             : action == SQLITE_UPDATE ? "update"
                                                                                       : "delete")}});
  } catch (...) {
    // Notification allocation must not change the result of an already executed write.
  }
}

Value::Array columnValues(exsqlite3_stmt *stmt) {
  Value::Array row;
  const int count = exsqlite3_column_count(stmt);
  row.reserve(count);

  for (int i = 0; i < count; ++i) {
    switch (exsqlite3_column_type(stmt, i)) {
    case SQLITE_INTEGER:
      row.emplace_back(static_cast<double>(exsqlite3_column_int64(stmt, i)));
      break;
    case SQLITE_FLOAT:
      row.emplace_back(exsqlite3_column_double(stmt, i));
      break;
    case SQLITE_TEXT: {
      const auto *text = exsqlite3_column_text(stmt, i);
      if (!text) throw std::bad_alloc();

      row.emplace_back(std::string(reinterpret_cast<const char *>(text), exsqlite3_column_bytes(stmt, i)));
      break;
    }
    case SQLITE_BLOB: {
      const auto *bytes = static_cast<const unsigned char *>(exsqlite3_column_blob(stmt, i));
      const int count = exsqlite3_column_bytes(stmt, i);
      if (!bytes && count) throw std::bad_alloc();

      row.emplace_back(count ? Bytes(bytes, bytes + count) : Bytes{});
      break;
    }
    default:
      row.emplace_back();
      break;
    }
  }

  return row;
}

void bind(Connection &db, exsqlite3_stmt *statement, const Value::Record &params, bool array, bool blobs) {
  for (const auto &[key, value] : params) {
    int index = 0;
    if (array) {
      size_t end = 0;
      const auto number = std::stoll(key, &end);
      if (end != key.size() || number < 0 || number >= std::numeric_limits<int>::max()) {
        throw std::invalid_argument("Invalid positional bind parameter index");
      }

      index = static_cast<int>(number) + 1;
    } else {
      if (key.find('\0') != std::string::npos) continue;
      index = exsqlite3_bind_parameter_index(statement, key.c_str());
    }

    if (index == 0) continue; // Upstream ignores unknown named parameters.

    int status;
    if (blobs) {
      const auto &bytes = value.get<Bytes>();
      status = bytes.empty() ? exsqlite3_bind_zeroblob(statement, index, 0)
                             : exsqlite3_bind_blob(statement, index, bytes.data(), byteCount(bytes.size()),
                                                   SQLITE_TRANSIENT);
    } else if (value.isNull()) {
      status = exsqlite3_bind_null(statement, index);
    } else if (const auto *boolean = std::get_if<bool>(&value.data)) {
      status = exsqlite3_bind_int(statement, index, *boolean ? 1 : 0);
    } else if (const auto *number = std::get_if<double>(&value.data)) {
      if (isInt64(*number)) {
        status = exsqlite3_bind_int64(statement, index, static_cast<int64_t>(*number));
      } else {
        status = exsqlite3_bind_double(statement, index, *number);
      }
    } else {
      const auto &text = value.get<std::string>();
      status = exsqlite3_bind_text(statement, index, text.data(), byteCount(text.size()), SQLITE_TRANSIENT);
    }

    // Keep accepting surplus parameters. A failed bind for an existing
    // parameter (e.g. SQLITE_TOOBIG) must never execute with a different value.
    if (status != SQLITE_RANGE) db.check(status);
  }
}

Bytes copySQLiteBuffer(void *data, int size) {
  std::unique_ptr<void, decltype(&exsqlite3_free)> buffer(data, exsqlite3_free);
  if (!size) return {};
  if (!data || size < 0) throw std::runtime_error("Invalid SQLite output buffer");

  auto *bytes = static_cast<unsigned char *>(data);
  return Bytes(bytes, bytes + size);
}

Bytes changeset(Session &session) {
  int size = 0;
  void *data = nullptr;
  const int status = exsqlite3session_changeset(session.state->session, &size, &data);
  auto bytes = copySQLiteBuffer(data, size);
  session.owner->check(status);

  return bytes;
}

Bytes invert(const Bytes &bytes) {
  int size = 0;
  void *data = nullptr;
  const int status =
      exsqlite3changeset_invert(byteCount(bytes.size()), const_cast<unsigned char *>(bytes.data()), &size, &data);
  auto result = copySQLiteBuffer(data, size);
  if (status != SQLITE_OK) throw std::runtime_error(exsqlite3_errstr(status));

  return result;
}

void close(Connection &db, bool finalize) {
  if (finalize) {
    for (const auto &statement : db.statements) {
      statement->stmt = nullptr;
      statement->finalized = true;
    }
    db.statements.clear();
    // Match upstream: extensions may also prepare statements on this connection.
    while (auto *statement = exsqlite3_next_stmt(db.db, nullptr))
      exsqlite3_finalize(statement);
  }

  // Keep the connection usable when close() fails with SQLITE_BUSY.
  if (exsqlite3_next_stmt(db.db, nullptr)) {
    throw std::runtime_error("Error code " + std::to_string(SQLITE_BUSY) + ": unable to close due to unfinalized statements");
  }

  for (const auto &session : db.sessions) {
    if (session->session) exsqlite3session_delete(session->session);
    session->session = nullptr;
  }
  db.sessions.clear();

  db.check(exsqlite3_close(db.db));
  db.db = nullptr;
  if (db.eventSink) db.eventSink->stop(napi_tsfn_release);
}

Value execute(Task &task) {
  const auto &args = task.args;
  const auto op = task.spec->op;

  if (op == Op::Dispose) {
    auto db = std::dynamic_pointer_cast<Connection>(args[0].get<Handle>());
    if (!db) throw std::invalid_argument("Expected a database handle");

    if (db->db) close(*db, true);

    return {};
  }

  if (op == Op::Open) {
    auto db = std::make_shared<Connection>();
    const auto &options = args[1].get<Value::Record>();
    db->listen = options.at("enableChangeListener").get<bool>();

    if (exsqlite3_open(args[2].isNull() ? cstring(args[0]).c_str() : ":memory:", &db->db) != SQLITE_OK) {
      throw NativeError("E_SQLITE_OPEN_DATABASE",
                        "Could not open database: " +
                            std::string(db->db ? exsqlite3_errmsg(db->db) : "allocation failed"));
    }

    if (!args[2].isNull()) {
      const auto &bytes = args[2].get<Bytes>();
      auto *buffer = static_cast<unsigned char *>(exsqlite3_malloc64(std::max<size_t>(bytes.size(), 1)));
      if (!buffer) throw std::bad_alloc();

      if (!bytes.empty()) std::memcpy(buffer, bytes.data(), bytes.size());

      // FREEONCLOSE transfers ownership even if deserialize fails (SQLite contract).
      db->check(exsqlite3_deserialize(db->db, "main", buffer, bytes.size(), bytes.size(),
                                      SQLITE_DESERIALIZE_RESIZEABLE | SQLITE_DESERIALIZE_FREEONCLOSE));
    }

    return Handle(db);
  }

  if (op >= Op::Run && op <= Op::Finalize) {
    auto statement = resource<Statement>(args[0]);
    auto &db = *statement->owner;
    auto &state = *statement->state;
    auto *stmt = state.stmt;
    if (op != Op::Columns && resource<Connection>(args[1]).get() != &db) {
      throw std::invalid_argument("Statement belongs to a different database");
    }

    // Empty SQL has no statement: step(NULL) fails, but clear_bindings(NULL) can crash.
    if (!stmt && (op == Op::Run || op == Op::Step)) {
      throw std::runtime_error("Error code " + std::to_string(SQLITE_MISUSE) + ": " + exsqlite3_errstr(SQLITE_MISUSE));
    }

    switch (op) {
    case Op::Run: {
      const bool hadActiveCursor = !state.finished;
      state.finished = true;
      const int reset = exsqlite3_reset(stmt);
      // A pending RETURNING write can report a new failure on reset.
      // A completed/failed cursor already reported its last step result.
      if (hadActiveCursor) db.check(reset);

      db.check(exsqlite3_clear_bindings(stmt));
      bind(db, stmt, args[2].get<Value::Record>(), args[4].get<bool>(), false);
      bind(db, stmt, args[3].get<Value::Record>(), args[4].get<bool>(), true);

      const int status = exsqlite3_step(stmt);
      state.finished = status != SQLITE_ROW;
      if (status != SQLITE_ROW && status != SQLITE_DONE) db.check(status);

      return Value::Record{{"lastInsertRowId", static_cast<double>(exsqlite3_last_insert_rowid(db.db))},
                           {"changes", static_cast<double>(exsqlite3_changes(db.db))},
                           {"firstRowValues", status == SQLITE_ROW ? columnValues(stmt) : Value::Array{}}};
    }
    case Op::Step: {
      // SQLite may implicitly reset and re-execute a finished statement.
      if (state.finished) return {};
      const int status = exsqlite3_step(stmt);
      state.finished = status != SQLITE_ROW;
      if (status == SQLITE_ROW) return columnValues(stmt);
      if (status != SQLITE_DONE) db.check(status);

      return {};
    }
    case Op::Reset:
      state.finished = false;
      db.check(exsqlite3_reset(stmt));
      return {};
    case Op::Columns: {
      Value::Array names;
      for (int i = 0; i < exsqlite3_column_count(stmt); ++i) {
        const char *name = exsqlite3_column_name(stmt, i);
        if (!name) throw std::bad_alloc();

        names.emplace_back(std::string(name));
      }

      return names;
    }
    case Op::Finalize: {
      const int status = exsqlite3_finalize(stmt);
      state.stmt = nullptr; // finalize destroys the statement even on failure.
      state.finalized = true;
      db.statements.erase(statement->state);

      db.check(status);

      return {};
    }
    default:
      break;
    }
  }

  if (op >= Op::Attach) {
    auto session = resource<Session>(args[0]);
    auto &db = *session->owner;
    auto &state = *session->state;
    if (resource<Connection>(args[1]).get() != &db) throw std::invalid_argument("Session belongs to a different database");

    switch (op) {
    case Op::Attach:
      db.check(exsqlite3session_attach(state.session, args[2].isNull() ? nullptr : cstring(args[2]).c_str()));
      return {};
    case Op::Enable:
      exsqlite3session_enable(state.session, args[2].get<bool>());
      return {};
    case Op::CloseSession:
      exsqlite3session_delete(state.session);
      state.session = nullptr;
      db.sessions.erase(session->state);
      return {};
    case Op::Changeset:
      return changeset(*session);
    case Op::InvertedChangeset:
      return invert(changeset(*session));
    case Op::InvertChangeset:
      return invert(args[2].get<Bytes>());
    case Op::ApplyChangeset: {
      const auto &bytes = args[2].get<Bytes>();
      db.check(exsqlite3changeset_apply(
          db.db, byteCount(bytes.size()), const_cast<unsigned char *>(bytes.data()), nullptr,
          [](void *, int, exsqlite3_changeset_iter *) { return SQLITE_CHANGESET_REPLACE; }, nullptr));
      return {};
    }
    default:
      break;
    }
  }

  auto db = resource<Connection>(args[0]);
  switch (op) {
  case Op::SyncLibSQL:
    throw NativeError("ERR_UNSUPPORTED_OPERATION", "libSQL is not enabled in this build");
  case Op::Init:
    if (db->listen) exsqlite3_update_hook(db->db, updateHook, db.get());
    return {};
  case Op::Close:
    close(*db, args[1].get<bool>());
    return {};
  case Op::Exec:
    db->check(exsqlite3_exec(db->db, cstring(args[1]).c_str(), nullptr, nullptr, nullptr));
    return {};
  case Op::InTransaction:
    return exsqlite3_get_autocommit(db->db) == 0;
  case Op::Serialize: {
    sqlite3_int64 size = 0;
    auto *data = exsqlite3_serialize(db->db, cstring(args[1]).c_str(), &size, 0);
    std::unique_ptr<void, decltype(&exsqlite3_free)> buffer(data, exsqlite3_free);

    if (!data) throw std::runtime_error("Unable to serialize database: " + std::string(exsqlite3_errmsg(db->db)));
    if (size < 0 || static_cast<uint64_t>(size) > std::numeric_limits<size_t>::max())
      throw std::length_error("Serialized database is too large");

    return Bytes(data, data + static_cast<size_t>(size));
  }
  case Op::Prepare: {
    auto statement = std::make_shared<Statement>(db);
    db->check(exsqlite3_prepare_v2(db->db, cstring(args[1]).c_str(), -1, &statement->state->stmt, nullptr));
    db->statements.insert(statement->state);

    return Handle(statement);
  }
  case Op::CreateSession: {
    auto session = std::make_shared<Session>(db);
    db->check(exsqlite3session_create(db->db, cstring(args[1]).c_str(), &session->state->session));
    db->sessions.insert(session->state);

    return Handle(session);
  }
  case Op::LoadExtension: {
    const auto &path = cstring(args[1]);
    const char *entry = args[2].isNull() || cstring(args[2]).empty() ? nullptr : cstring(args[2]).c_str();
    // Enable only SQLite's C API. SQL source must not gain load_extension().
    db->check(exsqlite3_db_config(db->db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 1, static_cast<int *>(nullptr)));

    char *message = nullptr;
    const int status = exsqlite3_load_extension(db->db, path.c_str(), entry, &message);
    std::unique_ptr<void, decltype(&exsqlite3_free)> buffer(message, exsqlite3_free);
    if (status != SQLITE_OK) throw std::runtime_error(message ? message : exsqlite3_errmsg(db->db));

    return {};
  }
  case Op::Backup: {
    auto source = resource<Connection>(args[2]);
    auto *backup = exsqlite3_backup_init(db->db, cstring(args[1]).c_str(), source->db, cstring(args[3]).c_str());
    if (!backup) throw std::runtime_error(exsqlite3_errmsg(db->db));

    const int step = exsqlite3_backup_step(backup, -1);
    const int finish = exsqlite3_backup_finish(backup);

    if (step != SQLITE_DONE) db->check(step);
    db->check(finish);

    return {};
  }
  default:
    throw std::logic_error("Unknown SQLite operation");
  }
}
