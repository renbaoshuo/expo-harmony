#include "ExpoFileSystemProvider.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <limits>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <unistd.h>
#include <uv.h>
#include <variant>
#include <vector>

#include <jsi/JSIDynamic.h>

#include <CryptoArchitectureKit/crypto_digest.h>
#include <sys/statvfs.h>

#include "FileHandleReadUtils.h"

namespace jsi = facebook::jsi;

namespace expo::harmony::filesystem {
namespace {

struct RawFileDescriptor final {
  int fd;
  off_t offset;
  size_t length;
};

class ScopedFileDescriptor final {
public:
  explicit ScopedFileDescriptor(int fd) : fd_(fd) {}

  ScopedFileDescriptor(const ScopedFileDescriptor &) = delete;
  ScopedFileDescriptor &operator=(const ScopedFileDescriptor &) = delete;

  ~ScopedFileDescriptor() {
    if (fd_ >= 0) {
      close(fd_);
    }
  }

  void release() {
    fd_ = -1;
  }

private:
  int fd_;
};

struct DuplicatedRawFileDescriptor final {
  int fd;
  off_t offset;
  size_t length;

  DuplicatedRawFileDescriptor(int fd, off_t offset, size_t length)
      : fd(fd), offset(offset), length(length) {}

  DuplicatedRawFileDescriptor(const DuplicatedRawFileDescriptor &) = delete;
  DuplicatedRawFileDescriptor &operator=(const DuplicatedRawFileDescriptor &) = delete;

  ~DuplicatedRawFileDescriptor() {
    if (fd >= 0) {
      close(fd);
    }
  }
};

using BytesTask = std::function<std::vector<uint8_t>()>;

/**
 * RNOH 0.84 does not install a BACKGROUND task runner and the optional ArkTS
 * WORKER runner is deliberately disabled by the canonical host. File-system
 * work must still stay off the JavaScript thread, so this package owns one
 * process-lifetime serial native queue. Keeping the queue serial also preserves
 * Expo Modules' module-queue ordering for legacy mutations.
 */
class NativeFileSystemExecutor final {
public:
  NativeFileSystemExecutor() : worker_([this]() { run(); }) {}

  NativeFileSystemExecutor(const NativeFileSystemExecutor &) = delete;
  NativeFileSystemExecutor &operator=(const NativeFileSystemExecutor &) = delete;

  ~NativeFileSystemExecutor() {
    {
      std::scoped_lock lock(mutex_);
      stopping_ = true;
    }
    condition_.notify_one();
    if (worker_.joinable()) {
      worker_.join();
    }
  }

  void schedule(std::function<void()> task) {
    if (!task) {
      return;
    }

    {
      std::scoped_lock lock(mutex_);
      if (stopping_) {
        throw CodedError(
            "ERR_FILE_SYSTEM_QUEUE_UNAVAILABLE",
            "The native file-system queue is shutting down.");
      }
      tasks_.push_back(std::move(task));
    }

    condition_.notify_one();
  }

private:
  void run() noexcept {
    while (true) {
      std::function<void()> task;
      {
        std::unique_lock lock(mutex_);
        condition_.wait(lock, [this]() { return stopping_ || !tasks_.empty(); });
        if (stopping_ && tasks_.empty()) {
          return;
        }
        task = std::move(tasks_.front());
        tasks_.pop_front();
      }

      // Every scheduled operation owns its public error conversion. This final
      // guard prevents a non-standard exception from terminating the queue.
      try {
        task();
      } catch (...) {
      }
    }
  }

  std::mutex mutex_;
  std::condition_variable condition_;
  std::deque<std::function<void()>> tasks_;
  bool stopping_{false};
  std::thread worker_;
};

NativeFileSystemExecutor &nativeFileSystemExecutor() {
  static NativeFileSystemExecutor executor;
  return executor;
}

constexpr const char *kService = "ExpoFileSystemService";

std::string percentDecode(const std::string &value) {
  std::string result;
  result.reserve(value.size());
  auto digit = [](char character) -> int {
    if (character >= '0' && character <= '9') {
      return character - '0';
    }
    if (character >= 'a' && character <= 'f') {
      return character - 'a' + 10;
    }
    if (character >= 'A' && character <= 'F') {
      return character - 'A' + 10;
    }
    return -1;
  };

  for (size_t index = 0; index < value.size(); ++index) {
    if (value[index] != '%') {
      result.push_back(value[index]);
      continue;
    }
    if (index + 2 >= value.size()) {
      throw CodedError("ERR_FILE_SYSTEM_INVALID_URI", "URI has an incomplete percent escape.");
    }
    const int high = digit(value[index + 1]);
    const int low = digit(value[index + 2]);
    if (high < 0 || low < 0) {
      throw CodedError("ERR_FILE_SYSTEM_INVALID_URI", "URI has an invalid percent escape.");
    }
    const char decoded = static_cast<char>((high << 4) | low);
    if (decoded == '\0') {
      throw CodedError("ERR_FILE_SYSTEM_INVALID_URI", "URI contains a NUL byte.");
    }

    result.push_back(decoded);
    index += 2;
  }
  return result;
}

std::string percentEncodePath(const std::string &value) {
  std::ostringstream output;
  output << std::uppercase << std::hex;
  for (unsigned char character : value) {
    if ((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '/' || character == '-' || character == '_' || character == '.' || character == '~') {
      output << static_cast<char>(character);
    } else {
      output << '%' << std::setw(2) << std::setfill('0')
             << static_cast<int>(character);
    }
  }
  return output.str();
}

std::string toFileUri(const std::filesystem::path &path, bool directory = false) {
  auto result = std::string("file://") + percentEncodePath(path.string());
  if (directory && !result.ends_with('/')) {
    result.push_back('/');
  }
  return result;
}

bool hasTraversalSegment(const std::filesystem::path &path) {
  return std::any_of(path.begin(), path.end(), [](const auto &part) {
    return part == "..";
  });
}

bool isInside(const std::filesystem::path &root, const std::filesystem::path &value) {
  auto rootIterator = root.begin();
  auto valueIterator = value.begin();
  for (; rootIterator != root.end(); ++rootIterator, ++valueIterator) {
    if (valueIterator == value.end() || *rootIterator != *valueIterator) {
      return false;
    }
  }
  return true;
}

void validateChildName(const std::string &name) {
  if (name.empty() || name == "." || name == ".." || name.find('/') != std::string::npos || name.find('\\') != std::string::npos) {
    throw CodedError("ERR_FILE_SYSTEM_INVALID_NAME", "A child name must be a single path segment.");
  }
}

void requireFileType(const std::filesystem::path &path) {
  if (std::filesystem::exists(path) && !std::filesystem::is_regular_file(path)) {
    throw CodedError("ERR_FILE_SYSTEM_INVALID_FILE_TYPE", "The path points to a directory, not a file.");
  }
}

void requireDirectoryType(const std::filesystem::path &path) {
  if (std::filesystem::exists(path) && !std::filesystem::is_directory(path)) {
    throw CodedError("ERR_FILE_SYSTEM_INVALID_DIRECTORY_TYPE", "The path points to a file, not a directory.");
  }
}

void requireTargetOutsideDirectory(
    const std::filesystem::path &source,
    const std::filesystem::path &target) {
  std::error_code sourceError;
  const auto canonicalSource = std::filesystem::weakly_canonical(source, sourceError);
  std::error_code targetError;
  const auto canonicalTarget = std::filesystem::weakly_canonical(target, targetError);
  if (!sourceError && !targetError && canonicalTarget != canonicalSource
      && isInside(canonicalSource, canonicalTarget)) {
    throw CodedError(
        "ERR_FILE_SYSTEM_INVALID_DESTINATION",
        "A directory cannot be copied or moved into its own subtree.");
  }
}

std::filesystem::path decodeFileUri(const std::string &uri) {
  constexpr std::string_view scheme = "file:";
  if (!uri.starts_with(scheme)) {
    throw CodedError("ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME", "Only file:// URIs can be used for local file operations.");
  }

  auto encoded = uri.substr(scheme.size());
  if (encoded.starts_with("//")) {
    encoded.erase(0, 2);
    if (!encoded.starts_with('/')) {
      constexpr std::string_view localhost = "localhost/";
      if (!encoded.starts_with(localhost)) {
        throw CodedError("ERR_FILE_SYSTEM_UNSUPPORTED_AUTHORITY", "Only empty or localhost file URI authorities are supported.");
      }
      encoded.erase(0, localhost.size() - 1);
    }
  }

  const auto suffix = encoded.find_first_of("?#");
  if (suffix != std::string::npos) {
    encoded.resize(suffix);
  }
  const auto decoded = std::filesystem::path(percentDecode(encoded));

  if (!decoded.is_absolute()) {
    throw CodedError("ERR_FILE_SYSTEM_PATH_TRAVERSAL", "The file URI must contain an absolute path.");
  }
  return decoded.lexically_normal();
}

void movePath(const std::filesystem::path &source, const std::filesystem::path &target) {
  try {
    std::filesystem::rename(source, target);
    return;
  } catch (const std::filesystem::filesystem_error &error) {
    if (error.code() != std::errc::cross_device_link) {
      throw;
    }
  }

  try {
    if (std::filesystem::is_directory(source)) {
      std::filesystem::copy(source, target, std::filesystem::copy_options::recursive);
    } else {
      std::filesystem::copy_file(source, target);
    }
  } catch (...) {
    std::error_code ignored;
    std::filesystem::remove_all(target, ignored);
    throw;
  }

  // Keep the completed target if source cleanup fails. This leaves a
  // recoverable duplicate instead of risking deletion of both copies.
  std::filesystem::remove_all(source);
}

std::string rawPathFromUri(const std::string &uri, bool allowSchemeLess = false) {
  std::string value;
  if (uri.starts_with("asset://")) {
    value = uri.substr(std::string_view("asset://").size());
  } else if (uri.starts_with("rawfile://")) {
    value = uri.substr(std::string_view("rawfile://").size());
  } else if (allowSchemeLess && uri.find(':') == std::string::npos) {
    value = uri;
  } else {
    throw CodedError("ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME", "Expected an asset:// or rawfile:// URI.");
  }

  const auto suffix = value.find_first_of("?#");
  if (suffix != std::string::npos) {
    value.resize(suffix);
  }
  value = percentDecode(value);

  while (value.starts_with('/')) {
    value.erase(value.begin());
  }
  std::replace(value.begin(), value.end(), '\\', '/');
  const auto path = std::filesystem::path(value).lexically_normal();

  if (path.is_absolute() || hasTraversalSegment(path)) {
    throw CodedError("ERR_FILE_SYSTEM_PATH_TRAVERSAL", "Raw resource paths must stay inside the application bundle.");
  }
  if (path == ".") {
    return {};
  }
  return path.generic_string();
}

std::string toAssetUri(const std::string &rawPath, bool directory = false) {
  auto uri = std::string("asset:///") + percentEncodePath(rawPath);
  if (directory && !uri.ends_with('/')) {
    uri.push_back('/');
  }
  return uri;
}

std::string replaceInvalidUtf8(const std::string &value) {
  constexpr std::string_view replacement = "\xEF\xBF\xBD";
  std::string result;
  result.reserve(value.size());
  size_t index = 0;
  const auto continuation = [](unsigned char character) {
    return character >= 0x80 && character <= 0xBF;
  };

  while (index < value.size()) {
    const auto first = static_cast<unsigned char>(value[index]);
    size_t length = 0;
    bool valid = false;
    if (first <= 0x7F) {
      length = 1;
      valid = true;
    } else if (first >= 0xC2 && first <= 0xDF && index + 1 < value.size()) {
      length = 2;
      valid = continuation(static_cast<unsigned char>(value[index + 1]));
    } else if (first >= 0xE0 && first <= 0xEF && index + 2 < value.size()) {
      const auto second = static_cast<unsigned char>(value[index + 1]);
      const auto third = static_cast<unsigned char>(value[index + 2]);
      length = 3;
      valid = continuation(third)
           && ((first == 0xE0 && second >= 0xA0 && second <= 0xBF)
               || (first == 0xED && second >= 0x80 && second <= 0x9F)
               || (first != 0xE0 && first != 0xED && continuation(second)));
    } else if (first >= 0xF0 && first <= 0xF4 && index + 3 < value.size()) {
      const auto second = static_cast<unsigned char>(value[index + 1]);
      length = 4;
      valid = continuation(static_cast<unsigned char>(value[index + 2]))
           && continuation(static_cast<unsigned char>(value[index + 3]))
           && ((first == 0xF0 && second >= 0x90 && second <= 0xBF)
               || (first == 0xF4 && second >= 0x80 && second <= 0x8F)
               || (first != 0xF0 && first != 0xF4 && continuation(second)));
    }
    if (!valid) {
      result.append(replacement);
      ++index;
      continue;
    }
    result.append(value, index, length);
    index += length;
  }

  return result;
}

std::string readTextFile(const std::filesystem::path &path) {
  requireFileType(path);

  std::ifstream input(path, std::ios::binary);
  if (!input) {
    throw CodedError("ERR_FILE_SYSTEM_CANNOT_READ", "Cannot read '" + path.string() + "'.");
  }
  const auto bytes = std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());

  if (input.bad()) {
    throw CodedError("ERR_FILE_SYSTEM_CANNOT_READ", "File read failed before reaching the end.");
  }
  return replaceInvalidUtf8(bytes);
}

std::vector<uint8_t> readBytesFile(const std::filesystem::path &path) {
  requireFileType(path);

  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) {
    throw CodedError("ERR_FILE_SYSTEM_CANNOT_READ", "Cannot read '" + path.string() + "'.");
  }
  const auto length = input.tellg();
  if (length < 0) {
    throw CodedError("ERR_FILE_SYSTEM_CANNOT_READ", "Cannot determine file size.");
  }

