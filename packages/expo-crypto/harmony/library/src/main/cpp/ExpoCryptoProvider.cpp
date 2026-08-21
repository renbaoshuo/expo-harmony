#include "ExpoCryptoProvider.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <functional>
#include <iomanip>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include <CryptoArchitectureKit/crypto_digest.h>
#include <CryptoArchitectureKit/crypto_rand.h>
#include <CryptoArchitectureKit/crypto_sym_cipher.h>
#include <CryptoArchitectureKit/crypto_sym_key.h>

namespace jsi = facebook::jsi;

namespace expo::harmony::crypto {
namespace {

constexpr size_t kDefaultIvLength = 12;
constexpr size_t kDefaultGcmTagLength = 16;
constexpr size_t kMaximumIvLength = 128;
constexpr size_t kMaximumDigestLength = 64;
constexpr std::array<size_t, 7> kGcmTagLengths{4, 8, 12, 13, 14, 15, 16};

bool isGcmTagLength(size_t length) {
  return std::find(kGcmTagLengths.begin(), kGcmTagLengths.end(), length) != kGcmTagLengths.end();
}

class NativeCryptoExecutor final {
public:
  NativeCryptoExecutor() : worker_([this]() { run(); }) {}

  NativeCryptoExecutor(const NativeCryptoExecutor &) = delete;
  NativeCryptoExecutor &operator=(const NativeCryptoExecutor &) = delete;

