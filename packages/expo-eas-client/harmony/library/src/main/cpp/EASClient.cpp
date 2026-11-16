/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include <cerrno>
#include <climits>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <utility>

#include <sys/file.h>
#include <sys/stat.h>

#include "napi/native_api.h"

namespace {

constexpr size_t kUuidLength = 36;

class FileDescriptor {
 public:
  explicit FileDescriptor(int fd) : fd_(fd) {}
  FileDescriptor(const FileDescriptor &) = delete;
  FileDescriptor &operator=(const FileDescriptor &) = delete;

  ~FileDescriptor() {
    const int error = errno;
    Close();
    errno = error;
  }

  int Get() const { return fd_; }
  explicit operator bool() const { return fd_ >= 0; }

  bool Close() {
    const int fd = std::exchange(fd_, -1);
    return fd < 0 || close(fd) == 0;
  }

 private:
  int fd_;
};

int Open(const char *path, int flags, mode_t mode = 0) {
  int fd;
  do {
    fd = open(path, flags | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, mode);
  } while (fd < 0 && errno == EINTR);
  return fd;
}

bool StringArg(napi_env env, napi_value value, char (&out)[PATH_MAX]) {
  napi_valuetype type;
  if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
    return false;
  }

  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length == 0 || length >= PATH_MAX) {
    return false;
  }

  size_t copied = 0;
  return napi_get_value_string_utf8(env, value, out, PATH_MAX, &copied) == napi_ok && copied == length &&
      out[0] == '/' && std::memchr(out, '\0', copied) == nullptr;
}

bool ValidUUID(const char *value, size_t length) {
  if (length != kUuidLength) {
    return false;
  }
  for (size_t i = 0; i < length; ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (value[i] != '-') {
        return false;
      }
      continue;
    }
    const char c = value[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
      return false;
    }
  }
  return true;
}

bool IsRegularFile(int fd) {
  struct stat info {};
  if (fstat(fd, &info) != 0) {
    return false;
  }
  if (!S_ISREG(info.st_mode)) {
    errno = EINVAL;
    return false;
  }
  return true;
}

bool ReadId(const char *path, char (&value)[kUuidLength + 1], bool &exists) {
  const FileDescriptor fd(Open(path, O_RDONLY));
  if (!fd) {
    exists = false;
    return errno == ENOENT;
  }
  if (!IsRegularFile(fd.Get())) {
    return false;
  }

  exists = true;
  size_t total = 0;
  while (total < sizeof(value)) {
    const ssize_t n = read(fd.Get(), value + total, sizeof(value) - total);
    if (n > 0) {
      total += static_cast<size_t>(n);
      continue;
    }
    if (n < 0 && errno == EINTR) {
      continue;
    }
    if (n == 0) {
      break;
    }
    return false;
  }

  if (!ValidUUID(value, total)) {
    errno = EINVAL;
    return false;
  }

  value[kUuidLength] = '\0';
  return true;
}

bool Sync(int fd) {
  int result;
  do {
    result = fsync(fd);
  } while (result != 0 && errno == EINTR);
  return result == 0;
}

bool WriteAll(int fd, const char *data, size_t length) {
  size_t written = 0;
  while (written < length) {
    const ssize_t n = write(fd, data + written, length - written);
    if (n > 0) {
      written += static_cast<size_t>(n);
      continue;
    }
    if (n < 0 && errno == EINTR) {
      continue;
    }
    if (n == 0) {
      errno = EIO;
    }
    return false;
  }
  return Sync(fd);
}

bool SyncDirectory(const char *path) {
  char directory[PATH_MAX];
  std::strncpy(directory, path, sizeof(directory) - 1);
  directory[sizeof(directory) - 1] = '\0';
  char *slash = std::strrchr(directory, '/');
  if (slash == nullptr) {
    return false;
  }
  if (slash == directory) {
    slash[1] = '\0';
  } else {
    *slash = '\0';
  }
  const FileDescriptor fd(Open(directory, O_RDONLY | O_DIRECTORY));
  return fd && Sync(fd.Get());
}

