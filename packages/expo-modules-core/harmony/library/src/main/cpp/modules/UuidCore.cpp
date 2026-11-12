/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "modules/UuidCore.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iomanip>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <vector>

#include <CryptoArchitectureKit/crypto_digest.h>

#include "errors/CodedError.h"

namespace expo::harmony {

namespace {

uint8_t parseHex(char digit) {
  if (digit >= '0' && digit <= '9') {
    return digit - '0';
  }
  if (digit >= 'a' && digit <= 'f') {
    return digit - 'a' + 10;
  }
  if (digit >= 'A' && digit <= 'F') {
    return digit - 'A' + 10;
  }

  throw std::invalid_argument("UUID namespace contains a non-hex character");
}

std::array<uint8_t, 16> parseUuid(const std::string &value) {
  constexpr std::array<size_t, 4> separators{8, 13, 18, 23};
  if (value.size() != 36 || std::any_of(separators.begin(), separators.end(), [&value](size_t index) { return value[index] != '-'; })) {
    throw std::invalid_argument("UUID namespace does not use the 8-4-4-4-12 format");
  }

  std::string hex;
  hex.reserve(32);
  for (size_t index = 0; index < value.size(); ++index) {
    if (std::find(separators.begin(), separators.end(), index) == separators.end()) {
      hex.push_back(value[index]);
    }
  }

  std::array<uint8_t, 16> result{};
  for (size_t index = 0; index < result.size(); ++index) {
    result[index] = static_cast<uint8_t>(
        (parseHex(hex[index * 2]) << 4U) | parseHex(hex[index * 2 + 1]));
  }

  return result;
}

}  // namespace

std::string formatUuid(const std::array<uint8_t, 16> &bytes) {
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (size_t index = 0; index < bytes.size(); ++index) {
    if (index == 4 || index == 6 || index == 8 || index == 10) {
      output << '-';
    }
    output << std::setw(2) << static_cast<unsigned>(bytes[index]);
  }

  return output.str();
}

void applyUuidVersionAndVariant(std::array<uint8_t, 16> &bytes, uint8_t version) {
  if (version > 0x0fU) {
    throw std::invalid_argument("UUID version must fit in four bits");
  }

  bytes[6] = static_cast<uint8_t>((bytes[6] & 0x0fU) | (version << 4U));
  bytes[8] = static_cast<uint8_t>((bytes[8] & 0x3fU) | 0x80U);
}

std::string uuidV5Core(const std::string &name, const std::string &nameSpace) {
  const auto prefix = parseUuid(nameSpace);
  std::vector<uint8_t> input(prefix.begin(), prefix.end());
  input.insert(input.end(), name.begin(), name.end());

  OH_CryptoDigest *context = nullptr;
  const auto status = OH_CryptoDigest_Create("SHA1", &context);
  const std::unique_ptr<OH_CryptoDigest, decltype(&OH_DigestCrypto_Destroy)> handle(
      context, OH_DigestCrypto_Destroy);
  if (status != CRYPTO_SUCCESS || !handle) {
    throw CodedError("ERR_UUID_DIGEST", "HarmonyOS could not initialize the UUID v5 digest.");
  }
  Crypto_DataBlob source{input.data(), input.size()};
  if (OH_CryptoDigest_Update(context, &source) != CRYPTO_SUCCESS) {
    throw CodedError("ERR_UUID_DIGEST", "HarmonyOS could not hash the UUID v5 namespace and name.");
  }

  Crypto_DataBlob digest{};
  const std::unique_ptr<Crypto_DataBlob, decltype(&OH_Crypto_FreeDataBlob)> result(
      &digest, OH_Crypto_FreeDataBlob);
  std::array<uint8_t, 16> bytes{};
  if (OH_CryptoDigest_Final(context, &digest) != CRYPTO_SUCCESS || !digest.data || digest.len != 20) {
    throw CodedError("ERR_UUID_DIGEST", "HarmonyOS could not finalize the UUID v5 digest.");
  }

  std::copy_n(digest.data, bytes.size(), bytes.begin());
  applyUuidVersionAndVariant(bytes, 5);

  return formatUuid(bytes);
}

}  // namespace expo::harmony
