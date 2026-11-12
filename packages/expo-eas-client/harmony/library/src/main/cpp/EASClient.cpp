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

#include <sys/file.h>
#include <sys/stat.h>

#include "napi/native_api.h"

namespace {

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
  return napi_get_value_string_utf8(env, value, out, PATH_MAX, &copied) == napi_ok && copied == length && out[0] == '/' && std::strchr(out, '\0') == out + copied;
}

bool ValidUUID(const char *value, size_t length) {
  if (length != 36) {
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

bool ReadWinner(const char *path, char (&value)[37], bool &exists) {
  int fd;
  do {
    fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) {
    if (errno == ENOENT) {
      exists = false;
      return true;
    }
    return false;
  }
  exists = true;
  size_t total = 0;
  while (total < 37) {
    ssize_t n = read(fd, value + total, 37 - total);
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
    const int error = errno;
    close(fd);
    errno = error;
    return false;
  }
  char extra;
  ssize_t more;
  do {
    more = read(fd, &extra, 1);
  } while (more < 0 && errno == EINTR);
  const int saved = errno;
  close(fd);
  if (more < 0) {
    errno = saved;
    return false;
  }
  if (more != 0 || total != 36 || !ValidUUID(value, total)) {
    errno = EINVAL;
    return false;
  }
  value[36] = '\0';
  errno = saved;
  return true;
}

bool Sync(int fd);

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

bool Sync(int fd) {
  int result;
  do {
    result = fsync(fd);
  } while (result != 0 && errno == EINTR);
  return result == 0;
}

bool SyncDirectory(const char *path) {
  char directory[PATH_MAX];
  std::strncpy(directory, path, sizeof(directory));
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
  int fd;
  do {
    fd = open(directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) {
    return false;
  }
  const bool result = Sync(fd);
  const int error = errno;
  close(fd);
  errno = error;

  return result;
}

napi_value ClientID(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2];
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

  int lock;
  do {
    lock = open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR);
  } while (lock < 0 && errno == EINTR);
  if (lock < 0) {
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_LOCK", std::strerror(errno));
    return nullptr;
  }

  int locked;
  do {
    locked = flock(lock, LOCK_EX);
  } while (locked != 0 && errno == EINTR);
  if (locked != 0) {
    const int error = errno;
    close(lock);
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_LOCK", std::strerror(error));
    return nullptr;
  }

  char winner[37];
  bool exists = false;
  if (!ReadWinner(path, winner, exists)) {
    const int error = errno;
    flock(lock, LOCK_UN);
    close(lock);
    napi_throw_error(env, error == EINVAL ? "ERR_EAS_CLIENT_ID_INVALID" : "ERR_EAS_CLIENT_ID_PERSIST", std::strerror(error));
    return nullptr;
  }
  if (!exists && argc == 2) {
    char candidate[64];
    size_t length = 0;
    if (napi_get_value_string_utf8(env, argv[1], candidate, sizeof(candidate), &length) != napi_ok || !ValidUUID(candidate, length)) {
      flock(lock, LOCK_UN);
      close(lock);
      napi_throw_error(env, "ERR_EAS_CLIENT_ID_INVALID", "The EAS client ID must be a valid UUID");
      return nullptr;
    }

    char temporary[PATH_MAX];
    if (std::snprintf(temporary, sizeof(temporary), "%s.tmp", path) >= static_cast<int>(sizeof(temporary))) {
      flock(lock, LOCK_UN);
      close(lock);
      napi_throw_error(env, "ERR_EAS_CLIENT_ID_PATH", "The canonical path is too long");
      return nullptr;
    }

    int temp;
    do {
      temp = open(temporary, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR);
    } while (temp < 0 && errno == EINTR);
    const bool tempOwned = temp >= 0;
    const bool written = temp >= 0 && WriteAll(temp, candidate, length);
    const int error = errno;
    const int closed = temp >= 0 ? close(temp) : -1;
    if (!written) {
      errno = error;
    }
    const bool published = written && closed == 0 && rename(temporary, path) == 0;
    if (!published) {
      const int error = errno;
      if (tempOwned) {
        unlink(temporary);
      }
      flock(lock, LOCK_UN);
      close(lock);
      napi_throw_error(env, "ERR_EAS_CLIENT_ID_PERSIST", std::strerror(error));
      return nullptr;
    }

    std::memcpy(winner, candidate, length);
    winner[length] = '\0';
    exists = true;
  }

  // An earlier writer may have renamed the file before its directory sync failed.
  if (exists && !SyncDirectory(path)) {
    const int error = errno;
    flock(lock, LOCK_UN);
    close(lock);
    napi_throw_error(env, "ERR_EAS_CLIENT_ID_PERSIST", std::strerror(error));
    return nullptr;
  }

  flock(lock, LOCK_UN);
  close(lock);

  napi_value result;
  const napi_status status = exists ? napi_create_string_utf8(env, winner, 36, &result) : napi_get_undefined(env, &result);
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