  std::vector<uint8_t> result(static_cast<size_t>(length));
  input.seekg(0);
  if (!result.empty()) {
    input.read(reinterpret_cast<char *>(result.data()), static_cast<std::streamsize>(result.size()));
  }
  if (!input && !result.empty()) {
    throw CodedError("ERR_FILE_SYSTEM_CANNOT_READ", "File read was incomplete.");
  }
  return result;
}

void writeBytesFile(const std::filesystem::path &path, const std::vector<uint8_t> &bytes, bool append) {
  requireFileType(path);

  std::ofstream output(path, std::ios::binary | (append ? std::ios::app : std::ios::trunc));
  if (!output) {
    throw CodedError("ERR_FILE_SYSTEM_CANNOT_WRITE", "Cannot write '" + path.string() + "'.");
  }

  if (!bytes.empty()) {
    output.write(reinterpret_cast<const char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  }
  if (!output) {
    throw CodedError("ERR_FILE_SYSTEM_CANNOT_WRITE", "File write was incomplete.");
  }
}

const char kBase64Alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

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

std::vector<uint8_t> base64Decode(const std::string &value) {
  std::array<int, 256> lookup{};
  lookup.fill(-1);
  for (int index = 0; index < 64; ++index) {
    lookup[static_cast<unsigned char>(kBase64Alphabet[index])] = index;
  }

  std::vector<uint8_t> result;
  uint32_t accumulator = 0;
  int bits = 0;
  for (unsigned char character : value) {
    if (character == '=') {
      break;
    }
    if (character == ' ' || character == '\n' || character == '\r' || character == '\t') {
      continue;
    }
    const int decoded = lookup[character];
    // Match Android's Base64.DEFAULT and iOS's ignoreUnknownCharacters.
    // This intentionally does not special-case data-URI prefixes: upstream
    // accepts unknown separators, but does not strip alphabetic prefix bytes.
    if (decoded < 0) {
      continue;
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

std::string md5File(const std::filesystem::path &path) {
  requireFileType(path);
  OH_CryptoDigest *digest = nullptr;
  if (OH_CryptoDigest_Create("MD5", &digest) != CRYPTO_SUCCESS || !digest) {
    throw CodedError("ERR_FILE_SYSTEM_MD5", "Unable to create the MD5 digest.");
  }

  struct Guard {
    OH_CryptoDigest *value;

    ~Guard() {
      if (value) {
        OH_DigestCrypto_Destroy(value);
      }
    }
  } guard{digest};

  std::ifstream input(path, std::ios::binary);
  if (!input) {
    throw CodedError("ERR_FILE_SYSTEM_MD5", "Cannot open the file for MD5.");
  }
  std::array<uint8_t, 64 * 1024> buffer{};
  while (input) {
    input.read(reinterpret_cast<char *>(buffer.data()), static_cast<std::streamsize>(buffer.size()));
    const auto count = input.gcount();
    if (count <= 0) {
      break;
    }
    Crypto_DataBlob blob{buffer.data(), static_cast<size_t>(count)};
    if (OH_CryptoDigest_Update(digest, &blob) != CRYPTO_SUCCESS) {
      throw CodedError("ERR_FILE_SYSTEM_MD5", "Unable to update the MD5 digest.");
    }
  }
  if (input.bad()) {
    throw CodedError("ERR_FILE_SYSTEM_MD5", "The file could not be read completely for MD5.");
  }

  std::array<uint8_t, 16> output{};
  Crypto_DataBlob result{output.data(), output.size()};
  if (OH_CryptoDigest_Final(digest, &result) != CRYPTO_SUCCESS) {
    throw CodedError("ERR_FILE_SYSTEM_MD5", "Unable to finalize the MD5 digest.");
  }

  std::ostringstream encoded;
  encoded << std::hex << std::setfill('0');
  for (size_t index = 0; index < result.len; ++index) {
    encoded << std::setw(2) << static_cast<int>(result.data[index]);
  }
  return encoded.str();
}

std::string md5Bytes(const std::vector<uint8_t> &bytes) {
  OH_CryptoDigest *digest = nullptr;
  if (OH_CryptoDigest_Create("MD5", &digest) != CRYPTO_SUCCESS || !digest) {
    throw CodedError("ERR_FILE_SYSTEM_MD5", "Unable to create the MD5 digest.");
  }

  struct Guard {
    OH_CryptoDigest *value;

    ~Guard() {
      if (value) {
        OH_DigestCrypto_Destroy(value);
      }
    }
  } guard{digest};

  if (!bytes.empty()) {
    Crypto_DataBlob input{const_cast<uint8_t *>(bytes.data()), bytes.size()};
    if (OH_CryptoDigest_Update(digest, &input) != CRYPTO_SUCCESS) {
      throw CodedError("ERR_FILE_SYSTEM_MD5", "Unable to update the MD5 digest.");
    }
  }

  std::array<uint8_t, 16> output{};
  Crypto_DataBlob result{output.data(), output.size()};
  if (OH_CryptoDigest_Final(digest, &result) != CRYPTO_SUCCESS) {
    throw CodedError("ERR_FILE_SYSTEM_MD5", "Unable to finalize the MD5 digest.");
  }

  std::ostringstream encoded;
  encoded << std::hex << std::setfill('0');
  for (size_t index = 0; index < result.len; ++index) {
    encoded << std::setw(2) << static_cast<int>(result.data[index]);
  }
  return encoded.str();
}

RawFileDescriptor parseRawFileDescriptor(jsi::Runtime &runtime, const jsi::Value &value) {
  if (!value.isObject()) {
    throw CodedError("ERR_FILE_SYSTEM_RAW_RESOURCE", "Harmony returned an invalid raw resource descriptor.");
  }
  auto object = value.getObject(runtime);
  auto fdValue = object.getProperty(runtime, "fd");
  auto offsetValue = object.getProperty(runtime, "offset");
  auto lengthValue = object.getProperty(runtime, "length");

  if (!fdValue.isNumber() || !offsetValue.isNumber() || !lengthValue.isNumber()) {
    throw CodedError("ERR_FILE_SYSTEM_RAW_RESOURCE", "Harmony returned a non-numeric raw resource descriptor.");
  }
  const auto fd = fdValue.getNumber();
  const auto offset = offsetValue.getNumber();
  const auto length = lengthValue.getNumber();

  if (!std::isfinite(fd) || !std::isfinite(offset) || !std::isfinite(length) || std::trunc(fd) != fd || std::trunc(offset) != offset || std::trunc(length) != length || fd < 0 || fd > std::numeric_limits<int>::max() || offset < 0 || offset > static_cast<double>(std::numeric_limits<off_t>::max()) || length < 0 || length > static_cast<double>(std::numeric_limits<size_t>::max())) {
    throw CodedError("ERR_FILE_SYSTEM_RAW_RESOURCE", "Harmony returned an invalid raw resource descriptor range.");
  }
  return {
      static_cast<int>(fd),
      static_cast<off_t>(offset),
      static_cast<size_t>(length),
  };
}

double milliseconds(const std::filesystem::file_time_type &value) {
  const auto system = std::chrono::time_point_cast<std::chrono::milliseconds>(
      value - std::filesystem::file_time_type::clock::now() + std::chrono::system_clock::now());
  return static_cast<double>(system.time_since_epoch().count());
}

std::optional<double> creationTime(const std::filesystem::path &path) {
  uv_fs_t request{};
  const auto result = uv_fs_stat(nullptr, &request, path.c_str(), nullptr);
  if (result < 0) {
    uv_fs_req_cleanup(&request);
    return std::nullopt;
  }
  const auto birth = request.statbuf.st_birthtim;
  uv_fs_req_cleanup(&request);
  if (birth.tv_sec <= 0) {
    return std::nullopt;
  }
  return static_cast<double>(birth.tv_sec) * 1000.0 + static_cast<double>(birth.tv_nsec) / 1000000.0;
}

bool dynamicBool(const folly::dynamic &value, const char *key, bool fallback = false) {
  if (!value.isObject() || !value.count(key) || !value.at(key).isBool()) {
    return fallback;
  }
  return value.at(key).asBool();
}

std::string dynamicString(const folly::dynamic &value, const char *key, std::string fallback = {}) {
  if (!value.isObject() || !value.count(key) || !value.at(key).isString()) {
    return fallback;
  }
  return value.at(key).asString();
}

int64_t parseResumeOffset(const std::string &value) {
  try {
    size_t parsed = 0;
    const auto result = std::stoll(value, &parsed);
    return parsed == value.size() && result >= 0 ? result : 0;
  } catch (...) {
    return 0;
  }
}

folly::dynamic valueToDynamic(Invocation &invocation, size_t index, folly::dynamic fallback = folly::dynamic::object()) {
  if (index >= invocation.argumentCount() || invocation.argument(index).isNull() || invocation.argument(index).isUndefined()) {
    return fallback;
  }
  return jsi::dynamicFromValue(invocation.runtime(), invocation.argument(index));
}

std::filesystem::path prepareSandboxDirectory(std::filesystem::path path) {
  path = path.lexically_normal();

  std::error_code createError;
  std::filesystem::create_directories(path, createError);
  if (createError) {
    std::error_code statusError;
    if (!std::filesystem::is_directory(path, statusError)) {
      throw CodedError(
          "ERR_FILE_SYSTEM_CANNOT_CREATE",
          "Cannot prepare file-system sandbox directory '" + path.string() + "': " + createError.message());
    }
  }

  std::error_code canonicalError;
  auto canonical = std::filesystem::weakly_canonical(path, canonicalError);
  if (canonicalError) {
    throw CodedError(
        "ERR_FILE_SYSTEM_INVALID_PATH",
        "Cannot resolve file-system sandbox directory '" + path.string() + "': " + canonicalError.message());
  }
  return canonical;
}

class FileSystemState final {
public:
  FileSystemState(
      std::filesystem::path document,
      std::filesystem::path cache,
      std::shared_ptr<RuntimeContext> context)
      : context_(std::move(context)),
        document_(prepareSandboxDirectory(std::move(document))),
        cache_(prepareSandboxDirectory(std::move(cache))) {}

  const std::filesystem::path &document() const {
    return document_;
  }

  const std::filesystem::path &cache() const {
    return cache_;
  }

  void grant(const std::string &uri, bool directory) {
    const auto lexical = decodeFileUri(uri).lexically_normal();
    std::error_code error;
    const auto canonical = std::filesystem::weakly_canonical(lexical, error);

    if (error) {
      throw CodedError("ERR_FILE_SYSTEM_INVALID_PICKED_URI", "Cannot resolve the selected URI: " + error.message());
    }
    std::scoped_lock lock(capabilitiesMutex_);
    const auto duplicate = std::find_if(capabilities_.begin(), capabilities_.end(), [&](const Capability &capability) {
      return capability.lexical == lexical && capability.canonical == canonical && capability.directory == directory;
    });

    if (duplicate == capabilities_.end()) {
      capabilities_.push_back(Capability{lexical, canonical, directory});
    }
  }

  std::filesystem::path resolve(const std::string &uri, bool mayNotExist = true) const {
    const auto decoded = decodeFileUri(uri);
    const auto lexical = decoded.lexically_normal();

    std::optional<std::filesystem::path> canonicalRoot;
    bool exactCapability = false;
    if (isInside(document_, lexical)) {
      canonicalRoot = document_;
    }
    if (isInside(cache_, lexical)) {
      canonicalRoot = cache_;
    }
    std::error_code error;
    const auto canonical = mayNotExist
                             ? std::filesystem::weakly_canonical(decoded, error)
                             : std::filesystem::canonical(decoded, error);

    if (error) {
      throw CodedError("ERR_FILE_SYSTEM_INVALID_PATH", "Cannot resolve '" + uri + "': " + error.message());
    }
    {
      std::scoped_lock lock(capabilitiesMutex_);
      for (const auto &capability : capabilities_) {
        const bool matchesLexical = capability.directory
                                      ? isInside(capability.lexical, lexical)
                                      : capability.lexical == lexical;
        const bool matchesCanonical = capability.directory
                                        ? isInside(capability.canonical, canonical)
                                        : capability.canonical == canonical;
        if (matchesLexical || matchesCanonical) {
          canonicalRoot = capability.canonical;
          exactCapability = !capability.directory;
          break;
        }
      }
    }

    if (!canonicalRoot) {
      throw CodedError("ERR_FILE_SYSTEM_PATH_OUTSIDE_SANDBOX", "Path is outside the application sandbox or an active picker grant.");
    }
    const bool canonicalAllowed = exactCapability ? canonical == *canonicalRoot : isInside(*canonicalRoot, canonical);

    if (!canonicalAllowed) {
      throw CodedError("ERR_FILE_SYSTEM_PATH_OUTSIDE_SANDBOX", "Resolved path escaped its application or picker root.");
    }
    return canonical;
  }

  std::optional<std::filesystem::path> resolveForProbe(
      const std::string &uri,
      bool mayNotExist = true) const {
    try {
      return resolve(uri, mayNotExist);
    } catch (const CodedError &error) {
      if (error.code() == "ERR_FILE_SYSTEM_PATH_OUTSIDE_SANDBOX") {
        return std::nullopt;
      }
      throw;
    }
  }

  uint64_t totalSpace() const {
    const auto value = space();
    return value.f_blocks * value.f_frsize;
  }

  uint64_t freeSpace() const {
    const auto value = space();
    return value.f_bavail * value.f_frsize;
  }

  std::string platformString(const std::string &method, const std::string &argument) const {
    auto context = context_.lock();
    if (!context || !context->isAlive()) {
      throw CodedError("ERR_FILE_SYSTEM_CONTEXT_LOST", "The Expo runtime is no longer available.");
    }

    auto value = context->invokePlatformServiceSync(kService, method, folly::dynamic::array(argument));
    if (!value.isString()) {
      throw CodedError("ERR_FILE_SYSTEM_PLATFORM_VALUE", "Harmony returned an invalid file-system string value.");
    }
    return value.getString(context->runtime()).utf8(context->runtime());
  }

  std::string contentUri(const std::filesystem::path &path) const {
    // Harmony has no Android FileProvider-equivalent content:// contract.
    // Keep this URI consumable by File and legacy APIs instead of returning a
    // virtual authority that this carrier cannot resolve back to a path.
    return toFileUri(path);
  }

  std::string bundledContentUri(
      const std::string &rawPath,
      const std::vector<uint8_t> &bytes) const {
    std::scoped_lock lock(sharedAssetsMutex_);
    const auto directory = cache_ / "expo_shared_assets";
    std::filesystem::create_directories(directory);
    auto leaf = std::filesystem::path(rawPath).filename().string();
    validateChildName(leaf);

    const auto target = directory / (md5Bytes(bytes) + "-" + leaf);
    if (!std::filesystem::is_regular_file(target)) {
      const auto temporary = target.string() + ".tmp";

      try {
        writeBytesFile(temporary, bytes, false);
        std::filesystem::rename(temporary, target);
      } catch (...) {
        std::error_code ignored;
        std::filesystem::remove(temporary, ignored);
        throw;
      }
    }

    return contentUri(target);
  }

  std::string mimeType(const std::filesystem::path &path) const {
    return platformString("mimeType", path.string());
  }

  std::vector<std::string> rawList(const std::string &path) const {
    auto context = context_.lock();
    if (!context || !context->isAlive()) {
      throw CodedError("ERR_FILE_SYSTEM_CONTEXT_LOST", "The Expo runtime is no longer available.");
    }

    auto value = context->callPlatformSync("getRawFileList", {path});
    auto dynamic = jsi::dynamicFromValue(context->runtime(), value);
    if (!dynamic.isArray()) {
      throw CodedError("ERR_FILE_SYSTEM_RAW_RESOURCE", "Harmony returned an invalid raw resource listing.");
    }
    std::vector<std::string> result;
    result.reserve(dynamic.size());

    for (const auto &item : dynamic) {
      if (!item.isString()) {
        throw CodedError("ERR_FILE_SYSTEM_RAW_RESOURCE", "Harmony returned an invalid raw resource name.");
      }
      result.push_back(item.asString());
    }
    return result;
  }

  BytesTask prepareRawBytesTask(const std::string &path) const {
    auto context = context_.lock();
    if (!context || !context->isAlive()) {
      throw CodedError("ERR_FILE_SYSTEM_CONTEXT_LOST", "The Expo runtime is no longer available.");
    }
    context->assertRuntimeThread();

    const auto descriptor = openRawDescriptor(context, path);
    const int duplicateFd = dup(descriptor.fd);
    const int duplicateError = duplicateFd < 0 ? errno : 0;

    try {
      // ResourceManager owns the original descriptor. Duplicate it while on
      // the runtime thread, then immediately balance the platform open call.
      // The duplicate is safe to pread and close on our native queue.
      closeRawDescriptor(context, path, true);
    } catch (...) {
      if (duplicateFd >= 0) {
        close(duplicateFd);
      }
      throw;
    }

    if (duplicateFd < 0) {
      throw CodedError(
          "ERR_FILE_SYSTEM_RAW_RESOURCE",
          "Unable to duplicate the bundled resource descriptor: " + std::string(std::strerror(duplicateError)));
    }

    ScopedFileDescriptor guard(duplicateFd);
    auto file = std::make_shared<DuplicatedRawFileDescriptor>(
        duplicateFd, descriptor.offset, descriptor.length);
    guard.release();

    return [file = std::move(file)]() {
      std::vector<uint8_t> result(file->length);
      size_t read = 0;
      while (read < result.size()) {
        const auto count = pread(
            file->fd,
            result.data() + read,
            result.size() - read,
            file->offset + static_cast<off_t>(read));
        if (count < 0 && errno == EINTR) {
          continue;
        }
        if (count <= 0) {
          throw CodedError("ERR_FILE_SYSTEM_RAW_RESOURCE", "Unable to read the complete bundled resource.");
        }
        read += static_cast<size_t>(count);
      }

      return result;
    };
  }

  std::function<void()> prepareRawCopyTask(
      const std::string &path,
      std::filesystem::path target) const {
    auto context = context_.lock();
    if (!context || !context->isAlive()) {
      throw CodedError("ERR_FILE_SYSTEM_CONTEXT_LOST", "The Expo runtime is no longer available.");
    }
    context->assertRuntimeThread();

    const auto descriptor = openRawDescriptor(context, path);
    const int duplicateFd = dup(descriptor.fd);
    const int duplicateError = duplicateFd < 0 ? errno : 0;

    try {
      closeRawDescriptor(context, path, true);
    } catch (...) {
      if (duplicateFd >= 0) {
        close(duplicateFd);
      }
      throw;
    }

    if (duplicateFd < 0) {
      throw CodedError(
          "ERR_FILE_SYSTEM_RAW_RESOURCE",
          "Unable to duplicate the bundled resource descriptor: " + std::string(std::strerror(duplicateError)));
    }

    ScopedFileDescriptor guard(duplicateFd);
    auto file = std::make_shared<DuplicatedRawFileDescriptor>(
        duplicateFd, descriptor.offset, descriptor.length);
    guard.release();

    return [file = std::move(file), target = std::move(target)]() {
      std::ofstream output(target, std::ios::binary | std::ios::trunc);
      if (!output) {
        throw CodedError("ERR_FILE_SYSTEM_CANNOT_WRITE", "Cannot write '" + target.string() + "'.");
      }
      std::array<uint8_t, 64 * 1024> buffer{};
      size_t copied = 0;
      while (copied < file->length) {
        const auto requested = std::min(buffer.size(), file->length - copied);
        const auto count = pread(
            file->fd,
            buffer.data(),
            requested,
            file->offset + static_cast<off_t>(copied));
        if (count < 0 && errno == EINTR) {
          continue;
        }
        if (count <= 0) {
          throw CodedError("ERR_FILE_SYSTEM_RAW_RESOURCE", "Unable to read the complete bundled resource.");
        }
        output.write(
            reinterpret_cast<const char *>(buffer.data()),
            static_cast<std::streamsize>(count));
        if (!output) {
          throw CodedError("ERR_FILE_SYSTEM_CANNOT_WRITE", "File write was incomplete.");
        }
        copied += static_cast<size_t>(count);
      }
    };
  }

  std::vector<uint8_t> rawBytes(const std::string &path) const {
    auto context = context_.lock();
    if (!context || !context->isAlive()) {
      throw CodedError("ERR_FILE_SYSTEM_CONTEXT_LOST", "The Expo runtime is no longer available.");
    }

    const auto descriptor = openRawDescriptor(context, path);
    try {
      std::vector<uint8_t> result(descriptor.length);
      size_t read = 0;
      while (read < result.size()) {
        const auto count = pread(
            descriptor.fd,
            result.data() + read,
            result.size() - read,
            descriptor.offset + static_cast<off_t>(read));
        if (count < 0 && errno == EINTR) {
          continue;
        }
        if (count <= 0) {
          throw CodedError("ERR_FILE_SYSTEM_RAW_RESOURCE", "Unable to read the complete bundled resource.");
        }
        read += static_cast<size_t>(count);
      }

      closeRawDescriptor(context, path, true);
      return result;
    } catch (...) {
      closeRawDescriptor(context, path, false);
      throw;
    }
  }

  size_t rawSize(const std::string &path) const {
    auto context = context_.lock();
    if (!context || !context->isAlive()) {
      throw CodedError("ERR_FILE_SYSTEM_CONTEXT_LOST", "The Expo runtime is no longer available.");
    }

    const auto descriptor = openRawDescriptor(context, path);
    closeRawDescriptor(context, path, true);
    return descriptor.length;
  }

  bool rawIsDirectory(const std::string &path) const {
    if (rawIsFile(path)) {
      return false;
    }
    try {
      static_cast<void>(rawList(path));
      return true;
    } catch (...) {
      return false;
    }
  }

  bool rawIsFile(const std::string &path) const {
    if (path.empty()) {
      return false;
    }
    try {
      static_cast<void>(rawSize(path));
      return true;
    } catch (...) {
      return false;
    }
  }

private:
  RawFileDescriptor openRawDescriptor(
      const std::shared_ptr<RuntimeContext> &context,
      const std::string &path) const {
    auto value = context->callPlatformSync("getRawFileDescriptor", {path});
    try {
      return parseRawFileDescriptor(context->runtime(), value);
    } catch (...) {
      closeRawDescriptor(context, path, false);
      throw;
    }
  }

  void closeRawDescriptor(
      const std::shared_ptr<RuntimeContext> &context,
      const std::string &path,
      bool propagate) const {
    try {
      context->callPlatformSync("closeRawFileDescriptor", {path});
    } catch (...) {
      if (propagate) {
        throw;
      }
    }
  }

  struct Capability {
    std::filesystem::path lexical;
    std::filesystem::path canonical;
    bool directory;
  };

  struct statvfs space() const {
    struct statvfs value{};
    if (statvfs(document_.c_str(), &value) != 0) {
      throw CodedError("ERR_FILE_SYSTEM_DISK_SPACE", "Unable to query disk space.");
    }
    return value;
  }

  std::weak_ptr<RuntimeContext> context_;
  std::filesystem::path document_;
  std::filesystem::path cache_;
  mutable std::mutex capabilitiesMutex_;
  mutable std::mutex sharedAssetsMutex_;
  std::vector<Capability> capabilities_;
};

class DirectoryObject;

class FileObject final : public NativeSharedObject {
public:
  FileObject(std::shared_ptr<FileSystemState> state, std::string uri)
      : state_(std::move(state)), bundle_(uri.starts_with("asset://") || uri.starts_with("rawfile://")) {
    if (bundle_) {
      rawPath_ = rawPathFromUri(uri);
    } else {
      path_ = decodeFileUri(uri).lexically_normal();
    }
  }

  std::filesystem::path path() const {
    if (bundle_) {
      throw CodedError("ERR_FILE_SYSTEM_READ_ONLY_BUNDLE", "Bundle files are read-only.");
    }
    return state_->resolve(toFileUri(path_));
  }

  std::string uri() const {
    return bundle_ ? toAssetUri(rawPath_) : toFileUri(path_);
  }

  std::optional<std::filesystem::path> probePath() const {
    if (bundle_) {
      return std::nullopt;
    }
    return state_->resolveForProbe(toFileUri(path_));
  }

  void setPath(std::filesystem::path path) {
    bundle_ = false;
    rawPath_.clear();
    rawBytes_.reset();
    path_ = state_->resolve(toFileUri(path));
  }

  bool isBundle() const {
    return bundle_;
  }

  bool rawExists() const {
    if (!bundle_) {
      return false;
    }
    try {
      static_cast<void>(state_->rawSize(rawPath_));
      return true;
    } catch (...) {
      return false;
    }
  }

  size_t rawSize() const {
    if (!bundle_) {
      throw CodedError("ERR_FILE_SYSTEM_CANNOT_READ", "The file is not a bundled resource.");
    }
    return state_->rawSize(rawPath_);
  }

  BytesTask prepareBytesTask() const {
    if (bundle_) {
      return state_->prepareRawBytesTask(rawPath_);
    }
    auto resolvedPath = path();
    return [resolvedPath = std::move(resolvedPath)]() {
      return readBytesFile(resolvedPath);
    };
  }

  const std::vector<uint8_t> &rawBytes() const {
    if (!bundle_) {
      throw CodedError("ERR_FILE_SYSTEM_CANNOT_READ", "The file is not a bundled resource.");
    }
    if (!rawBytes_) {
      rawBytes_ = state_->rawBytes(rawPath_);
    }
    return *rawBytes_;
  }

  const std::string &rawPath() const {
    return rawPath_;
  }

  std::shared_ptr<FileSystemState> state() const {
    return state_;
  }

private:
  std::shared_ptr<FileSystemState> state_;
  bool bundle_{false};
  std::filesystem::path path_;
  std::string rawPath_;
  mutable std::optional<std::vector<uint8_t>> rawBytes_;
};

class DirectoryObject final : public NativeSharedObject {
public:
  DirectoryObject(std::shared_ptr<FileSystemState> state, std::string uri)
      : state_(std::move(state)),
        bundle_(uri.starts_with("asset://") || uri.starts_with("rawfile://")),
        path_(bundle_ ? std::filesystem::path() : decodeFileUri(uri).lexically_normal()),
        rawPath_(bundle_ ? rawPathFromUri(uri) : std::string()) {}

  std::filesystem::path path() const {
    if (bundle_) {
      throw CodedError("ERR_FILE_SYSTEM_READ_ONLY_BUNDLE", "Bundle directories are read-only.");
    }
    return state_->resolve(toFileUri(path_, true));
  }

  std::string uri() const {
    return bundle_ ? toAssetUri(rawPath_, true) : toFileUri(path_, true);
  }

  std::optional<std::filesystem::path> probePath() const {
    if (bundle_) {
      return std::nullopt;
    }
    return state_->resolveForProbe(toFileUri(path_, true));
  }

  void setPath(std::filesystem::path path) {
    bundle_ = false;
    rawPath_.clear();
    path_ = state_->resolve(toFileUri(path, true));
  }

  bool isBundle() const {
    return bundle_;
  }

  const std::string &rawPath() const {
    return rawPath_;
  }

  std::vector<std::string> rawList() const {
    return state_->rawList(rawPath_);
  }

  std::shared_ptr<FileSystemState> state() const {
    return state_;
  }

private:
  std::shared_ptr<FileSystemState> state_;
  bool bundle_{false};
  std::filesystem::path path_;
  std::string rawPath_;
};

std::string joinRawPath(const std::string &directory, const std::string &name) {
  validateChildName(name);
  return directory.empty() ? name : directory + "/" + name;
}

uint64_t rawDirectorySize(const std::shared_ptr<FileSystemState> &state, const std::string &path) {
  uint64_t size = 0;
  for (const auto &name : state->rawList(path)) {
    const auto child = joinRawPath(path, name);
    if (state->rawIsDirectory(child)) {
      size += rawDirectorySize(state, child);
    } else {
      size += state->rawSize(child);
    }
  }

  return size;
}

folly::dynamic rawFileInfo(const FileObject &file, bool includeMd5) {
  const bool exists = file.rawExists();
  folly::dynamic result = folly::dynamic::object("exists", exists)("uri", file.uri());

  if (!exists) {
    return result;
  }
  result["size"] = static_cast<double>(file.rawSize());
  result["modificationTime"] = nullptr;
  result["creationTime"] = nullptr;

  if (includeMd5) {
    result["md5"] = md5Bytes(file.rawBytes());
  }
  return result;
}

folly::dynamic rawDirectoryInfo(const DirectoryObject &directory) {
  bool exists = false;
  std::vector<std::string> names;
  try {
    names = directory.rawList();
    exists = true;
  } catch (...) {
    exists = false;
  }
  folly::dynamic result = folly::dynamic::object("exists", exists)("uri", directory.uri());

  if (!exists) {
    return result;
  }
  auto files = folly::dynamic::array();
  for (const auto &name : names) {
    files.push_back(name);
  }

  result["files"] = std::move(files);
  result["size"] = static_cast<double>(rawDirectorySize(directory.state(), directory.rawPath()));
  result["modificationTime"] = nullptr;
  result["creationTime"] = nullptr;

  return result;
}

std::filesystem::path fileDestinationPath(
    const std::filesystem::path &source,
    const std::shared_ptr<NativeSharedObject> &destination) {
  if (auto directory = std::dynamic_pointer_cast<DirectoryObject>(destination)) {
    const auto path = directory->path();
    requireDirectoryType(path);
    if (!std::filesystem::is_directory(path)) {
      throw CodedError("ERR_FILE_SYSTEM_DESTINATION_MISSING", "Destination directory does not exist.");
    }

    return path / source.filename();
  }
  if (auto file = std::dynamic_pointer_cast<FileObject>(destination)) {
    const auto path = file->path();
    requireFileType(path);
    if (!std::filesystem::is_directory(path.parent_path())) {
      throw CodedError("ERR_FILE_SYSTEM_DESTINATION_MISSING", "Destination parent directory does not exist.");
    }

    return path;
  }
  throw CodedError("ERR_FILE_SYSTEM_DESTINATION", "Destination must be a File or Directory.");
}

std::filesystem::path directoryDestinationPath(
    const std::filesystem::path &source,
    const std::shared_ptr<NativeSharedObject> &destination) {
  auto directory = std::dynamic_pointer_cast<DirectoryObject>(destination);
  if (!directory) {
    throw CodedError("ERR_FILE_SYSTEM_DESTINATION", "A directory cannot be copied or moved to a File.");
  }
  const auto path = directory->path();
  requireDirectoryType(path);

  if (std::filesystem::is_directory(path)) {
    return path / source.filename();
  }
  if (!std::filesystem::is_directory(path.parent_path())) {
    throw CodedError("ERR_FILE_SYSTEM_DESTINATION_MISSING", "Destination parent directory does not exist.");
  }
  return path;
}

class FileHandleObject final : public NativeSharedObject {
public:
  explicit FileHandleObject(const std::shared_ptr<FileObject> &file)
      : file_(file), stream_(file->path(), std::ios::binary | std::ios::in | std::ios::out) {
    if (!stream_) {
      throw CodedError("ERR_FILE_SYSTEM_CANNOT_OPEN", "Cannot open '" + file->path().string() + "'.");
    }
  }

  std::vector<uint8_t> read(uint64_t count) {
    std::scoped_lock lock(mutex_);
    requireOpen();

    const auto size = streamSize("ERR_FILE_SYSTEM_CANNOT_READ");
    const auto allocation = detail::readAllocationSize(count, offset_, size);
    if (allocation == 0) {
      return {};
    }
    stream_.seekg(static_cast<std::streamoff>(offset_));
    if (!stream_) {
      stream_.clear();
      throw CodedError(
          "ERR_FILE_SYSTEM_CANNOT_READ", "File handle seek failed.");
    }

    std::vector<uint8_t> bytes(allocation);
    stream_.read(
        reinterpret_cast<char *>(bytes.data()),
        static_cast<std::streamsize>(allocation));
    bytes.resize(static_cast<size_t>(stream_.gcount()));
    stream_.clear();
    offset_ += bytes.size();

    return bytes;
  }

  void write(const std::vector<uint8_t> &bytes) {
    std::scoped_lock lock(mutex_);
    requireOpen();
    stream_.clear();
    stream_.seekp(static_cast<std::streamoff>(offset_));
    if (!stream_) {
      stream_.clear();
      throw CodedError("ERR_FILE_SYSTEM_CANNOT_WRITE", "File handle seek failed.");
    }

    if (!bytes.empty()) {
      stream_.write(reinterpret_cast<const char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    }
    stream_.flush();
    if (!stream_) {
      throw CodedError("ERR_FILE_SYSTEM_CANNOT_WRITE", "File handle write failed.");
    }
    offset_ += bytes.size();
  }

  void close() {
    std::scoped_lock lock(mutex_);
    if (closed_) {
      return;
    }
    stream_.close();
    closed_ = true;
  }

  std::optional<double> offset() const {
    std::scoped_lock lock(mutex_);
    return closed_ ? std::nullopt : std::optional<double>(static_cast<double>(offset_));
  }

  void setOffset(double value) {
    std::scoped_lock lock(mutex_);
    requireOpen();
    if (!detail::isValidFileHandleInteger(value)) {
      throw CodedError(
          "ERR_FILE_SYSTEM_INVALID_OFFSET",
          "File handle offset must be a finite, non-negative safe integer.");
    }
    offset_ = detail::fileHandleInteger(value);
  }

  std::optional<double> size() {
    std::scoped_lock lock(mutex_);
    if (closed_) {
      return std::nullopt;
    }
    return static_cast<double>(streamSize("ERR_FILE_SYSTEM_CANNOT_READ"));
  }

  void deallocate() override {
    close();
  }

private:
  uint64_t streamSize(const char *errorCode) {
    stream_.clear();
    stream_.seekg(0, std::ios::end);
    const auto end = stream_.tellg();
    stream_.clear();
    if (end < 0) {
      throw CodedError(errorCode, "Cannot determine the file handle length.");
    }
    return static_cast<uint64_t>(end);
  }

  void requireOpen() const {
    if (closed_) {
      throw CodedError("ERR_FILE_SYSTEM_HANDLE_CLOSED", "File handle is closed.");
    }
  }

  std::shared_ptr<FileObject> file_;
  mutable std::mutex mutex_;
  std::fstream stream_;
  uint64_t offset_{0};
  bool closed_{false};
};

folly::dynamic fileInfo(const std::filesystem::path &path, bool includeMd5 = false) {
  std::error_code error;
  const bool exists = std::filesystem::exists(path, error) && !error;
  folly::dynamic result = folly::dynamic::object("exists", exists)("uri", toFileUri(path));

  if (!exists) {
    return result;
  }
  requireFileType(path);

  result["size"] = static_cast<double>(std::filesystem::file_size(path));
  result["modificationTime"] = milliseconds(std::filesystem::last_write_time(path));
  if (const auto created = creationTime(path)) {
    result["creationTime"] = *created;
  } else {
    result["creationTime"] = nullptr;
  }

  if (includeMd5 && std::filesystem::is_regular_file(path)) {
    result["md5"] = md5File(path);
  }

  return result;
}

folly::dynamic legacyFileInfo(const std::filesystem::path &path, bool includeMd5 = false) {
  std::error_code error;
  const bool exists = std::filesystem::exists(path, error) && !error;
  folly::dynamic result = folly::dynamic::object("exists", exists)("isDirectory", false);

  if (!exists) {
    return result;
  }
  const bool isDirectory = std::filesystem::is_directory(path, error) && !error;
  result["isDirectory"] = isDirectory;
  result["uri"] = toFileUri(path, isDirectory);
  uint64_t size = 0;

  if (isDirectory) {
    for (const auto &entry : std::filesystem::recursive_directory_iterator(path)) {
      if (entry.is_regular_file()) {
        size += entry.file_size();
      }
    }
  } else {
    size = std::filesystem::file_size(path);
  }
  result["size"] = static_cast<double>(size);
  result["modificationTime"] = milliseconds(std::filesystem::last_write_time(path)) / 1000.0;

  if (includeMd5 && !isDirectory) {
    result["md5"] = md5File(path);
  }

  return result;
}

folly::dynamic directoryInfo(const std::filesystem::path &path) {
  std::error_code error;
  const bool exists = std::filesystem::is_directory(path, error) && !error;
  folly::dynamic result = folly::dynamic::object("exists", exists)("uri", toFileUri(path, true));

  if (!exists) {
    requireDirectoryType(path);
    return result;
  }
  auto files = folly::dynamic::array();
  uint64_t size = 0;

  for (const auto &entry : std::filesystem::directory_iterator(path)) {
    files.push_back(entry.path().filename().string());
  }
  for (const auto &entry : std::filesystem::recursive_directory_iterator(path)) {
    if (entry.is_regular_file()) {
      size += entry.file_size();
    }
  }

  result["files"] = std::move(files);
  result["size"] = static_cast<double>(size);
  result["modificationTime"] = milliseconds(std::filesystem::last_write_time(path));
  if (const auto created = creationTime(path)) {
    result["creationTime"] = *created;
  } else {
    result["creationTime"] = nullptr;
  }

  return result;
}

using BackgroundTask = std::function<folly::dynamic()>;
using TaskFactory = std::function<BackgroundTask(Invocation &)>;

const char *backgroundErrorCode(const std::string &operation) {
  if (operation == "readDirectoryAsync") {
    return "ERR_FILE_SYSTEM_CANNOT_READ_DIRECTORY";
  }
  if (operation == "makeDirectoryAsync") {
    return "ERR_FILE_SYSTEM_CANNOT_CREATE_DIRECTORY";
  }
  if (operation == "moveAsync") {
    return "ERR_FILE_SYSTEM_CANNOT_MOVE_FILE";
  }
  if (operation == "copyAsync") {
    return "ERR_FILE_SYSTEM_COPY_FAILED";
  }
  return "ERR_FILE_SYSTEM";
}

FunctionDefinition backgroundFunction(std::string name, size_t arity, size_t requiredArity, TaskFactory factory) {
  const auto operation = name;

  return FunctionDefinition{
      .name = std::move(name),
      .arity = arity,
      .requiredArity = requiredArity,
      .async = true,
      // Argument decoding happens on the runtime thread. The actual native
      // operation is scheduled below without touching RNOH's absent runners.
      .queue = FunctionQueue::JavaScript,
      .asyncBody = [factory = std::move(factory), operation](Invocation &invocation, const std::shared_ptr<Promise> &promise) {
        auto task = factory(invocation);

        nativeFileSystemExecutor().schedule([task = std::move(task), promise, operation]() mutable {
          try {
            promise->cancellationToken()->throwIfCancellationRequested();
            auto result = std::make_shared<folly::dynamic>(task());

            promise->cancellationToken()->throwIfCancellationRequested();
            promise->resolve([result = std::move(result)](jsi::Runtime &runtime) {
              return jsi::valueFromDynamic(runtime, *result);
            });
          } catch (const CodedError &error) {
            promise->reject(error);
          } catch (const std::filesystem::filesystem_error &error) {
            promise->reject(backgroundErrorCode(operation), error.what());
          } catch (const std::exception &error) {
            promise->reject(backgroundErrorCode(operation), error.what());
          } catch (...) {
            promise->reject("ERR_FILE_SYSTEM", "The native file-system operation threw a non-standard exception.");
          }
        });
      }};
}

template <typename Return, typename Transform>
SharedObjectFunctionDefinition fileReadFunction(std::string name, Transform transform) {
  SharedObjectFunctionDefinition definition;
  definition.name = std::move(name);
  definition.arity = 0;
  definition.requiredArity = 0;
  definition.async = true;
  // The resource descriptor/path is resolved while the RuntimeContext and JSI
  // runtime are valid. Only the pure byte read and transform cross threads.
  definition.queue = FunctionQueue::JavaScript;
  definition.asyncBody =
      [transform = std::move(transform)](
          Invocation &invocation,
          const std::shared_ptr<NativeSharedObject> &object,
          const std::shared_ptr<Promise> &promise) mutable {
        auto owner = std::dynamic_pointer_cast<FileObject>(object);
        if (!owner) {
          throw CodedError(
              "ERR_SHARED_OBJECT_TYPE",
              invocation.path() + " received an incompatible native owner.");
        }
        auto context = invocation.sharedContext();
        auto readBytes = owner->prepareBytesTask();
        nativeFileSystemExecutor().schedule(
            [context,
             promise,
             readBytes = std::move(readBytes),
             transform]() mutable {
              try {
                promise->cancellationToken()->throwIfCancellationRequested();
                auto result = std::make_shared<Return>(transform(readBytes()));

                promise->cancellationToken()->throwIfCancellationRequested();
                promise->resolve(
                    [context, result = std::move(result)](jsi::Runtime &) mutable {
                      return convertToJS(context, std::move(*result));
                    });
              } catch (const CodedError &error) {
                promise->reject(error);
              } catch (const std::exception &error) {
                promise->reject("ERR_FILE_SYSTEM", error.what());
              } catch (...) {
                promise->reject("ERR_FILE_SYSTEM", "The native file read threw a non-standard exception.");
              }
            });
      };
  return definition;
}

facebook::jsi::Value invokeService(Invocation &invocation, std::string method, folly::dynamic arguments) {
  return invocation.context().invokePlatformService(kService, std::move(method), std::move(arguments));
}

FunctionDefinition serviceFunction(std::string jsName, std::string method, size_t arity, size_t requiredArity) {
  return FunctionDefinition{
      .name = std::move(jsName),
      .arity = arity,
      .requiredArity = requiredArity,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [method = std::move(method)](Invocation &invocation) {
        auto args = folly::dynamic::array();
        for (size_t index = 0; index < invocation.argumentCount(); ++index) {
          args.push_back(jsi::dynamicFromValue(invocation.runtime(), invocation.argument(index)));
        }

        return invokeService(invocation, method, std::move(args));
      }};
}

FunctionDefinition pickerFunction(
    std::string jsName,
    std::string method,
    std::string uriKey,
    size_t arity,
    std::shared_ptr<FileSystemState> state,
    bool directory) {
  return FunctionDefinition{
      .name = std::move(jsName),
      .arity = arity,
      .requiredArity = 0,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [method = std::move(method), uriKey = std::move(uriKey), state = std::move(state), directory](Invocation &invocation) {
        auto args = folly::dynamic::array();
        for (size_t index = 0; index < invocation.argumentCount(); ++index) {
          args.push_back(jsi::dynamicFromValue(invocation.runtime(), invocation.argument(index)));
        }

        auto platformPromise = invokeService(invocation, method, std::move(args));
        if (!platformPromise.isObject()) {
          throw CodedError("ERR_FILE_SYSTEM_PICKER", "Harmony picker did not return a Promise.");
        }
        auto &runtime = invocation.runtime();
        auto promise = platformPromise.getObject(runtime);
        auto then = promise.getPropertyAsFunction(runtime, "then");
        auto onFulfilled = jsi::Function::createFromHostFunction(
            runtime, jsi::PropNameID::forAscii(runtime, "grantExpoFileSystemPickerUri"), 1, [state, directory, uriKey](jsi::Runtime &callbackRuntime, const jsi::Value &, const jsi::Value *arguments, size_t count) {
              if (count < 1 || !arguments[0].isObject()) {
                throw jsi::JSError(callbackRuntime, "ERR_FILE_SYSTEM_PICKER: missing picker result");
              }
              try {
                auto result = jsi::dynamicFromValue(callbackRuntime, arguments[0]);
                if (uriKey == "directoryUri" && result.isObject() && result.count("granted")
                    && result.at("granted").isBool() && !result.at("granted").asBool()) {
                  return jsi::Value(callbackRuntime, arguments[0]);
                }
                if (!result.isObject() || !result.count(uriKey) || !result.at(uriKey).isString()) {
                  throw CodedError("ERR_FILE_SYSTEM_PICKER", "Harmony picker returned an invalid URI record.");
                }
                state->grant(result.at(uriKey).asString(), directory);
              } catch (const std::exception &error) {
                throw jsi::JSError(callbackRuntime, error.what());
              }
              return jsi::Value(callbackRuntime, arguments[0]);
            });
        return then.callWithThis(runtime, promise, std::move(onFulfilled));
      }};
}

class ModernFileSystemModule final : public ExpoModule {
public:
  explicit ModernFileSystemModule(std::shared_ptr<FileSystemState> state) : state_(std::move(state)) {}

  ModuleDefinition definition() override {
    ModuleBuilder module("FileSystem");
    module.constant<std::string>("documentDirectory", [state = state_]() { return toFileUri(state->document(), true); });
    module.constant<std::string>("cacheDirectory", [state = state_]() { return toFileUri(state->cache(), true); });
    module.constant<std::string>("bundleDirectory", []() { return std::string("asset:///"); });
    module.constant("appleSharedContainers", [](Invocation &invocation) { return jsi::Object(invocation.runtime()); });
    module.property(typedProperty<double>("totalDiskSpace", [state = state_]() { return static_cast<double>(state->totalSpace()); }));
    module.property(typedProperty<double>("availableDiskSpace", [state = state_]() { return static_cast<double>(state->freeSpace()); }));
    module.function(FunctionDefinition{
        .name = "info", .arity = 1, .body = [state = state_](Invocation &invocation) {
          const auto uri = convertFromJS<std::string>(
              invocation.sharedContext(), invocation.argument(0), invocation.path());
          const auto path = state->resolveForProbe(uri);

          const bool exists = path && std::filesystem::exists(*path);
          folly::dynamic result = folly::dynamic::object("exists", exists);
          result["isDirectory"] = exists
                                    ? folly::dynamic(std::filesystem::is_directory(*path))
                                    : folly::dynamic(nullptr);

          return jsi::valueFromDynamic(invocation.runtime(), result);
        }});
    module.function(FunctionDefinition{
        .name = "downloadFileAsync", .arity = 3, .requiredArity = 2, .async = true, .body = [state = state_](Invocation &invocation) {
          const auto url = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
          const auto destination = convertFromJS<std::shared_ptr<NativeSharedObject>>(invocation.sharedContext(), invocation.argument(1), invocation.path());
          std::filesystem::path output;
          bool destinationIsDirectory = false;
          if (auto file = std::dynamic_pointer_cast<FileObject>(destination)) {
            output = file->path();
            requireFileType(output);
          } else if (auto directory = std::dynamic_pointer_cast<DirectoryObject>(destination)) {
            output = directory->path();
            requireDirectoryType(output);
            destinationIsDirectory = true;
          } else {
            throw CodedError("ERR_FILE_SYSTEM_DESTINATION", "Download destination must be a File or Directory.");
          }

          state->resolve(toFileUri(output, destinationIsDirectory));
          auto options = valueToDynamic(invocation, 2);
          if (!destinationIsDirectory && std::filesystem::exists(output) && !dynamicBool(options, "idempotent")) {
            throw CodedError("ERR_DESTINATION_ALREADY_EXISTS", "Download destination already exists.");
          }

          folly::dynamic request = folly::dynamic::object("url", url)("destination", output.string())("destinationIsDirectory", destinationIsDirectory)("rejectIfExists", true)("rejectHttpErrors", true)("idempotent", dynamicBool(options, "idempotent"));
          if (options.isObject() && options.count("headers")) {
            request["headers"] = options["headers"];
          }

          return invokeService(invocation, "downloadUri", folly::dynamic::array(std::move(request)));
        }});
    module.function(pickerFunction("pickDirectoryAsync", "pickDirectoryRecord", "uri", 1, state_, true));
    module.function(pickerFunction("pickFileAsync", "pickFileRecord", "uri", 2, state_, false));

    ClassDefinitionBuilder<FileObject> file("FileSystemFile");
    file.constructor<std::string>([state = state_](std::string uri) { return std::make_shared<FileObject>(state, std::move(uri)); });
    file.function(typedSharedFunction<FileObject, void>("validatePath", [](FileObject &) {}));
    file.function(SharedObjectFunctionDefinition{
        .name = "create", .arity = 1, .requiredArity = 0, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          auto owner = std::dynamic_pointer_cast<FileObject>(object);
          const auto options = valueToDynamic(invocation, 0);
          requireFileType(owner->path());

          if (dynamicBool(options, "intermediates")) {
            std::filesystem::create_directories(owner->path().parent_path());
          }
          if (std::filesystem::exists(owner->path())) {
            if (!dynamicBool(options, "overwrite")) {
              throw CodedError("ERR_UNABLE_TO_CREATE", "File already exists.");
            }
            std::filesystem::remove_all(owner->path());
          }
          std::ofstream output(owner->path(), std::ios::binary);
          if (!output) {
            throw CodedError("ERR_UNABLE_TO_CREATE", "Cannot create file.");
          }

          return jsi::Value::undefined();
        }});
    file.function(SharedObjectFunctionDefinition{
        .name = "write", .arity = 2, .requiredArity = 1, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          auto owner = std::dynamic_pointer_cast<FileObject>(object);
          requireFileType(owner->path());
          const auto options = valueToDynamic(invocation, 1);
          std::vector<uint8_t> bytes;

          if (invocation.argument(0).isString()) {
            const auto text = invocation.argument(0).getString(invocation.runtime()).utf8(invocation.runtime());
            bytes = dynamicString(options, "encoding") == "base64"
                      ? base64Decode(text)
                      : std::vector<uint8_t>(text.begin(), text.end());
          } else {
            bytes = convertFromJS<std::vector<uint8_t>>(invocation.sharedContext(), invocation.argument(0), invocation.path());
          }

          writeBytesFile(owner->path(), bytes, dynamicBool(options, "append"));
          return jsi::Value::undefined();
        }});
    file.function(fileReadFunction<std::string>("text", [](std::vector<uint8_t> bytes) {
      return replaceInvalidUtf8(std::string(bytes.begin(), bytes.end()));
    }));
    file.function(typedSharedFunction<FileObject, std::string>("textSync", [](FileObject &owner) {
      if (owner.isBundle()) {
        return replaceInvalidUtf8(std::string(owner.rawBytes().begin(), owner.rawBytes().end()));
      }
      return readTextFile(owner.path());
    }));
    file.function(fileReadFunction<std::string>("base64", [](std::vector<uint8_t> bytes) {
      return base64Encode(bytes);
    }));
    file.function(typedSharedFunction<FileObject, std::string>("base64Sync", [](FileObject &owner) {
      return base64Encode(owner.isBundle() ? owner.rawBytes() : readBytesFile(owner.path()));
    }));
    file.function(fileReadFunction<std::vector<uint8_t>>("bytes", [](std::vector<uint8_t> bytes) {
      return bytes;
    }));
    file.function(typedSharedFunction<FileObject, std::vector<uint8_t>>("bytesSync", [](FileObject &owner) {
      return owner.isBundle() ? owner.rawBytes() : readBytesFile(owner.path());
    }));
    file.function(SharedObjectFunctionDefinition{
        .name = "info", .arity = 1, .requiredArity = 0, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          auto owner = std::dynamic_pointer_cast<FileObject>(object);
          const bool includeMd5 = dynamicBool(valueToDynamic(invocation, 0), "md5");
          const auto result = owner->isBundle() ? rawFileInfo(*owner, includeMd5) : fileInfo(owner->path(), includeMd5);

          return jsi::valueFromDynamic(invocation.runtime(), result);
        }});
    file.function(typedSharedFunction<FileObject, void>("delete", [](FileObject &owner) {
      if (!std::filesystem::exists(owner.path())) {
        throw CodedError("ERR_FILE_SYSTEM_CANNOT_DELETE", "File does not exist or cannot be deleted.");
      }

      std::filesystem::remove_all(owner.path());
    }));
    file.function(typedSharedFunction<FileObject, void, std::shared_ptr<NativeSharedObject>>(
        "copy", [](FileObject &owner, std::shared_ptr<NativeSharedObject> destination) {
          requireFileType(owner.path());
          const auto target = fileDestinationPath(owner.path(), destination);

          if (std::filesystem::exists(target)) {
            throw CodedError("ERR_FILE_SYSTEM_DESTINATION_EXISTS", "Copy destination exists.");
          }
          std::filesystem::copy_file(owner.path(), target);
        }));
    file.function(typedSharedFunction<FileObject, void, std::shared_ptr<NativeSharedObject>>(
        "move", [](FileObject &owner, std::shared_ptr<NativeSharedObject> destination) {
          requireFileType(owner.path());
          const auto target = fileDestinationPath(owner.path(), destination);

          if (std::filesystem::exists(target)) {
            throw CodedError("ERR_FILE_SYSTEM_DESTINATION_EXISTS", "Move destination exists.");
          }
          movePath(owner.path(), target);
          owner.setPath(target);
        }));
    file.function(typedSharedFunction<FileObject, void, std::string>("rename", [](FileObject &owner, std::string name) {
      requireFileType(owner.path());
      validateChildName(name);
      const auto source = owner.path();
      const auto target = source.parent_path() / name;
      if (target == source) {
        return;
      }
      if (std::filesystem::exists(target)) {
        throw CodedError("ERR_FILE_SYSTEM_DESTINATION_EXISTS", "Rename destination exists.");
      }

      std::filesystem::rename(owner.path(), target);
      owner.setPath(target);
    }));
    file.function(SharedObjectFunctionDefinition{
        .name = "open", .arity = 0, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          auto owner = std::dynamic_pointer_cast<FileObject>(object);
          requireFileType(owner->path());
          return convertToJS(invocation.sharedContext(), std::make_shared<FileHandleObject>(std::move(owner)));
        }});
    file.property(typedSharedProperty<FileObject, bool>("exists", [](FileObject &owner) {
      if (owner.isBundle()) {
        return owner.rawExists();
      }
      const auto path = owner.probePath();
      return path && std::filesystem::is_regular_file(*path);
    }));
    file.property(typedSharedProperty<FileObject, std::optional<double>>("modificationTime", [](FileObject &owner) -> std::optional<double> {
      if (owner.isBundle()) {
        return std::nullopt;
      }
      const auto path = owner.probePath();
      if (!path || !std::filesystem::exists(*path)) {
        return std::nullopt;
      }
      requireFileType(*path);
      return milliseconds(std::filesystem::last_write_time(*path));
    }));
    file.property(typedSharedProperty<FileObject, std::optional<double>>("creationTime", [](FileObject &owner) -> std::optional<double> {
      if (owner.isBundle()) {
        return std::nullopt;
      }
      const auto path = owner.probePath();
      if (!path || !std::filesystem::exists(*path)) {
        return std::nullopt;
      }
      requireFileType(*path);
      return creationTime(*path);
    }));
    file.property(typedSharedProperty<FileObject, std::string>("uri", [](FileObject &owner) { return owner.uri(); }));
    file.property(typedSharedProperty<FileObject, std::string>("contentUri", [](FileObject &owner) {
      return owner.isBundle()
               ? owner.state()->bundledContentUri(owner.rawPath(), owner.rawBytes())
               : owner.state()->contentUri(owner.path());
    }));
    file.property(typedSharedProperty<FileObject, std::optional<std::string>>("md5", [](FileObject &owner) -> std::optional<std::string> {
      if (owner.isBundle()) {
        return owner.rawExists() ? std::optional<std::string>(md5Bytes(owner.rawBytes())) : std::nullopt;
      }
      const auto path = owner.probePath();
      if (!path || !std::filesystem::is_regular_file(*path)) {
        return std::nullopt;
      }
      return md5File(*path);
    }));
    file.property(typedSharedProperty<FileObject, double>("size", [](FileObject &owner) {
      if (owner.isBundle()) {
        return owner.rawExists() ? static_cast<double>(owner.rawSize()) : 0.0;
      }
      const auto path = owner.probePath();
      return path && std::filesystem::is_regular_file(*path)
               ? static_cast<double>(std::filesystem::file_size(*path))
               : 0.0;
    }));
    file.property(typedSharedProperty<FileObject, std::string>("type", [](FileObject &owner) {
      if (owner.isBundle()) {
        return owner.state()->mimeType(std::filesystem::path(owner.rawPath()));
      }
      const auto path = owner.probePath();
      return path ? owner.state()->mimeType(*path) : std::string();
    }));
    module.klass(std::move(file).build());

    ClassDefinitionBuilder<FileHandleObject> handle("FileSystemFileHandle");
    handle.constructor<std::shared_ptr<FileObject>>([](std::shared_ptr<FileObject> owner) { return std::make_shared<FileHandleObject>(owner); });
    handle.function(typedSharedFunction<FileHandleObject, std::vector<uint8_t>, double>("readBytes", [](FileHandleObject &owner, double count) {
      if (!detail::isValidFileHandleInteger(count)) {
        throw CodedError(
            "ERR_FILE_SYSTEM_INVALID_LENGTH",
            "Read length must be a finite, non-negative safe integer.");
      }
      return owner.read(detail::fileHandleInteger(count));
    }));
    handle.function(typedSharedFunction<FileHandleObject, void, std::vector<uint8_t>>("writeBytes", [](FileHandleObject &owner, std::vector<uint8_t> bytes) { owner.write(bytes); }));
    handle.function(typedSharedFunction<FileHandleObject, void>("close", [](FileHandleObject &owner) { owner.close(); }));
    handle.property(typedSharedProperty<FileHandleObject, std::optional<double>>("offset", [](FileHandleObject &owner) { return owner.offset(); }, [](FileHandleObject &owner, std::optional<double> value) {
      if (!value) {
        throw CodedError("ERR_FILE_SYSTEM_INVALID_OFFSET", "Offset cannot be null.");
      }

      owner.setOffset(*value); }));
    handle.property(typedSharedProperty<FileHandleObject, std::optional<double>>("size", [](FileHandleObject &owner) { return owner.size(); }));
    module.klass(std::move(handle).build());

    ClassDefinitionBuilder<DirectoryObject> directory("FileSystemDirectory");
    directory.constructor<std::string>([state = state_](std::string uri) { return std::make_shared<DirectoryObject>(state, std::move(uri)); });
    directory.function(typedSharedFunction<DirectoryObject, void>("validatePath", [](DirectoryObject &owner) { static_cast<void>(owner.uri()); }));
    directory.function(SharedObjectFunctionDefinition{
        .name = "info", .arity = 0, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          auto owner = std::dynamic_pointer_cast<DirectoryObject>(object);
          const auto result = owner->isBundle() ? rawDirectoryInfo(*owner) : directoryInfo(owner->path());
          return jsi::valueFromDynamic(invocation.runtime(), result);
        }});
    directory.function(typedSharedFunction<DirectoryObject, void>("delete", [](DirectoryObject &owner) {
      if (!std::filesystem::exists(owner.path())) {
        throw CodedError("ERR_FILE_SYSTEM_CANNOT_DELETE", "Directory does not exist.");
      }
      std::filesystem::remove_all(owner.path());
    }));
    directory.function(SharedObjectFunctionDefinition{
        .name = "create", .arity = 1, .requiredArity = 0, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          auto owner = std::dynamic_pointer_cast<DirectoryObject>(object);
          const auto options = valueToDynamic(invocation, 0);
          requireDirectoryType(owner->path());
          const bool exists = std::filesystem::exists(owner->path());

          if (exists) {
            if (dynamicBool(options, "idempotent")) {
              return jsi::Value::undefined();
            }
            if (!dynamicBool(options, "overwrite")) {
              throw CodedError("ERR_UNABLE_TO_CREATE", "Directory already exists.");
            }
            std::filesystem::remove_all(owner->path());
          }

          if (!exists || dynamicBool(options, "overwrite")) {
            const bool created = dynamicBool(options, "intermediates")
                                   ? std::filesystem::create_directories(owner->path())
                                   : std::filesystem::create_directory(owner->path());
            if (!created && !std::filesystem::exists(owner->path())) {
              throw CodedError("ERR_UNABLE_TO_CREATE", "Cannot create directory.");
            }
          }

          return jsi::Value::undefined();
        }});
    directory.function(typedSharedFunction<DirectoryObject, std::shared_ptr<DirectoryObject>, std::string>(
        "createDirectory", [](DirectoryObject &owner, std::string name) {
          requireDirectoryType(owner.path());
          validateChildName(name);
          const auto target = owner.path() / name;

          if (!std::filesystem::create_directory(target)) {
            throw CodedError("ERR_UNABLE_TO_CREATE", "Cannot create child directory.");
          }
          return std::make_shared<DirectoryObject>(owner.state(), toFileUri(target, true));
        }));
    directory.function(typedSharedFunction<DirectoryObject, std::shared_ptr<FileObject>, std::string, std::optional<std::string>>(
        "createFile", [](DirectoryObject &owner, std::string name, std::optional<std::string>) {
          requireDirectoryType(owner.path());
          validateChildName(name);
          const auto target = owner.path() / name;

          if (std::filesystem::exists(target)) {
            throw CodedError("ERR_UNABLE_TO_CREATE", "Child file already exists.");
          }
          std::ofstream output(target, std::ios::binary);
          if (!output) {
            throw CodedError("ERR_UNABLE_TO_CREATE", "Cannot create child file.");
          }

          return std::make_shared<FileObject>(owner.state(), toFileUri(target));
        }));
    directory.function(typedSharedFunction<DirectoryObject, void, std::shared_ptr<NativeSharedObject>>(
        "copy", [](DirectoryObject &owner, std::shared_ptr<NativeSharedObject> destination) {
          requireDirectoryType(owner.path());
          const auto target = directoryDestinationPath(owner.path(), destination);
          requireTargetOutsideDirectory(owner.path(), target);

          if (std::filesystem::exists(target)) {
            throw CodedError("ERR_FILE_SYSTEM_DESTINATION_EXISTS", "Copy destination exists.");
          }
          std::filesystem::copy(owner.path(), target, std::filesystem::copy_options::recursive);
        }));
    directory.function(typedSharedFunction<DirectoryObject, void, std::shared_ptr<NativeSharedObject>>(
        "move", [](DirectoryObject &owner, std::shared_ptr<NativeSharedObject> destination) {
          requireDirectoryType(owner.path());
          const auto target = directoryDestinationPath(owner.path(), destination);
          requireTargetOutsideDirectory(owner.path(), target);

          if (std::filesystem::exists(target)) {
            throw CodedError("ERR_FILE_SYSTEM_DESTINATION_EXISTS", "Move destination exists.");
          }
          movePath(owner.path(), target);
          owner.setPath(target);
        }));
    directory.function(typedSharedFunction<DirectoryObject, void, std::string>("rename", [](DirectoryObject &owner, std::string name) {
      requireDirectoryType(owner.path());
      validateChildName(name);
      const auto source = owner.path();
      const auto target = source.parent_path() / name;
      if (target == source) {
        return;
      }
      if (std::filesystem::exists(target)) {
        throw CodedError("ERR_FILE_SYSTEM_DESTINATION_EXISTS", "Rename destination exists.");
      }

      std::filesystem::rename(owner.path(), target);
      owner.setPath(target);
    }));
    directory.function(SharedObjectFunctionDefinition{
        .name = "listAsRecords", .arity = 0, .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          auto owner = std::dynamic_pointer_cast<DirectoryObject>(object);
          auto records = folly::dynamic::array();

          if (owner->isBundle()) {
            for (const auto &name : owner->rawList()) {
              const auto child = joinRawPath(owner->rawPath(), name);
              const bool isDirectory = owner->state()->rawIsDirectory(child);
              records.push_back(folly::dynamic::object("isDirectory", isDirectory)("uri", toAssetUri(child, isDirectory)));
            }
          } else {
            requireDirectoryType(owner->path());
            for (const auto &entry : std::filesystem::directory_iterator(owner->path())) {
              records.push_back(folly::dynamic::object("isDirectory", entry.is_directory())("uri", toFileUri(entry.path(), entry.is_directory())));
            }
          }

          return jsi::valueFromDynamic(invocation.runtime(), records);
        }});
    directory.property(typedSharedProperty<DirectoryObject, bool>("exists", [](DirectoryObject &owner) {
      if (!owner.isBundle()) {
        const auto path = owner.probePath();
        return path && std::filesystem::is_directory(*path);
      }
      try {
        static_cast<void>(owner.rawList());
        return true;
      } catch (...) {
        return false;
      }
    }));
    directory.property(typedSharedProperty<DirectoryObject, std::string>("uri", [](DirectoryObject &owner) { return owner.uri(); }));
    directory.property(typedSharedProperty<DirectoryObject, std::optional<double>>("size", [](DirectoryObject &owner) -> std::optional<double> {
      if (owner.isBundle()) {
        try {
          return static_cast<double>(rawDirectorySize(owner.state(), owner.rawPath()));
        } catch (...) {
          return std::nullopt;
        }
      }
      const auto path = owner.probePath();
      if (!path || !std::filesystem::is_directory(*path)) {
        return std::nullopt;
      }

      double size = 0;
      for (const auto &entry : std::filesystem::recursive_directory_iterator(*path)) {
        if (entry.is_regular_file()) {
          size += static_cast<double>(entry.file_size());
        }
      }
      return size;
    }));
    module.klass(std::move(directory).build());
    return std::move(module).build();
  }

