/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

// The pinned libSQL archive includes its own SQLite parser. The C binding
// exposes single-statement execution even when the connection is remote-only.
extern "C" int sqlite3_complete(const char *sql);

struct LibSQLCall {
  const char *error = nullptr;
  ~LibSQLCall() {
    if (error) libsql_free_string(error);
  }
  void check(int status) const {
    if (status) throw NativeError("ERR_INTERNAL_SQLITE_ERROR", error ? error : "libSQL operation failed");
  }
};

struct Connection : Resource, std::enable_shared_from_this<Connection> {
  libsql_database_t db = nullptr;
  libsql_connection_t conn = nullptr;
  std::recursive_mutex mutex;
  std::vector<std::weak_ptr<Statement>> statements;
  std::shared_ptr<EventSink> eventSink;
  bool listen = false;
  ~Connection() override {
    if (conn) libsql_disconnect(conn);
    if (db) libsql_close(db);
  }
  std::shared_ptr<Connection> connection() override { return shared_from_this(); }
  void requireOpen() const {
    if (!conn) throw NativeError("ERR_ACCESS_CLOSED_RESOURCE", "Access to closed resource");
  }
};

struct Statement : Resource {
  std::shared_ptr<Connection> owner;
  libsql_stmt_t stmt = nullptr;
  libsql_rows_t rows = nullptr;
  bool finished = false;
  std::optional<Value::Array> columnNames;
  Value::Array bindings;
  explicit Statement(std::shared_ptr<Connection> owner) : owner(std::move(owner)) {}
  ~Statement() override {
    std::lock_guard<std::recursive_mutex> lock(owner->mutex);
    finalize();
  }
  void finalize() {
    if (rows) libsql_free_rows(rows);
    rows = nullptr;
    if (stmt) libsql_free_stmt(stmt);
    stmt = nullptr;
  }
  std::shared_ptr<Connection> connection() override { return owner; }
  void requireOpen() const {
    owner->requireOpen();
    if (!stmt) throw NativeError("ERR_ACCESS_CLOSED_RESOURCE", "Access to closed resource");
  }
  void reset() {
    if (rows) libsql_free_rows(rows);
    rows = nullptr;
    finished = false;

    LibSQLCall call;
    call.check(libsql_reset_stmt(stmt, &call.error));
  }
  libsql_rows_t getRows() {
    if (!rows) {
      LibSQLCall call;
      call.check(libsql_query_stmt(stmt, &rows, &call.error));
      if (!rows) throw std::runtime_error("libsql_query_stmt returned null rows");
    }

    return rows;
  }
};

template <typename T> std::shared_ptr<T> resource(const Value &value) {
  auto result = std::dynamic_pointer_cast<T>(value.get<Handle>());
  if (!result) throw std::invalid_argument("Incorrect libSQL resource");
  result->requireOpen();

  return result;
}

void close(Connection &db) {
  for (auto &weak : db.statements)
    if (auto stmt = weak.lock()) stmt->finalize();

  if (db.conn) libsql_disconnect(db.conn);
  db.conn = nullptr;
  if (db.db) libsql_close(db.db);
  db.db = nullptr;

  if (db.eventSink) db.eventSink->stop(napi_tsfn_release);
}

void collectBindings(Value::Array &bindings, const Value::Record &params, bool array) {
  if (!array && !params.empty()) {
    throw NativeError("ERR_UNSUPPORTED_OPERATION", "Named parameter binding is not supported in libSQL mode");
  }

  for (const auto &[key, value] : params) {
    size_t end = 0;
    const auto index = std::stoll(key, &end);
    // The pinned libSQL build uses SQLite's default variable limit. The C
    // binding allocates up to the requested index before validating the query.
    if (end != key.size() || index < 0 || index >= 32766) {
      throw NativeError("ERR_INVALID_BIND_PARAMETER", "Invalid bind parameter");
    }

    if (bindings.size() <= static_cast<size_t>(index)) bindings.resize(index + 1);
    bindings[index] = value;
  }
}

void bind(Statement &statement, const Value::Array &bindings) {
  for (size_t i = 0; i < bindings.size(); ++i) {
    const auto &value = bindings[i];
    const int index = static_cast<int>(i) + 1;
    LibSQLCall call;
    if (auto bytes = std::get_if<Bytes>(&value.data)) {
      if (bytes->size() > std::numeric_limits<int>::max()) throw std::length_error("BLOB exceeds INT_MAX bytes");

      // Rust slice::from_raw_parts requires non-null even for a zero-length slice.
      const unsigned char empty = 0;
      call.check(
          libsql_bind_blob(statement.stmt, index, bytes->empty() ? &empty : bytes->data(), bytes->size(), &call.error));
    } else if (value.isNull()) call.check(libsql_bind_null(statement.stmt, index, &call.error));
    else if (auto boolean = std::get_if<bool>(&value.data))
      call.check(libsql_bind_int(statement.stmt, index, *boolean, &call.error));
    else if (auto number = std::get_if<double>(&value.data)) {
      if (isInt64(*number)) {
        call.check(libsql_bind_int(statement.stmt, index, static_cast<int64_t>(*number), &call.error));
      } else call.check(libsql_bind_float(statement.stmt, index, *number, &call.error));
    } else {
      const auto &text = value.get<std::string>();
      if (text.find('\0') != std::string::npos) {
        throw NativeError("ERR_INVALID_BIND_PARAMETER", "libSQL TEXT parameters cannot contain a NUL byte");
      }

      call.check(libsql_bind_string(statement.stmt, index, text.c_str(), &call.error));
    }
  }
}