bool Publish(const char *path, const char *candidate) {
  char staging[PATH_MAX];
  if (std::snprintf(staging, sizeof(staging), "%s.tmp", path) >= static_cast<int>(sizeof(staging))) {
    errno = ENAMETOOLONG;
    return false;
  }

  // Under the writer lock, an existing staging file belongs to an interrupted writer.
  if (unlink(staging) != 0 && errno != ENOENT) {
    return false;
  }
  FileDescriptor fd(Open(staging, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR));
  if (!fd) {
    return false;
  }

  if (WriteAll(fd.Get(), candidate, kUuidLength) && fd.Close() && rename(staging, path) == 0) {
    return true;
  }

  const int error = errno;
  unlink(staging);
  errno = error;
  return false;
}

napi_value ClientID(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3];
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || (argc != 1 && argc != 2)) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_ARGUMENT", "Expected path and optional UUID candidate");
    return nullptr;
  }

  char path[PATH_MAX];
  if (!StringArg(env, argv[0], path)) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_PATH", "An absolute canonical path is required");
    return nullptr;
  }
  char lockPath[PATH_MAX];
  if (std::snprintf(lockPath, sizeof(lockPath), "%s.lock", path) >= static_cast<int>(sizeof(lockPath))) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_PATH", "The canonical path is too long");
    return nullptr;
  }

  const FileDescriptor lock(Open(lockPath, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR));
  if (!lock || !IsRegularFile(lock.Get())) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_LOCK", std::strerror(errno));
    return nullptr;
  }

  int locked;
  do {
    locked = flock(lock.Get(), LOCK_EX);
  } while (locked != 0 && errno == EINTR);
  if (locked != 0) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_LOCK", std::strerror(errno));
    return nullptr;
  }

  char id[kUuidLength + 1];
  bool exists = false;
  if (!ReadId(path, id, exists)) {
    const int error = errno;
    napi_throw_error(env, error == EINVAL ? "ERR_EAS_CLIENT_ID_INVALID" : "ERR_EAS_CLIENT_ID_PERSIST", std::strerror(error));
    return nullptr;
  }

  if (!exists && argc == 2) {
    char candidate[kUuidLength + 2];
    size_t length = 0;
    if (napi_get_value_string_utf8(env, argv[1], candidate, sizeof(candidate), &length) != napi_ok || !ValidUUID(candidate, length)) {
      napi_throw_error(env, "ERR_EAS_CLIENT_ID_INVALID", "The EAS client ID must be a valid UUID");
      return nullptr;
    }

    if (!Publish(path, candidate)) {
      const int error = errno;
      napi_throw_error(env, error == ENAMETOOLONG ? "ERR_EAS_CLIENT_ID_PATH" : "ERR_EAS_CLIENT_ID_PERSIST", std::strerror(error));
      return nullptr;
    }

    std::memcpy(id, candidate, length);
    id[kUuidLength] = '\0';
    exists = true;
  }

  // An earlier writer may have renamed the file before its directory sync failed.
  if (exists && !SyncDirectory(path)) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_PERSIST", std::strerror(errno));
    return nullptr;
  }

  napi_value result;
  const napi_status status = exists ? napi_create_string_utf8(env, id, kUuidLength, &result) : napi_get_undefined(env, &result);
  if (status != napi_ok) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_RESULT", "Unable to create the client ID result");
    return nullptr;
  }

  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor props[] = {
      {"clientID", nullptr, ClientID, nullptr, nullptr, nullptr, napi_default, nullptr}};
  if (napi_define_properties(env, exports, 1, props) != napi_ok) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_INIT", "Unable to initialize the client ID store");
    return nullptr;
  }

  return exports;
}

napi_module module = {1, 0, nullptr, Init, "expo_eas_client", nullptr, {0}};
}  // namespace

extern "C" __attribute__((constructor)) void RegisterExpoEASClient() {
  napi_module_register(&module);
}
