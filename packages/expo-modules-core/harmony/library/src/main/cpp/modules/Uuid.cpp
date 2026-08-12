#include "Uuid.h"

#include "errors/CodedError.h"
#include "modules/UuidCore.h"

#include <array>
#include <cerrno>
#include <cstring>
#include <stdexcept>
#include <sys/random.h>

namespace expo::harmony {

std::string uuidV4() {
  std::array<uint8_t, 16> bytes{};
  size_t offset = 0;
  while (offset < bytes.size()) {
    const auto count = getrandom(
        bytes.data() + offset, bytes.size() - offset, 0);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) {
      throw CodedError(
          "ERR_UUID_ENTROPY",
          "HarmonyOS secure random source failed: " +
              std::string(std::strerror(errno)));
    }
    offset += static_cast<size_t>(count);
  }
  applyUuidVersionAndVariant(bytes, 4);
  return formatUuid(bytes);
}

std::string uuidV5(const std::string& name, const std::string& nameSpace) {
  try {
    return uuidV5Core(name, nameSpace);
  } catch (const std::invalid_argument& error) {
    throw CodedError(
        "ERR_INVALID_NAMESPACE",
        "'" + nameSpace + "' is not a valid UUID namespace: " + error.what() + ".");
  }
}

} // namespace expo::harmony