  ~NativeCryptoExecutor() {
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
    {
      std::scoped_lock lock(mutex_);
      if (stopping_) {
        throw CodedError("ERR_CRYPTO_QUEUE_UNAVAILABLE", "The native crypto queue is shutting down.");
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

NativeCryptoExecutor &nativeCryptoExecutor() {
  static NativeCryptoExecutor executor;
  return executor;
}

void requireCryptoSuccess(
    OH_Crypto_ErrCode result,
    const char *code,
    const std::string &message) {
  if (result != CRYPTO_SUCCESS) {
    const char *name = "unknown error";
    switch (result) {
      case CRYPTO_INVALID_PARAMS:
        name = "invalid parameters";
        break;
      case CRYPTO_NOT_SUPPORTED:
        name = "not supported";
        break;
      case CRYPTO_MEMORY_ERROR:
        name = "memory error";
        break;
      case CRYPTO_PARAMETER_CHECK_FAILED:
        name = "parameter check failed";
        break;
      case CRYPTO_INVALID_CALL:
        name = "invalid call";
        break;
      case CRYPTO_OPERTION_ERROR:
        name = "operation error";
        break;
    }

    throw CodedError(
        code,
        message + " (Harmony crypto error: " + name + ", " + std::to_string(static_cast<int>(result)) + ").");
  }
}

struct DigestDeleter {
  void operator()(OH_CryptoDigest *value) const {
    if (value) {
      OH_DigestCrypto_Destroy(value);
    }
  }
};

struct RandomDeleter {
  void operator()(OH_CryptoRand *value) const {
    if (value) {
      OH_CryptoRand_Destroy(value);
    }
  }
};

struct KeyGeneratorDeleter {
  void operator()(OH_CryptoSymKeyGenerator *value) const {
    if (value) {
      OH_CryptoSymKeyGenerator_Destroy(value);
    }
  }
};

struct SymKeyDeleter {
  void operator()(OH_CryptoSymKey *value) const {
    if (value) {
      OH_CryptoSymKey_Destroy(value);
    }
  }
};

struct CipherParamsDeleter {
  void operator()(OH_CryptoSymCipherParams *value) const {
    if (value) {
      OH_CryptoSymCipherParams_Destroy(value);
    }
  }
};

struct CipherDeleter {
  void operator()(OH_CryptoSymCipher *value) const {
    if (value) {
      OH_CryptoSymCipher_Destroy(value);
    }
  }
};

using DigestPtr = std::unique_ptr<OH_CryptoDigest, DigestDeleter>;
using RandomPtr = std::unique_ptr<OH_CryptoRand, RandomDeleter>;
using KeyGeneratorPtr = std::unique_ptr<OH_CryptoSymKeyGenerator, KeyGeneratorDeleter>;
using SymKeyPtr = std::unique_ptr<OH_CryptoSymKey, SymKeyDeleter>;
using CipherParamsPtr = std::unique_ptr<OH_CryptoSymCipherParams, CipherParamsDeleter>;
using CipherPtr = std::unique_ptr<OH_CryptoSymCipher, CipherDeleter>;

class OwnedDataBlob final {
public:
  OwnedDataBlob() = default;
  OwnedDataBlob(const OwnedDataBlob &) = delete;
  OwnedDataBlob &operator=(const OwnedDataBlob &) = delete;

  ~OwnedDataBlob() {
    if (value_.data) {
      OH_Crypto_FreeDataBlob(&value_);
    }
  }

  Crypto_DataBlob *get() {
    return &value_;
  }

  std::vector<uint8_t> bytes() const {
    if (!value_.data || value_.len == 0) {
      return {};
    }

    return {value_.data, value_.data + value_.len};
  }

private:
  Crypto_DataBlob value_{nullptr, 0};
};

void secureErase(std::vector<uint8_t> &bytes) noexcept {
  volatile uint8_t *data = bytes.data();
  for (size_t index = 0; index < bytes.size(); ++index) {
    data[index] = 0;
  }
}

size_t checkedSize(double value, const std::string &label) {
  constexpr bool sizeExceedsDoublePrecision = std::numeric_limits<size_t>::digits > std::numeric_limits<double>::digits;
  const auto max = static_cast<double>(std::numeric_limits<size_t>::max());
  const bool tooLarge = sizeExceedsDoublePrecision ? value >= max : value > max;

  if (!std::isfinite(value) || std::trunc(value) != value || value < 0 || tooLarge) {
    throw CodedError("ERR_INVALID_ARGUMENT", label + " must be a non-negative integer.");
  }

  return static_cast<size_t>(value);
}

std::string constructorName(jsi::Runtime &runtime, const jsi::Object &object) {
  auto ctor = object.getProperty(runtime, "constructor");
  if (!ctor.isObject()) {
    return {};
  }

  auto name = ctor.getObject(runtime).getProperty(runtime, "name");

  return name.isString() ? name.getString(runtime).utf8(runtime) : std::string();
}

struct ViewRange final {
  uint8_t *data;
  size_t size;
  std::string kind;
};

ViewRange requireBufferView(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    const std::string &label,
    bool requireUint8 = false) {
  if (!value.isObject()) {
    throw CodedError("ERR_INVALID_ARGUMENT", label + " must be an ArrayBuffer or TypedArray.");
  }

  auto object = value.getObject(runtime);
  if (object.isArrayBuffer(runtime)) {
    if (requireUint8) {
      throw CodedError("ERR_INVALID_ARGUMENT", label + " must be a Uint8Array.");
    }

    auto buffer = object.getArrayBuffer(runtime);

    return {buffer.data(runtime), buffer.size(runtime), "ArrayBuffer"};
  }

  if (!expo::isTypedArray(runtime, object)) {
    throw CodedError("ERR_INVALID_ARGUMENT", label + " must be an ArrayBuffer or TypedArray.");
  }

  const auto kind = constructorName(runtime, object);
  if (requireUint8 && kind != "Uint8Array") {
    throw CodedError("ERR_INVALID_ARGUMENT", label + " must be a Uint8Array.");
  }

  auto bufferValue = object.getProperty(runtime, "buffer");
  auto offsetValue = object.getProperty(runtime, "byteOffset");
  auto lengthValue = object.getProperty(runtime, "byteLength");
  if (!bufferValue.isObject() || !bufferValue.getObject(runtime).isArrayBuffer(runtime) || !offsetValue.isNumber() || !lengthValue.isNumber()) {
    throw CodedError("ERR_INVALID_ARGUMENT", label + " has an invalid backing buffer.");
  }

  auto buffer = bufferValue.getObject(runtime).getArrayBuffer(runtime);
  const auto offset = checkedSize(offsetValue.getNumber(), label + ".byteOffset");
  const auto length = checkedSize(lengthValue.getNumber(), label + ".byteLength");
  if (offset > buffer.size(runtime) || length > buffer.size(runtime) - offset) {
    throw CodedError("ERR_INVALID_ARGUMENT", label + " is outside its backing buffer.");
  }

  return {buffer.data(runtime) + offset, length, kind};
}

std::vector<uint8_t> copyBufferSource(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    const std::string &label) {
  const auto view = requireBufferView(runtime, value, label);
  if (view.size == 0) {
    return {};
  }
  return {view.data, view.data + view.size};
}

std::vector<uint8_t> copyUint8Array(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    const std::string &label) {
  const auto view = requireBufferView(runtime, value, label, true);
  if (view.size == 0) {
    return {};
  }
  return {view.data, view.data + view.size};
}

bool isIntegerTypedArray(const std::string &name) {
  return name == "Int8Array" || name == "Uint8Array" || name == "Uint8ClampedArray" || name == "Int16Array" || name == "Uint16Array" || name == "Int32Array" || name == "Uint32Array";
}

void fillRandomView(jsi::Runtime &runtime, const jsi::Value &value) {
  const auto view = requireBufferView(runtime, value, "typedArray");

  if (!isIntegerTypedArray(view.kind)) {
    throw CodedError(
        "ERR_INVALID_ARGUMENT",
        "getRandomValues expects an integer-based TypedArray.");
  }
  if (view.size > static_cast<size_t>(std::numeric_limits<int>::max())) {
    throw CodedError("ERR_CRYPTO_RANDOM", "The requested random buffer is too large.");
  }
  if (view.size == 0) {
    return;
  }

  OH_CryptoRand *raw = nullptr;
  requireCryptoSuccess(
      OH_CryptoRand_Create(&raw),
      "ERR_CRYPTO_RANDOM",
      "Unable to create a secure random generator");
  RandomPtr random(raw);
  OwnedDataBlob out;

  requireCryptoSuccess(
      OH_CryptoRand_GenerateRandom(random.get(), static_cast<int>(view.size), out.get()),
      "ERR_CRYPTO_RANDOM",
      "Unable to generate secure random bytes");

  const auto bytes = out.bytes();
  if (bytes.size() != view.size) {
    throw CodedError("ERR_CRYPTO_RANDOM", "Harmony returned an incomplete random buffer.");
  }

  std::memcpy(view.data, bytes.data(), bytes.size());
}

std::vector<uint8_t> randomBytes(size_t size) {
  if (size > static_cast<size_t>(std::numeric_limits<int>::max())) {
    throw CodedError("ERR_CRYPTO_RANDOM", "The requested random buffer is too large.");
  }

  if (size == 0) {
    return {};
  }

  OH_CryptoRand *raw = nullptr;
  requireCryptoSuccess(
      OH_CryptoRand_Create(&raw),
      "ERR_CRYPTO_RANDOM",
      "Unable to create a secure random generator");
  RandomPtr random(raw);
  OwnedDataBlob out;

  requireCryptoSuccess(
      OH_CryptoRand_GenerateRandom(random.get(), static_cast<int>(size), out.get()),
      "ERR_CRYPTO_RANDOM",
      "Unable to generate secure random bytes");

  auto bytes = out.bytes();
  if (bytes.size() != size) {
    throw CodedError("ERR_CRYPTO_RANDOM", "Harmony returned an incomplete random buffer.");
  }

  return bytes;
}

std::string digestAlgorithmName(const std::string &algorithm) {
  if (algorithm == "SHA-1") {
    return "SHA1";
  }
  if (algorithm == "SHA-256") {
    return "SHA256";
  }
  if (algorithm == "SHA-384") {
    return "SHA384";
  }
  if (algorithm == "SHA-512") {
    return "SHA512";
  }
  if (algorithm == "MD5") {
    return "MD5";
  }

  throw CodedError("ERR_CRYPTO_DIGEST", "Unsupported digest algorithm '" + algorithm + "'.");
}

std::vector<uint8_t> digestBytes(
    const std::string &algorithm,
    const std::vector<uint8_t> &data) {
  OH_CryptoDigest *raw = nullptr;
  const auto native = digestAlgorithmName(algorithm);

  requireCryptoSuccess(
      OH_CryptoDigest_Create(native.c_str(), &raw),
      "ERR_CRYPTO_DIGEST",
      "Harmony does not support digest algorithm '" + algorithm + "'");
  DigestPtr digest(raw);

  if (!data.empty()) {
    Crypto_DataBlob input{const_cast<uint8_t *>(data.data()), data.size()};

    requireCryptoSuccess(
        OH_CryptoDigest_Update(digest.get(), &input),
        "ERR_CRYPTO_DIGEST",
        "Unable to update the '" + algorithm + "' digest");
  }

  OwnedDataBlob out;
  requireCryptoSuccess(
      OH_CryptoDigest_Final(digest.get(), out.get()),
      "ERR_CRYPTO_DIGEST",
      "Unable to finalize the '" + algorithm + "' digest");

  const auto length = OH_CryptoDigest_GetLength(digest.get());
  auto bytes = out.bytes();
  if (length == 0 || length > kMaximumDigestLength || bytes.size() != length) {
    throw CodedError("ERR_CRYPTO_DIGEST", "Harmony returned an invalid digest result.");
  }

  return bytes;
}

std::string hexEncode(const std::vector<uint8_t> &bytes) {
  std::ostringstream out;
  out << std::hex << std::setfill('0');
  for (const auto byte : bytes) {
    out << std::setw(2) << static_cast<int>(byte);
  }

  return out.str();
}

constexpr std::string_view kBase64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string base64Encode(const std::vector<uint8_t> &bytes) {
  std::string out;
  out.reserve(((bytes.size() + 2) / 3) * 4);
  for (size_t index = 0; index < bytes.size(); index += 3) {
    const uint32_t first = bytes[index];
    const uint32_t second = index + 1 < bytes.size() ? bytes[index + 1] : 0;
    const uint32_t third = index + 2 < bytes.size() ? bytes[index + 2] : 0;
    const uint32_t value = (first << 16) | (second << 8) | third;
    out.push_back(kBase64Alphabet[(value >> 18) & 0x3f]);
    out.push_back(kBase64Alphabet[(value >> 12) & 0x3f]);
    out.push_back(index + 1 < bytes.size() ? kBase64Alphabet[(value >> 6) & 0x3f] : '=');
    out.push_back(index + 2 < bytes.size() ? kBase64Alphabet[value & 0x3f] : '=');
  }

  return out;
}

std::vector<uint8_t> base64Decode(const std::string &text) {
  std::array<int, 256> lookup{};
  lookup.fill(-1);
  for (size_t index = 0; index < kBase64Alphabet.size(); ++index) {
    lookup[static_cast<unsigned char>(kBase64Alphabet[index])] = static_cast<int>(index);
  }

  std::vector<uint8_t> bytes;
  std::array<int, 4> block{};
  size_t count = 0;
  bool padded = false;
  bool finished = false;

  for (const unsigned char character : text) {
    if (character == ' ' || character == '\n' || character == '\r' || character == '\t') {
      continue;
    }

    if (character == '=') {
      if (finished || count < 2) {
        throw CodedError("ERR_CRYPTO_INVALID_BASE64", "Invalid base64 string.");
      }

      padded = true;
      block[count++] = -1;
    } else {
      if (padded || finished || lookup[character] < 0) {
        throw CodedError("ERR_CRYPTO_INVALID_BASE64", "Invalid base64 string.");
      }

      block[count++] = lookup[character];
    }

    if (count < block.size()) {
      continue;
    }

    if (block[0] < 0 || block[1] < 0) {
      throw CodedError("ERR_CRYPTO_INVALID_BASE64", "Invalid base64 string.");
    }

    bytes.push_back(static_cast<uint8_t>((block[0] << 2) | (block[1] >> 4)));
    if (block[2] < 0) {
      if (block[3] >= 0) {
        throw CodedError("ERR_CRYPTO_INVALID_BASE64", "Invalid base64 string.");
      }
    } else {
      bytes.push_back(static_cast<uint8_t>((block[1] << 4) | (block[2] >> 2)));
      if (block[3] >= 0) {
        bytes.push_back(static_cast<uint8_t>((block[2] << 6) | block[3]));
      }
    }

    finished = padded;
    padded = false;
    count = 0;
  }

  if (padded || count == 1) {
    throw CodedError("ERR_CRYPTO_INVALID_BASE64", "Invalid base64 string.");
  }

  if (count == 2) {
    bytes.push_back(static_cast<uint8_t>((block[0] << 2) | (block[1] >> 4)));
  } else if (count == 3) {
    bytes.push_back(static_cast<uint8_t>((block[0] << 2) | (block[1] >> 4)));
    bytes.push_back(static_cast<uint8_t>((block[1] << 4) | (block[2] >> 2)));
  }

  return bytes;
}

std::vector<uint8_t> hexDecode(std::string text) {
  if (text.starts_with("0x") || text.starts_with("0X")) {
    text.erase(0, 2);
  }

  if (text.size() % 2 != 0) {
    throw CodedError("ERR_CRYPTO_INVALID_KEY", "Invalid hexadecimal key string.");
  }

  auto nibble = [](char value) -> int {
    if (value >= '0' && value <= '9') {
      return value - '0';
    }
    if (value >= 'a' && value <= 'f') {
      return value - 'a' + 10;
    }
    if (value >= 'A' && value <= 'F') {
      return value - 'A' + 10;
    }
    return -1;
  };

  std::vector<uint8_t> bytes(text.size() / 2);
  for (size_t index = 0; index < bytes.size(); ++index) {
    const int high = nibble(text[index * 2]);
    const int low = nibble(text[index * 2 + 1]);
    if (high < 0 || low < 0) {
      throw CodedError("ERR_CRYPTO_INVALID_KEY", "Invalid hexadecimal key string.");
    }

    bytes[index] = static_cast<uint8_t>((high << 4) | low);
  }

  return bytes;
}

std::vector<uint8_t> binaryInput(
    jsi::Runtime &runtime,
    const jsi::Value &value,
    const std::string &label) {
  if (value.isString()) {
    return base64Decode(value.getString(runtime).utf8(runtime));
  }
  if (value.isObject() && value.getObject(runtime).isArrayBuffer(runtime)) {
    return copyBufferSource(runtime, value, label);
  }
  return copyUint8Array(runtime, value, label);
}

jsi::Value propertyOrUndefined(
    jsi::Runtime &runtime,
    const jsi::Object &object,
    const char *name) {
  return object.getProperty(runtime, name);
}

std::optional<jsi::Object> optionalOptions(
    Invocation &invocation,
    size_t index,
    const std::string &label) {
  if (index >= invocation.argumentCount() || invocation.argument(index).isUndefined() || invocation.argument(index).isNull()) {
    return std::nullopt;
  }
  if (!invocation.argument(index).isObject()) {
    throw CodedError("ERR_INVALID_ARGUMENT", label + " must be an object.");
  }
  return invocation.argument(index).getObject(invocation.runtime());
}

std::string stringOption(
    jsi::Runtime &runtime,
    const jsi::Object &options,
    const char *name,
    std::string fallback) {
  auto value = propertyOrUndefined(runtime, options, name);
  if (value.isUndefined() || value.isNull()) {
    return fallback;
  }
  if (!value.isString()) {
    throw CodedError("ERR_INVALID_ARGUMENT", std::string("options.") + name + " must be a string.");
  }
  return value.getString(runtime).utf8(runtime);
}

bool boolOption(
    jsi::Runtime &runtime,
    const jsi::Object &options,
    const char *name,
    bool fallback) {
  auto value = propertyOrUndefined(runtime, options, name);
  if (value.isUndefined() || value.isNull()) {
    return fallback;
  }
  if (!value.isBool()) {
    throw CodedError("ERR_INVALID_ARGUMENT", std::string("options.") + name + " must be a boolean.");
  }
  return value.getBool();
}

std::optional<size_t> sizeOption(
    jsi::Runtime &runtime,
    const jsi::Object &options,
    const char *name) {
  auto value = propertyOrUndefined(runtime, options, name);
  if (value.isUndefined() || value.isNull()) {
    return std::nullopt;
  }
  if (!value.isNumber()) {
    throw CodedError("ERR_INVALID_ARGUMENT", std::string("options.") + name + " must be a number.");
  }
  return checkedSize(value.getNumber(), std::string("options.") + name);
}

std::vector<uint8_t> optionalBinaryOption(
    jsi::Runtime &runtime,
    const jsi::Object &options,
    const char *name) {
  auto value = propertyOrUndefined(runtime, options, name);
  if (value.isUndefined() || value.isNull()) {
    return {};
  }

  return binaryInput(runtime, value, std::string("options.") + name);
}

class EncryptionKeyObject final : public NativeSharedObject {
public:
  explicit EncryptionKeyObject(std::vector<uint8_t> bytes)
      : bytes_(std::move(bytes)) {
    if (bytes_.size() != 16 && bytes_.size() != 24 && bytes_.size() != 32) {
      throw CodedError(
          "ERR_CRYPTO_INVALID_KEY",
          "Invalid AES key byte length '" + std::to_string(bytes_.size()) + "'.");
    }
  }

  ~EncryptionKeyObject() override {
    secureErase(bytes_);
  }

  const std::vector<uint8_t> &bytes() const noexcept {
    return bytes_;
  }

  size_t bitSize() const noexcept {
    return bytes_.size() * 8;
  }

  size_t getAdditionalMemoryPressure() const noexcept override {
    return bytes_.size();
  }

private:
  std::vector<uint8_t> bytes_;
};

class SealedDataObject final : public NativeSharedObject {
public:
  SealedDataObject(
      std::vector<uint8_t> iv,
      std::vector<uint8_t> ciphertext,
      std::vector<uint8_t> tag)
      : iv_(std::move(iv)),
        ciphertext_(std::move(ciphertext)),
        tag_(std::move(tag)) {
    if (iv_.empty() || iv_.size() > kMaximumIvLength || !isGcmTagLength(tag_.size())) {
      throw CodedError("ERR_CRYPTO_INVALID_SEALED_DATA", "Invalid SealedData configuration.");
    }
  }

  static std::shared_ptr<SealedDataObject> fromCombined(
      std::vector<uint8_t> combined,
      size_t ivLength,
      size_t tagLength) {
    if (ivLength == 0 || !isGcmTagLength(tagLength) || combined.size() < ivLength || combined.size() - ivLength < tagLength) {
      throw CodedError("ERR_CRYPTO_INVALID_SEALED_DATA", "Invalid SealedData configuration.");
    }

    auto ivEnd = combined.begin() + static_cast<std::ptrdiff_t>(ivLength);
    auto tagIt = combined.end() - static_cast<std::ptrdiff_t>(tagLength);

    return std::make_shared<SealedDataObject>(
        std::vector<uint8_t>(combined.begin(), ivEnd),
        std::vector<uint8_t>(ivEnd, tagIt),
        std::vector<uint8_t>(tagIt, combined.end()));
  }

  const std::vector<uint8_t> &iv() const noexcept {
    return iv_;
  }

  const std::vector<uint8_t> &ciphertext() const noexcept {
    return ciphertext_;
  }

  const std::vector<uint8_t> &tag() const noexcept {
    return tag_;
  }

  std::vector<uint8_t> taggedCiphertext() const {
    auto bytes = ciphertext_;
    bytes.insert(bytes.end(), tag_.begin(), tag_.end());

    return bytes;
  }

  std::vector<uint8_t> combined() const {
    auto bytes = iv_;
    bytes.insert(bytes.end(), ciphertext_.begin(), ciphertext_.end());
    bytes.insert(bytes.end(), tag_.begin(), tag_.end());

    return bytes;
  }

  size_t combinedSize() const noexcept {
    return iv_.size() + ciphertext_.size() + tag_.size();
  }

  size_t getAdditionalMemoryPressure() const noexcept override {
    return iv_.size() + ciphertext_.size() + tag_.size();
  }

private:
  std::vector<uint8_t> iv_;
  std::vector<uint8_t> ciphertext_;
  std::vector<uint8_t> tag_;
};

std::string aesAlgorithm(size_t bitSize) {
  return "AES" + std::to_string(bitSize);
}

SymKeyPtr importSymmetricKey(const EncryptionKeyObject &key) {
  OH_CryptoSymKeyGenerator *rawGenerator = nullptr;
  const auto algorithm = aesAlgorithm(key.bitSize());

  requireCryptoSuccess(
      OH_CryptoSymKeyGenerator_Create(algorithm.c_str(), &rawGenerator),
      "ERR_CRYPTO_AES_KEY",
      "Unable to create the '" + algorithm + "' key converter");
  KeyGeneratorPtr generator(rawGenerator);

  OH_CryptoSymKey *rawKey = nullptr;
  Crypto_DataBlob keyData{
      const_cast<uint8_t *>(key.bytes().data()),
      key.bytes().size()};
  requireCryptoSuccess(
      OH_CryptoSymKeyGenerator_Convert(generator.get(), &keyData, &rawKey),
      "ERR_CRYPTO_AES_KEY",
      "Unable to import the AES key");

  return SymKeyPtr(rawKey);
}

CipherParamsPtr createGcmParams(
    const std::vector<uint8_t> &iv,
    const std::vector<uint8_t> &aad,
    const std::vector<uint8_t> &tag) {
  OH_CryptoSymCipherParams *raw = nullptr;
  requireCryptoSuccess(
      OH_CryptoSymCipherParams_Create(&raw),
      "ERR_CRYPTO_AES",
      "Unable to create AES-GCM parameters");
  CipherParamsPtr params(raw);

  Crypto_DataBlob ivData{const_cast<uint8_t *>(iv.data()), iv.size()};
  requireCryptoSuccess(
      OH_CryptoSymCipherParams_SetParam(params.get(), CRYPTO_IV_DATABLOB, &ivData),
      "ERR_CRYPTO_AES",
      "Unable to set the AES-GCM nonce");

  if (!aad.empty()) {
    Crypto_DataBlob aadData{const_cast<uint8_t *>(aad.data()), aad.size()};

    requireCryptoSuccess(
        OH_CryptoSymCipherParams_SetParam(params.get(), CRYPTO_AAD_DATABLOB, &aadData),
        "ERR_CRYPTO_AES",
        "Unable to set AES-GCM additional authenticated data");
  }

  Crypto_DataBlob tagData{const_cast<uint8_t *>(tag.data()), tag.size()};
  requireCryptoSuccess(
      OH_CryptoSymCipherParams_SetParam(params.get(), CRYPTO_TAG_DATABLOB, &tagData),
      "ERR_CRYPTO_AES",
      "Unable to set the AES-GCM authentication tag");

  return params;
}

CipherPtr createGcmCipher(size_t bitSize) {
  OH_CryptoSymCipher *raw = nullptr;
  const auto transformation = aesAlgorithm(bitSize) + "|GCM|PKCS7";

  requireCryptoSuccess(
      OH_CryptoSymCipher_Create(transformation.c_str(), &raw),
      "ERR_CRYPTO_AES",
      "Unable to create the '" + transformation + "' cipher");

  return CipherPtr(raw);
}

std::shared_ptr<SealedDataObject> encryptAesGcm(
    const std::vector<uint8_t> &plaintext,
    const EncryptionKeyObject &key,
    std::vector<uint8_t> iv,
    const std::vector<uint8_t> &aad,
    size_t tagLength) {
  std::vector<uint8_t> tagBuffer(tagLength);
  auto nativeKey = importSymmetricKey(key);
  auto params = createGcmParams(iv, aad, tagBuffer);
  auto cipher = createGcmCipher(key.bitSize());

  requireCryptoSuccess(
      OH_CryptoSymCipher_Init(
          cipher.get(), CRYPTO_ENCRYPT_MODE, nativeKey.get(), params.get()),
      "ERR_CRYPTO_ENCRYPT",
      "Unable to initialize AES-GCM encryption");

  OwnedDataBlob updated;
  if (!plaintext.empty() || !aad.empty()) {
    uint8_t emptyByte = 0;
    Crypto_DataBlob input{
        plaintext.empty() ? &emptyByte : const_cast<uint8_t *>(plaintext.data()),
        plaintext.size()};

    requireCryptoSuccess(
        OH_CryptoSymCipher_Update(cipher.get(), &input, updated.get()),
        "ERR_CRYPTO_ENCRYPT",
        "AES-GCM encryption failed while processing plaintext");
  }

  OwnedDataBlob finalized;
  requireCryptoSuccess(
      OH_CryptoSymCipher_Final(cipher.get(), nullptr, finalized.get()),
      "ERR_CRYPTO_ENCRYPT",
      "AES-GCM encryption failed while producing the authentication tag");

  auto ciphertext = updated.bytes();
  auto tail = finalized.bytes();
  if (tail.size() < tagLength) {
    throw CodedError("ERR_CRYPTO_ENCRYPT", "Harmony returned an invalid AES-GCM authentication tag.");
  }

  const auto tagIt = tail.end() - static_cast<std::ptrdiff_t>(tagLength);
  ciphertext.insert(ciphertext.end(), tail.begin(), tagIt);
  std::vector<uint8_t> tag(tagIt, tail.end());

  return std::make_shared<SealedDataObject>(
      std::move(iv), std::move(ciphertext), std::move(tag));
}

std::vector<uint8_t> decryptAesGcm(
    const SealedDataObject &sealed,
    const EncryptionKeyObject &key,
    const std::vector<uint8_t> &aad) {
  if (!isGcmTagLength(sealed.tag().size())) {
    throw CodedError(
        "ERR_CRYPTO_UNSUPPORTED_TAG_LENGTH",
        "AES-GCM authentication tag length must be 4, 8, or 12...16 bytes; received "
            + std::to_string(sealed.tag().size()) + " bytes.");
  }

  auto nativeKey = importSymmetricKey(key);
  auto params = createGcmParams(sealed.iv(), aad, sealed.tag());
  auto cipher = createGcmCipher(key.bitSize());

  requireCryptoSuccess(
      OH_CryptoSymCipher_Init(
          cipher.get(), CRYPTO_DECRYPT_MODE, nativeKey.get(), params.get()),
      "ERR_CRYPTO_DECRYPT",
      "Unable to initialize AES-GCM decryption");

  OwnedDataBlob updated;
  if (!sealed.ciphertext().empty() || !aad.empty()) {
    uint8_t emptyByte = 0;
    Crypto_DataBlob input{
        sealed.ciphertext().empty()
            ? &emptyByte
            : const_cast<uint8_t *>(sealed.ciphertext().data()),
        sealed.ciphertext().size()};

    requireCryptoSuccess(
        OH_CryptoSymCipher_Update(cipher.get(), &input, updated.get()),
        "ERR_CRYPTO_DECRYPT",
        "AES-GCM decryption failed while processing ciphertext");
  }

  OwnedDataBlob finalized;
  requireCryptoSuccess(
      OH_CryptoSymCipher_Final(cipher.get(), nullptr, finalized.get()),
      "ERR_CRYPTO_DECRYPT",
      "AES-GCM authentication failed");

  auto plaintext = updated.bytes();
  auto tail = finalized.bytes();
  plaintext.insert(plaintext.end(), tail.begin(), tail.end());

  return plaintext;
}

jsi::Value formatBytes(
    Invocation &invocation,
    const std::vector<uint8_t> &bytes,
    const std::string &encoding) {
  if (encoding == "base64") {
    return jsi::String::createFromUtf8(invocation.runtime(), base64Encode(bytes));
  }
  if (encoding != "bytes") {
    throw CodedError("ERR_INVALID_ARGUMENT", "Unsupported binary output encoding '" + encoding + "'.");
  }
  return convertToJS(invocation.sharedContext(), bytes);
}

std::string randomUuid() {
  auto bytes = randomBytes(16);
  bytes[6] = static_cast<uint8_t>((bytes[6] & 0x0f) | 0x40);
  bytes[8] = static_cast<uint8_t>((bytes[8] & 0x3f) | 0x80);

  std::ostringstream out;
  out << std::hex << std::setfill('0');
  for (size_t index = 0; index < bytes.size(); ++index) {
    if (index == 4 || index == 6 || index == 8 || index == 10) {
      out << '-';
    }
    out << std::setw(2) << static_cast<int>(bytes[index]);
  }

  return out.str();
}

std::shared_ptr<EncryptionKeyObject> requireKey(
    Invocation &invocation,
    size_t index) {
  return convertFromJS<std::shared_ptr<EncryptionKeyObject>>(
      invocation.sharedContext(),
      invocation.argument(index),
      invocation.path() + " argument " + std::to_string(index));
}

std::shared_ptr<SealedDataObject> requireSealedData(
    Invocation &invocation,
    size_t index) {
  return convertFromJS<std::shared_ptr<SealedDataObject>>(
      invocation.sharedContext(),
      invocation.argument(index),
      invocation.path() + " argument " + std::to_string(index));
}

std::shared_ptr<EncryptionKeyObject> keyOwner(
    const std::shared_ptr<NativeSharedObject> &object) {
  auto owner = std::dynamic_pointer_cast<EncryptionKeyObject>(object);
  if (!owner) {
    throw CodedError("ERR_SHARED_OBJECT_TYPE", "Invalid EncryptionKey receiver.");
  }

  return owner;
}

std::shared_ptr<SealedDataObject> sealedOwner(
    const std::shared_ptr<NativeSharedObject> &object) {
  auto owner = std::dynamic_pointer_cast<SealedDataObject>(object);
  if (!owner) {
    throw CodedError("ERR_SHARED_OBJECT_TYPE", "Invalid SealedData receiver.");
  }

  return owner;
}

jsi::Value digestString(Invocation &invocation) {
  const auto algorithm = convertFromJS<std::string>(
      invocation.sharedContext(), invocation.argument(0), invocation.path());
  const auto text = convertFromJS<std::string>(
      invocation.sharedContext(), invocation.argument(1), invocation.path());

  std::string encoding = "hex";
  if (auto options = optionalOptions(invocation, 2, "options")) {
    encoding = stringOption(invocation.runtime(), *options, "encoding", "hex");
  }

  if (encoding != "hex" && encoding != "base64") {
    throw CodedError("ERR_CRYPTO_DIGEST", "Unsupported digest encoding '" + encoding + "'.");
  }

  const std::vector<uint8_t> data(text.begin(), text.end());
  const auto digest = digestBytes(algorithm, data);

  if (encoding == "hex") {
    return jsi::String::createFromUtf8(invocation.runtime(), hexEncode(digest));
  }
  if (encoding == "base64") {
    return jsi::String::createFromUtf8(invocation.runtime(), base64Encode(digest));
  }

  throw CodedError("ERR_CRYPTO_DIGEST", "Unsupported digest encoding '" + encoding + "'.");
}

class ExpoCryptoModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleDefinitionBuilder module("ExpoCrypto");

    module.function(FunctionDefinition{
        .name = "getRandomValues",
        .arity = 1,
        .requiredArity = 1,
        .body = [](Invocation &invocation) {
          fillRandomView(invocation.runtime(), invocation.argument(0));
          return jsi::Value::undefined();
        }});

    module.function(FunctionDefinition{
        .name = "randomUUID",
        .arity = 0,
        .requiredArity = 0,
        .body = [](Invocation &invocation) {
          return jsi::String::createFromUtf8(invocation.runtime(), randomUuid());
        }});

    module.function(FunctionDefinition{
        .name = "digestString",
        .arity = 3,
        .requiredArity = 2,
        .body = [](Invocation &invocation) {
          return digestString(invocation);
        }});

    module.asyncFunction(FunctionDefinition{
        .name = "digestStringAsync",
        .arity = 3,
        .requiredArity = 2,
        .asyncBody = [](Invocation &invocation, const std::shared_ptr<Promise> &promise) {
          const auto algorithm = convertFromJS<std::string>(
              invocation.sharedContext(), invocation.argument(0), invocation.path());
          const auto text = convertFromJS<std::string>(
              invocation.sharedContext(), invocation.argument(1), invocation.path());
          std::string encoding = "hex";
          if (auto options = optionalOptions(invocation, 2, "options")) {
            encoding = stringOption(invocation.runtime(), *options, "encoding", "hex");
          }
          if (encoding != "hex" && encoding != "base64") {
            throw CodedError("ERR_CRYPTO_DIGEST", "Unsupported digest encoding '" + encoding + "'.");
          }

          nativeCryptoExecutor().schedule(
              [algorithm, text, encoding, promise]() {
                try {
                  promise->cancellationToken()->throwIfCancellationRequested();
                  const std::vector<uint8_t> data(text.begin(), text.end());
                  const auto digest = digestBytes(algorithm, data);
                  auto result = std::make_shared<std::string>(
                      encoding == "hex" ? hexEncode(digest) : base64Encode(digest));
                  promise->cancellationToken()->throwIfCancellationRequested();
                  promise->resolve([result = std::move(result)](jsi::Runtime &runtime) {
                    return jsi::Value(jsi::String::createFromUtf8(runtime, *result));
                  });
                } catch (const CodedError &error) {
                  promise->reject(error);
                } catch (const std::exception &error) {
                  promise->reject("ERR_CRYPTO_DIGEST", error.what());
                } catch (...) {
                  promise->reject("ERR_CRYPTO_DIGEST", "The digest operation failed.");
                }
              });
        }});

    module.function(FunctionDefinition{
        .name = "digest",
        .arity = 3,
        .requiredArity = 3,
        .body = [](Invocation &invocation) {
          const auto algorithm = convertFromJS<std::string>(
              invocation.sharedContext(), invocation.argument(0), invocation.path());
          auto out = requireBufferView(invocation.runtime(), invocation.argument(1), "output");
          const auto data = copyBufferSource(invocation.runtime(), invocation.argument(2), "data");

          const auto digest = digestBytes(algorithm, data);
          const auto size = std::min(out.size, digest.size());

          if (size > 0) {
            std::memcpy(out.data, digest.data(), size);
          }

          return jsi::Value::undefined();
        }});

    return std::move(module).build();
  }
};

class ExpoCryptoAesModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleDefinitionBuilder module("ExpoCryptoAES");

    module.asyncFunction(FunctionDefinition{
        .name = "encryptAsync",
        .arity = 3,
        .requiredArity = 2,
        .asyncBody = [](Invocation &invocation, const std::shared_ptr<Promise> &promise) {
          auto plaintext = binaryInput(invocation.runtime(), invocation.argument(0), "plaintext");
          auto key = requireKey(invocation, 1);

          std::optional<std::vector<uint8_t>> iv;
          size_t ivLength = kDefaultIvLength;
          size_t tagLength = kDefaultGcmTagLength;
          std::vector<uint8_t> aad;

          if (auto options = optionalOptions(invocation, 2, "options")) {
            tagLength = sizeOption(invocation.runtime(), *options, "tagLength")
                            .value_or(tagLength);
            if (!isGcmTagLength(tagLength)) {
              throw CodedError(
                  "ERR_CRYPTO_UNSUPPORTED_TAG_LENGTH",
                  "AES-GCM authentication tag length must be 4, 8, or 12...16 bytes; received "
                      + std::to_string(tagLength) + " bytes.");
            }

            auto nonce = propertyOrUndefined(invocation.runtime(), *options, "nonce");
            if (nonce.isNumber()) {
              ivLength = checkedSize(nonce.getNumber(), "options.nonce");
              if (ivLength == 0 || ivLength > kMaximumIvLength) {
                throw CodedError("ERR_CRYPTO_INVALID_NONCE", "AES-GCM nonce length must be in the range 1...128 on HarmonyOS.");
              }
            } else if (!nonce.isUndefined() && !nonce.isNull()) {
              iv = binaryInput(invocation.runtime(), nonce, "options.nonce");
            }

            aad = optionalBinaryOption(invocation.runtime(), *options, "additionalData");
          }

          if (iv && (iv->empty() || iv->size() > kMaximumIvLength)) {
            throw CodedError("ERR_CRYPTO_INVALID_NONCE", "AES-GCM nonce length must be in the range 1...128 on HarmonyOS.");
          }

          auto context = invocation.sharedContext();
          nativeCryptoExecutor().schedule(
              [plaintext = std::move(plaintext), key = std::move(key), iv = std::move(iv), ivLength, aad = std::move(aad), tagLength, context, promise]() mutable {
                try {
                  promise->cancellationToken()->throwIfCancellationRequested();
                  auto nonce = iv ? std::move(*iv) : randomBytes(ivLength);
                  auto result = encryptAesGcm(plaintext, *key, std::move(nonce), aad, tagLength);
                  promise->cancellationToken()->throwIfCancellationRequested();
                  promise->resolve([context, result = std::move(result)](jsi::Runtime &) {
                    return convertToJS(context, result);
                  });
                } catch (const CodedError &error) {
                  promise->reject(error);
                } catch (const std::exception &error) {
                  promise->reject("ERR_CRYPTO_ENCRYPT", error.what());
                } catch (...) {
                  promise->reject("ERR_CRYPTO_ENCRYPT", "AES-GCM encryption failed.");
                }
              });
        }});

    module.asyncFunction(FunctionDefinition{
        .name = "decryptAsync",
        .arity = 3,
        .requiredArity = 2,
        .asyncBody = [](Invocation &invocation, const std::shared_ptr<Promise> &promise) {
          auto sealed = requireSealedData(invocation, 0);
          auto key = requireKey(invocation, 1);

          std::string encoding = "bytes";
          std::vector<uint8_t> aad;

          if (auto options = optionalOptions(invocation, 2, "options")) {
            encoding = stringOption(invocation.runtime(), *options, "output", "bytes");
            aad = optionalBinaryOption(invocation.runtime(), *options, "additionalData");
          }
          if (encoding != "bytes" && encoding != "base64") {
            throw CodedError("ERR_INVALID_ARGUMENT", "Unsupported binary output encoding '" + encoding + "'.");
          }

          auto context = invocation.sharedContext();
          nativeCryptoExecutor().schedule(
              [sealed = std::move(sealed), key = std::move(key), aad = std::move(aad), encoding, context, promise]() mutable {
                try {
                  promise->cancellationToken()->throwIfCancellationRequested();
                  auto plaintext = decryptAesGcm(*sealed, *key, aad);
                  promise->cancellationToken()->throwIfCancellationRequested();
                  if (encoding == "base64") {
                    auto result = std::make_shared<std::string>(base64Encode(plaintext));
                    promise->resolve([result = std::move(result)](jsi::Runtime &runtime) {
                      return jsi::Value(jsi::String::createFromUtf8(runtime, *result));
                    });
                  } else {
                    auto result = std::make_shared<std::vector<uint8_t>>(std::move(plaintext));
                    promise->resolve([context, result = std::move(result)](jsi::Runtime &) {
                      return convertToJS(context, *result);
                    });
                  }
                } catch (const CodedError &error) {
                  promise->reject(error);
                } catch (const std::exception &error) {
                  promise->reject("ERR_CRYPTO_DECRYPT", error.what());
                } catch (...) {
                  promise->reject("ERR_CRYPTO_DECRYPT", "AES-GCM decryption failed.");
                }
              });
        }});

    ClassDefinitionBuilder<EncryptionKeyObject> key("EncryptionKey");
    key.constructor<>([]() -> std::shared_ptr<EncryptionKeyObject> {
      throw CodedError("ERR_INVALID_ARGUMENT", "EncryptionKey constructor cannot be used directly.");
    });
    key.staticFunction(FunctionDefinition{
        .name = "generate",
        .arity = 1,
        .requiredArity = 0,
        .async = true,
        .body = [](Invocation &invocation) {
          size_t size = 256;

          if (invocation.argumentCount() > 0 && !invocation.argument(0).isUndefined() && !invocation.argument(0).isNull()) {
            if (!invocation.argument(0).isNumber()) {
              throw CodedError("ERR_CRYPTO_INVALID_KEY", "AES key size must be 128, 192, or 256 bits.");
            }

            size = checkedSize(invocation.argument(0).getNumber(), "size");
          }

          if (size != 128 && size != 192 && size != 256) {
            throw CodedError("ERR_CRYPTO_INVALID_KEY", "AES key size must be 128, 192, or 256 bits.");
          }

          return convertToJS(
              invocation.sharedContext(),
              std::make_shared<EncryptionKeyObject>(randomBytes(size / 8)));
        }});
    key.staticFunction(FunctionDefinition{
        .name = "import",
        .arity = 2,
        .requiredArity = 1,
        .async = true,
        .body = [](Invocation &invocation) {
          std::vector<uint8_t> bytes;
          if (invocation.argument(0).isString()) {
            if (invocation.argumentCount() < 2 || !invocation.argument(1).isString()) {
              throw CodedError("ERR_CRYPTO_INVALID_KEY", "Encoding must be provided for string key input.");
            }

            const auto text = invocation.argument(0).getString(invocation.runtime()).utf8(invocation.runtime());
            const auto encoding = invocation.argument(1).getString(invocation.runtime()).utf8(invocation.runtime());

            if (encoding == "hex") {
              bytes = hexDecode(text);
            } else if (encoding == "base64") {
              bytes = base64Decode(text);
            } else {
              throw CodedError("ERR_CRYPTO_INVALID_KEY", "Key encoding must be 'hex' or 'base64'.");
            }
          } else {
            bytes = copyUint8Array(invocation.runtime(), invocation.argument(0), "key");
          }

          return convertToJS(
              invocation.sharedContext(),
              std::make_shared<EncryptionKeyObject>(std::move(bytes)));
        }});
    key.function(SharedObjectFunctionDefinition{
        .name = "bytes",
        .arity = 0,
        .requiredArity = 0,
        .async = true,
        .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          return convertToJS(invocation.sharedContext(), keyOwner(object)->bytes());
        }});
    key.function(SharedObjectFunctionDefinition{
        .name = "encoded",
        .arity = 1,
        .requiredArity = 1,
        .async = true,
        .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          const auto encoding = convertFromJS<std::string>(
              invocation.sharedContext(), invocation.argument(0), invocation.path());
          const auto &bytes = keyOwner(object)->bytes();

          if (encoding == "hex") {
            return jsi::Value(jsi::String::createFromUtf8(invocation.runtime(), hexEncode(bytes)));
          }
          if (encoding == "base64") {
            return jsi::Value(jsi::String::createFromUtf8(invocation.runtime(), base64Encode(bytes)));
          }

          throw CodedError("ERR_CRYPTO_INVALID_KEY", "Key encoding must be 'hex' or 'base64'.");
        }});
    key.property(SharedObjectPropertyDefinition{
        .name = "size",
        .getter = [](Invocation &, const std::shared_ptr<NativeSharedObject> &object) {
          return jsi::Value(static_cast<double>(keyOwner(object)->bitSize()));
        }});
    module.klass(std::move(key).build());

