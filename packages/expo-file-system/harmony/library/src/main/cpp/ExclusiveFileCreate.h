#pragma once

#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace expo::filesystem {

// O_EXCL is required: the ArkTS file API has no exclusive-create flag, and
// moveFile(mode=1) checks existence before rename rather than reserving a name.
inline int exclusiveCreateFile(const char* path) {
  int fd;
  do {
    fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) return errno;
  // Do not retry close after EINTR: the descriptor may already be released.
  return close(fd) == 0 ? 0 : errno;
}

} // namespace expo::filesystem