private:
  std::shared_ptr<FileSystemState> state_;
};

class LegacyFileSystemModule final : public ExpoModule {
public:
  explicit LegacyFileSystemModule(std::shared_ptr<FileSystemState> state) : state_(std::move(state)) {}

  ModuleDefinition definition() override {
    ModuleBuilder module("ExponentFileSystem");
    module.constant<std::string>("documentDirectory", [state = state_]() { return toFileUri(state->document(), true); });
    module.constant<std::string>("cacheDirectory", [state = state_]() { return toFileUri(state->cache(), true); });
    module.constant<std::string>("bundleDirectory", []() { return std::string("asset:///"); });
    module.events({"expo-file-system.downloadProgress", "expo-file-system.uploadProgress"});
    module.function(backgroundFunction("getInfoAsync", 2, 1, [state = state_](Invocation &invocation) -> BackgroundTask {
      const auto uri = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
      const bool includeMd5 = dynamicBool(valueToDynamic(invocation, 1), "md5");

      if (uri.starts_with("asset://") || uri.starts_with("rawfile://") || uri.find(':') == std::string::npos) {
        std::optional<size_t> size;
        std::optional<BytesTask> readBytes;

        try {
          const auto rawPath = rawPathFromUri(uri, true);
          size = state->rawSize(rawPath);
          if (includeMd5) {
            readBytes = state->prepareRawBytesTask(rawPath);
          }
        } catch (...) {
          size.reset();
          readBytes.reset();
        }

        return [uri, size, readBytes = std::move(readBytes), includeMd5]() mutable -> folly::dynamic {
          folly::dynamic result = folly::dynamic::object("exists", size.has_value())("isDirectory", false);

          if (!size) {
            return result;
          }
          result["uri"] = uri;
          result["size"] = static_cast<double>(*size);

          if (includeMd5) {
            if (!readBytes) {
              return folly::dynamic::object("exists", false)("isDirectory", false);
            }
            try {
              result["md5"] = md5Bytes((*readBytes)());
            } catch (...) {
              return folly::dynamic::object("exists", false)("isDirectory", false);
            }
          }

          return result;
        };
      }
      return [state, uri, includeMd5]() {
        return legacyFileInfo(state->resolve(uri), includeMd5);
      };
    }));
    module.function(backgroundFunction("readAsStringAsync", 2, 1, [state = state_](Invocation &invocation) -> BackgroundTask {
      const auto uri = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
      const bool raw = uri.starts_with("asset://") || uri.starts_with("rawfile://") || uri.find(':') == std::string::npos;
      auto read = raw ? state->prepareRawBytesTask(rawPathFromUri(uri, true)) : BytesTask();
      auto options = valueToDynamic(invocation, 1);

      return [state, uri, raw, read = std::move(read), options = std::move(options)]() mutable {
        auto bytes = raw ? read() : readBytesFile(state->resolve(uri));
        if (dynamicString(options, "encoding") != "base64") {
          return folly::dynamic(replaceInvalidUtf8(std::string(bytes.begin(), bytes.end())));
        }

        const bool hasRange = options.isObject() && options.count("position") && options.count("length");
        const auto rawPosition = hasRange ? options["position"].asInt() : 0;
        if (rawPosition < 0) {
          throw CodedError("ERR_FILE_SYSTEM_INVALID_OFFSET", "Read position cannot be negative.");
        }
        const auto position = static_cast<size_t>(rawPosition);
        const auto rawLength = hasRange
                                 ? options["length"].asInt()
                                 : static_cast<int64_t>(bytes.size());
        if (rawLength < 0) {
          throw CodedError("ERR_FILE_SYSTEM_INVALID_LENGTH", "Read length cannot be negative.");
        }
        const auto length = static_cast<size_t>(rawLength);
        if (position > bytes.size()) {
          throw CodedError("ERR_FILE_SYSTEM_INVALID_OFFSET", "Read position is beyond the file.");
        }

        const auto available = bytes.size() - position;
        const auto end = position + std::min(length, available);
        bytes = std::vector<uint8_t>(bytes.begin() + static_cast<std::ptrdiff_t>(position), bytes.begin() + static_cast<std::ptrdiff_t>(end));

        return folly::dynamic(base64Encode(bytes));
      };
    }));
    module.function(backgroundFunction("writeAsStringAsync", 3, 2, [state = state_](Invocation &invocation) {
      auto uri = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
      auto text = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(1), invocation.path());
      auto options = valueToDynamic(invocation, 2);

      return [state, uri = std::move(uri), text = std::move(text), options = std::move(options)]() {
        const auto bytes = dynamicString(options, "encoding") == "base64" ? base64Decode(text) : std::vector<uint8_t>(text.begin(), text.end());

        writeBytesFile(state->resolve(uri), bytes, dynamicBool(options, "append"));
        return folly::dynamic(nullptr);
      };
    }));
    module.function(backgroundFunction("deleteAsync", 2, 1, [state = state_](Invocation &invocation) {
      auto uri = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
      const bool idempotent = dynamicBool(valueToDynamic(invocation, 1), "idempotent");

      return [state, uri = std::move(uri), idempotent]() {
        const auto path = state->resolve(uri);

        if (!std::filesystem::exists(path)) {
          if (idempotent) {
            return folly::dynamic(nullptr);
          }
          throw CodedError("ERR_FILE_SYSTEM_FILE_NOT_FOUND", "Path does not exist.");
        }

        std::filesystem::remove_all(path);
        return folly::dynamic(nullptr);
      };
    }));
    auto relocate = [state = state_](bool move) {
      return [state, move](Invocation &invocation) -> BackgroundTask {
        const auto options = valueToDynamic(invocation, 0);
        auto sourceUri = dynamicString(options, "from");
        auto targetUri = dynamicString(options, "to");
        const bool raw = sourceUri.starts_with("asset://")
                      || sourceUri.starts_with("rawfile://")
                      || sourceUri.find(':') == std::string::npos;

        if (raw) {
          if (move) {
            throw CodedError(
                "ERR_FILE_SYSTEM_UNSUPPORTED_SCHEME",
                "Bundled resources are read-only and cannot be moved.");
          }
          const auto target = state->resolve(targetUri);
          auto copyRaw = state->prepareRawCopyTask(rawPathFromUri(sourceUri, true), target);

          return [copyRaw = std::move(copyRaw)]() mutable {
            copyRaw();
            return folly::dynamic(nullptr);
          };
        }
        return [state, sourceUri = std::move(sourceUri), targetUri = std::move(targetUri), move]() {
          const auto source = state->resolve(sourceUri, false);
          const auto target = state->resolve(targetUri);

          if (std::filesystem::is_directory(source)) {
            requireTargetOutsideDirectory(source, target);
          }
          if (move) {
            movePath(source, target);
          } else {
            std::filesystem::copy(source, target, std::filesystem::copy_options::recursive | std::filesystem::copy_options::overwrite_existing);
          }

          return folly::dynamic(nullptr);
        };
      };
    };
    module.function(backgroundFunction("moveAsync", 1, 1, relocate(true)));
    module.function(backgroundFunction("copyAsync", 1, 1, relocate(false)));
    module.function(backgroundFunction("makeDirectoryAsync", 2, 1, [state = state_](Invocation &invocation) {
      auto uri = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
      const bool intermediates = dynamicBool(valueToDynamic(invocation, 1), "intermediates");

      return [state, uri = std::move(uri), intermediates]() {
        const auto path = state->resolve(uri);
        const bool created = intermediates ? std::filesystem::create_directories(path) : std::filesystem::create_directory(path);

        if (!created && (!intermediates || !std::filesystem::is_directory(path))) {
          throw CodedError("ERR_FILE_SYSTEM_CANNOT_CREATE_DIRECTORY", "Cannot create directory.");
        }
        return folly::dynamic(nullptr);
      };
    }));
    module.function(backgroundFunction("readDirectoryAsync", 1, 1, [state = state_](Invocation &invocation) {
      auto uri = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());

      return [state, uri = std::move(uri)]() {
        const auto path = state->resolve(uri, false);
        auto result = folly::dynamic::array();

        for (const auto &entry : std::filesystem::directory_iterator(path)) {
          result.push_back(entry.path().filename().string());
        }
        return result;
      };
    }));
    module.function(backgroundFunction("getTotalDiskCapacityAsync", 0, 0, [state = state_](Invocation &) {
      return [state]() { return folly::dynamic(static_cast<double>(state->totalSpace())); };
    }));
    module.function(backgroundFunction("getFreeDiskStorageAsync", 0, 0, [state = state_](Invocation &) {
      return [state]() { return folly::dynamic(static_cast<double>(state->freeSpace())); };
    }));
    module.function(typedAsyncFunction<std::string, std::string>("getContentUriAsync", [state = state_](std::string uri) { return state->contentUri(state->resolve(uri, false)); }, FunctionQueue::JavaScript));
    module.function(FunctionDefinition{
        .name = "downloadAsync", .arity = 3, .requiredArity = 2, .async = true, .body = [state = state_](Invocation &invocation) {
          folly::dynamic request = folly::dynamic::object("url", convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path()))("destination", state->resolve(convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(1), invocation.path())).string());
          auto options = valueToDynamic(invocation, 2);

          if (options.isObject() && options.count("headers")) {
            request["headers"] = options["headers"];
          }
          request["md5"] = dynamicBool(options, "md5");

          return invokeService(invocation, "download", folly::dynamic::array(std::move(request)));
        }});
    module.function(FunctionDefinition{
        .name = "downloadResumableStartAsync", .arity = 5, .requiredArity = 4, .async = true, .body = [state = state_](Invocation &invocation) {
          auto options = valueToDynamic(invocation, 3);
          const auto resume = invocation.argumentCount() > 4 && invocation.argument(4).isString()
                                ? parseResumeOffset(invocation.argument(4).getString(invocation.runtime()).utf8(invocation.runtime()))
                                : 0;
          folly::dynamic request = folly::dynamic::object("url", convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path()))("destination", state->resolve(convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(1), invocation.path())).string())("uuid", convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(2), invocation.path()))("emitProgress", true)("resumeFrom", resume);

          if (options.isObject() && options.count("headers")) {
            request["headers"] = options["headers"];
          }
          request["md5"] = dynamicBool(options, "md5");

          return invokeService(invocation, "download", folly::dynamic::array(std::move(request)));
        }});
    module.function(serviceFunction("downloadResumablePauseAsync", "pause", 1, 1));
    module.function(serviceFunction("networkTaskCancelAsync", "cancel", 1, 1));
    auto upload = [state = state_](bool progress) {
      return FunctionDefinition{
          .name = progress ? "uploadTaskStartAsync" : "uploadAsync",
          .arity = progress ? 4U : 3U,
          .requiredArity = progress ? 4U : 3U,
          .async = true,
          .body = [state, progress](Invocation &invocation) {
            const size_t index = progress ? 3 : 2;
            const auto options = valueToDynamic(invocation, index);
            folly::dynamic request = folly::dynamic::object("url", convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path()))("source", state->resolve(convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(1), invocation.path()), false).string())("emitProgress", progress);

            if (progress) {
              request["uuid"] = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(2), invocation.path());
            }
            if (options.isObject()) {
              for (const auto *key : {
                       "headers", "httpMethod", "uploadType", "fieldName", "mimeType", "parameters"}) {
                if (options.count(key)) {
                  request[key] = options[key];
                }
              }
            }

            return invokeService(invocation, "upload", folly::dynamic::array(std::move(request)));
          }};
    };
    module.function(upload(false));
    module.function(upload(true));
    module.function(pickerFunction("requestDirectoryPermissionsAsync", "pickDirectoryPermission", "directoryUri", 1, state_, true));
    module.function(FunctionDefinition{
        .name = "readSAFDirectoryAsync", .arity = 1, .requiredArity = 1, .async = true, .body = [state = state_](Invocation &invocation) {
          const auto path = state->resolve(convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path()), false);
          requireDirectoryType(path);

          return invokeService(invocation, "readDirectory", folly::dynamic::array(path.string()));
        }});
    module.function(FunctionDefinition{
        .name = "makeSAFDirectoryAsync", .arity = 2, .requiredArity = 2, .async = true, .body = [state = state_](Invocation &invocation) {
          const auto path = state->resolve(convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path()), false);
          const auto name = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(1), invocation.path());
          requireDirectoryType(path);
          validateChildName(name);

          return invokeService(invocation, "makeSafDirectory", folly::dynamic::array(path.string(), name));
        }});
    module.function(FunctionDefinition{
        .name = "createSAFFileAsync", .arity = 3, .requiredArity = 3, .async = true, .body = [state = state_](Invocation &invocation) {
          const auto path = state->resolve(convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path()), false);
          const auto name = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(1), invocation.path());
          const auto mimeType = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(2), invocation.path());
          requireDirectoryType(path);
          validateChildName(name);

          return invokeService(invocation, "createSafFile", folly::dynamic::array(path.string(), name, mimeType));
        }});
    module.onDestroy([](RuntimeContext &context) { context.invokePlatformService(kService, "destroy"); });
    module.onActivityDestroy([](RuntimeContext &context) { context.invokePlatformService(kService, "destroy"); });

    return std::move(module).build();
  }

private:
  std::shared_ptr<FileSystemState> state_;
};

std::filesystem::path directoryFromCore(const std::shared_ptr<RuntimeContext> &context, const std::string &method) {
  const auto uri = convertFromJS<std::string>(context, context->callPlatformSync(method), method);
  return decodeFileUri(uri);
}

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoFileSystemProvider::modules(
    const std::shared_ptr<RuntimeContext> &context) {
  auto state = std::make_shared<FileSystemState>(
      directoryFromCore(context, "getDocumentsDirectory"),
      directoryFromCore(context, "getCacheDirectory"),
      context);
  return {
      std::make_shared<ModernFileSystemModule>(state),
      std::make_shared<LegacyFileSystemModule>(std::move(state)),
  };
}

}  // namespace expo::harmony::filesystem