    ClassDefinitionBuilder<SealedDataObject> sealed("SealedData");
    sealed.constructor<>([]() -> std::shared_ptr<SealedDataObject> {
      throw CodedError("ERR_INVALID_ARGUMENT", "SealedData constructor cannot be used directly.");
    });
    sealed.staticFunction(FunctionDefinition{
        .name = "fromCombined",
        .arity = 2,
        .requiredArity = 1,
        .body = [](Invocation &invocation) {
          auto combined = binaryInput(invocation.runtime(), invocation.argument(0), "combined");

          size_t ivLength = kDefaultIvLength;
          size_t tagLength = kDefaultGcmTagLength;

          if (auto config = optionalOptions(invocation, 1, "config")) {
            ivLength = sizeOption(invocation.runtime(), *config, "ivLength").value_or(ivLength);
            tagLength = sizeOption(invocation.runtime(), *config, "tagLength").value_or(tagLength);
          }

          return convertToJS(
              invocation.sharedContext(),
              SealedDataObject::fromCombined(std::move(combined), ivLength, tagLength));
        }});
    sealed.staticFunction(FunctionDefinition{
        .name = "fromParts",
        .arity = 3,
        .requiredArity = 2,
        .body = [](Invocation &invocation) {
          auto iv = binaryInput(invocation.runtime(), invocation.argument(0), "iv");
          auto ciphertext = binaryInput(invocation.runtime(), invocation.argument(1), "ciphertext");

          if (invocation.argumentCount() >= 3 && !invocation.argument(2).isUndefined() && !invocation.argument(2).isNull() && !invocation.argument(2).isNumber()) {
            auto tag = binaryInput(invocation.runtime(), invocation.argument(2), "tag");

            return convertToJS(
                invocation.sharedContext(),
                std::make_shared<SealedDataObject>(
                    std::move(iv), std::move(ciphertext), std::move(tag)));
          }

          size_t tagLength = kDefaultGcmTagLength;
          if (invocation.argumentCount() >= 3 && invocation.argument(2).isNumber()) {
            tagLength = checkedSize(invocation.argument(2).getNumber(), "tagLength");
          }

          if (!isGcmTagLength(tagLength) || ciphertext.size() < tagLength) {
            throw CodedError("ERR_CRYPTO_INVALID_SEALED_DATA", "Invalid SealedData tag length.");
          }

          auto tagIt = ciphertext.end() - static_cast<std::ptrdiff_t>(tagLength);
          std::vector<uint8_t> tag(tagIt, ciphertext.end());
          ciphertext.erase(tagIt, ciphertext.end());

          return convertToJS(
              invocation.sharedContext(),
              std::make_shared<SealedDataObject>(
                  std::move(iv), std::move(ciphertext), std::move(tag)));
        }});
    sealed.function(SharedObjectFunctionDefinition{
        .name = "iv",
        .arity = 1,
        .requiredArity = 0,
        .async = true,
        .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          std::string encoding = "bytes";
          if (invocation.argumentCount() > 0 && !invocation.argument(0).isUndefined() && !invocation.argument(0).isNull()) {
            encoding = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
          }
          return formatBytes(invocation, sealedOwner(object)->iv(), encoding);
        }});
    sealed.function(SharedObjectFunctionDefinition{
        .name = "tag",
        .arity = 1,
        .requiredArity = 0,
        .async = true,
        .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          std::string encoding = "bytes";
          if (invocation.argumentCount() > 0 && !invocation.argument(0).isUndefined() && !invocation.argument(0).isNull()) {
            encoding = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
          }
          return formatBytes(invocation, sealedOwner(object)->tag(), encoding);
        }});
    sealed.function(SharedObjectFunctionDefinition{
        .name = "combined",
        .arity = 1,
        .requiredArity = 0,
        .async = true,
        .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          std::string encoding = "bytes";
          if (invocation.argumentCount() > 0 && !invocation.argument(0).isUndefined() && !invocation.argument(0).isNull()) {
            encoding = convertFromJS<std::string>(invocation.sharedContext(), invocation.argument(0), invocation.path());
          }
          return formatBytes(invocation, sealedOwner(object)->combined(), encoding);
        }});
    sealed.function(SharedObjectFunctionDefinition{
        .name = "ciphertext",
        .arity = 1,
        .requiredArity = 0,
        .async = true,
        .body = [](Invocation &invocation, const std::shared_ptr<NativeSharedObject> &object) {
          bool includeTag = false;
          std::string encoding = "bytes";

          if (auto options = optionalOptions(invocation, 0, "options")) {
            includeTag = boolOption(invocation.runtime(), *options, "includeTag", false);
            encoding = stringOption(invocation.runtime(), *options, "encoding", "bytes");
          }

          auto owner = sealedOwner(object);

          return formatBytes(
              invocation,
              includeTag ? owner->taggedCiphertext() : owner->ciphertext(),
              encoding);
        }});
    sealed.property(SharedObjectPropertyDefinition{
        .name = "combinedSize",
        .getter = [](Invocation &, const std::shared_ptr<NativeSharedObject> &object) {
          return jsi::Value(static_cast<double>(sealedOwner(object)->combinedSize()));
        }});
    sealed.property(SharedObjectPropertyDefinition{
        .name = "ivSize",
        .getter = [](Invocation &, const std::shared_ptr<NativeSharedObject> &object) {
          return jsi::Value(static_cast<double>(sealedOwner(object)->iv().size()));
        }});
    sealed.property(SharedObjectPropertyDefinition{
        .name = "tagSize",
        .getter = [](Invocation &, const std::shared_ptr<NativeSharedObject> &object) {
          return jsi::Value(static_cast<double>(sealedOwner(object)->tag().size()));
        }});
    module.klass(std::move(sealed).build());

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoCryptoProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {
      std::make_shared<ExpoCryptoModule>(),
      std::make_shared<ExpoCryptoAesModule>(),
  };
}

}  // namespace expo::harmony::crypto