Value step(Statement &statement) {
  if (statement.finished) return {};

  // A failed or exhausted cursor must not implicitly replay the statement.
  statement.finished = true;
  auto rows = statement.getRows();
  libsql_row_t raw = nullptr;
  LibSQLCall call;
  call.check(libsql_next_row(rows, &raw, &call.error));
  std::unique_ptr<const libsql_row, decltype(&libsql_free_row)> row(raw, libsql_free_row);
  if (!raw) return {};
  statement.finished = false;

  Value::Array result;
  for (int i = 0; i < libsql_column_count(rows); ++i) {
    int type;
    LibSQLCall field;
    field.check(libsql_column_type(rows, raw, i, &type, &field.error));
    switch (type) {
    case LIBSQL_INT: {
      long long number;
      field.check(libsql_get_int(raw, i, &number, &field.error));
      result.emplace_back(static_cast<double>(number));
      break;
    }
    case LIBSQL_FLOAT: {
      double number;
      field.check(libsql_get_float(raw, i, &number, &field.error));
      result.emplace_back(number);
      break;
    }
    case LIBSQL_TEXT: {
      const char *value = nullptr;
      field.check(libsql_get_string(raw, i, &value, &field.error));
      std::unique_ptr<const char, decltype(&libsql_free_string)> text(value, libsql_free_string);

      result.emplace_back(std::string(value ? value : ""));
      break;
    }
    case LIBSQL_BLOB: {
      blob value{};
      field.check(libsql_get_blob(raw, i, &value, &field.error));
      struct BlobOwner {
        blob data;
        ~BlobOwner() { libsql_free_blob(data); }
      } buffer{value};
      if (value.len < 0 || (!value.ptr && value.len)) throw std::runtime_error("Invalid libSQL BLOB");

      auto bytes = reinterpret_cast<const unsigned char *>(value.ptr);
      result.emplace_back(value.len ? Bytes(bytes, bytes + value.len) : Bytes{});
      break;
    }
    case LIBSQL_NULL:
      result.emplace_back();
      break;
    default:
      throw NativeError("ERR_INVALID_CONVERTIBLE", "Unsupported libSQL column type");
    }
  }

  return result;
}

Value::Array getColumnNames(libsql_rows_t rows) {
  Value::Array names;
  for (int i = 0; i < libsql_column_count(rows); ++i) {
    const char *name = nullptr;
    LibSQLCall call;
    call.check(libsql_column_name(rows, i, &name, &call.error));
    std::unique_ptr<const char, decltype(&libsql_free_string)> text(name, libsql_free_string);
    names.emplace_back(std::string(name ? name : ""));
  }

  return names;
}

bool hasStatement(const std::string &sql) {
  size_t i = 0;
  while (i < sql.size()) {
    if (std::isspace(static_cast<unsigned char>(sql[i])) || sql[i] == ';') {
      ++i;
    } else if (sql.compare(i, 2, "--") == 0) {
      const size_t end = sql.find('\n', i + 2);
      if (end == std::string::npos) return false;
      i = end + 1;
    } else if (sql.compare(i, 2, "/*") == 0) {
      const size_t end = sql.find("*/", i + 2);
      if (end == std::string::npos) return false;
      i = end + 2;
    } else {
      return true;
    }
  }
  return false;
}

void exec(Connection &db, const std::string &sql) {
  const auto executeStatement = [&](const std::string &statement) {
    if (!hasStatement(statement)) return;
    LibSQLCall call;
    call.check(libsql_execute(db.conn, statement.c_str(), &call.error));
  };

  size_t start = 0;
  for (size_t end = sql.find(';'); end != std::string::npos; end = sql.find(';', end + 1)) {
    const auto statement = sql.substr(start, end - start + 1);
    // Semicolons inside strings, comments and trigger bodies are not separators.
    if (!sqlite3_complete(statement.c_str())) continue;
    executeStatement(statement);
    start = end + 1;
  }
  executeStatement(sql.substr(start));
}

Value execute(Task &task) {
  const auto &args = task.args;
  const auto op = task.spec->op;

  if (op == Op::Dispose) {
    auto db = std::dynamic_pointer_cast<Connection>(args[0].get<Handle>());
    if (!db) throw std::invalid_argument("Expected database");

    close(*db);

    return {};
  }

  if (op == Op::Open) {
    if (!args[2].isNull()) throw NativeError("ERR_UNSUPPORTED_OPERATION", "Unsupported operation in libSQL mode");

    const auto &options = args[1].get<Value::Record>();
    if (options.at("enableChangeListener").get<bool>()) {
      throw NativeError("ERR_UNSUPPORTED_OPERATION", "Database change notifications are not supported in libSQL mode");
    }
    const auto &url = options.at("libSQLUrl"), &token = options.at("libSQLAuthToken");
    if (url.isNull() || token.isNull())
      throw NativeError("ERR_INVALID_ARGUMENTS", "libSQLUrl and libSQLAuthToken must be provided");

    auto db = std::make_shared<Connection>();
    LibSQLCall call;
    if (options.at("libSQLRemoteOnly").get<bool>()) {
      call.check(libsql_open_remote_with_webpki(cstring(url).c_str(), cstring(token).c_str(), &db->db, &call.error));
    } else {
      libsql_config config{};
      config.db_path = cstring(args[0]).c_str();
      config.primary_url = cstring(url).c_str();
      config.auth_token = cstring(token).c_str();
      config.read_your_writes = 1;
      config.with_webpki = 1;
      config.offline = 1;
      call.check(libsql_open_sync_with_config(config, &db->db, &call.error));
    }

    call.check(libsql_connect(db->db, &db->conn, &call.error));

    return Handle(db);
  }

  if (op >= Op::Run && op <= Op::Finalize) {
    auto stmt = resource<Statement>(args[0]);
    auto db = stmt->owner;
    if (op != Op::Columns && resource<Connection>(args[1]) != db)
      throw std::invalid_argument("Statement belongs to a different database");

    switch (op) {
    case Op::Run: {
      stmt->reset();
      stmt->columnNames.reset();
      stmt->finished = true;
      // Clear previously bound slots omitted on this run. Reset clears
      // libSQL's parameter vector, but the local SQLite bindings can persist.
      Value::Array bindings(stmt->bindings.size());
      const bool array = args[4].get<bool>();
      collectBindings(bindings, args[2].get<Value::Record>(), array);
      collectBindings(bindings, args[3].get<Value::Record>(), array);

      bind(*stmt, bindings);
      stmt->bindings = std::move(bindings);

      stmt->finished = false;
      auto row = step(*stmt);

      return Value::Record{{"lastInsertRowId", static_cast<double>(libsql_last_insert_rowid(db->conn))},
                           {"changes", static_cast<double>(libsql_changes(db->conn))},
                           {"firstRowValues", row.isNull() ? Value(Value::Array{}) : std::move(row)}};
    }
    case Op::Step:
      return step(*stmt);
    case Op::Reset:
      if (stmt->rows && !stmt->columnNames) stmt->columnNames = getColumnNames(stmt->rows);
      stmt->reset();
      stmt->finished = true;
      bind(*stmt, stmt->bindings);
      stmt->finished = false;
      return {};
    case Op::Finalize:
      stmt->finalize();
      return {};
    case Op::Columns: {
      // libsql_query_stmt executes SQL. Metadata lookup must never execute a
      // write, even on a statement that has not run or has been reset.
      if (!stmt->columnNames && stmt->rows) stmt->columnNames = getColumnNames(stmt->rows);
      if (!stmt->columnNames)
        throw NativeError("ERR_UNSUPPORTED_OPERATION", "libSQL column names are only available after execution");
      return *stmt->columnNames;
    }
    default:
      break;
    }
  }

  if (op >= Op::Attach) throw NativeError("ERR_UNSUPPORTED_OPERATION", "Unsupported operation in libSQL mode");

  auto db = resource<Connection>(args[0]);
  LibSQLCall call;
  switch (op) {
  case Op::Init:
    return {};
  case Op::Close:
    close(*db);
    return {};
  case Op::SyncLibSQL:
    call.check(libsql_sync(db->db, &call.error));
    return {};
  case Op::Exec:
    exec(*db, cstring(args[1]));
    return {};
  case Op::Prepare: {
    auto stmt = std::make_shared<Statement>(db);
    call.check(libsql_prepare(db->conn, cstring(args[1]).c_str(), &stmt->stmt, &call.error));

    db->statements.erase(
        std::remove_if(db->statements.begin(), db->statements.end(), [](auto &s) { return s.expired(); }),
        db->statements.end());
    db->statements.emplace_back(stmt);

    return Handle(stmt);
  }
  default:
    throw NativeError("ERR_UNSUPPORTED_OPERATION", "Unsupported operation in libSQL mode");
  }
}
