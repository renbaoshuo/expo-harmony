#include "modules/UuidCore.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace expo::harmony {

namespace {

uint32_t rotateLeft(uint32_t value, unsigned bits) {
  return (value << bits) | (value >> (32U - bits));
}

std::array<uint8_t, 20> sha1(const std::vector<uint8_t>& input) {
  auto data = input;
  const auto bitLength = static_cast<uint64_t>(data.size()) * 8U;
  data.push_back(0x80);
  while ((data.size() % 64U) != 56U) data.push_back(0);
  for (int shift = 56; shift >= 0; shift -= 8) {
    data.push_back(static_cast<uint8_t>((bitLength >> shift) & 0xffU));
  }

  uint32_t h0 = 0x67452301U;
  uint32_t h1 = 0xefcdab89U;
  uint32_t h2 = 0x98badcfeU;
  uint32_t h3 = 0x10325476U;
  uint32_t h4 = 0xc3d2e1f0U;
  std::array<uint32_t, 80> words{};
  for (size_t offset = 0; offset < data.size(); offset += 64) {
    for (size_t index = 0; index < 16; ++index) {
      const auto position = offset + index * 4;
      words[index] =
          (static_cast<uint32_t>(data[position]) << 24U) |
          (static_cast<uint32_t>(data[position + 1]) << 16U) |
          (static_cast<uint32_t>(data[position + 2]) << 8U) |
          static_cast<uint32_t>(data[position + 3]);
    }
    for (size_t index = 16; index < 80; ++index) {
      words[index] = rotateLeft(
          words[index - 3] ^ words[index - 8] ^
              words[index - 14] ^ words[index - 16],
          1);
    }
    auto a = h0;
    auto b = h1;
    auto c = h2;
    auto d = h3;
    auto e = h4;
    for (size_t index = 0; index < 80; ++index) {
      uint32_t f;
      uint32_t k;
      if (index < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5a827999U;
      } else if (index < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1U;
      } else if (index < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdcU;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6U;
      }
      const auto temporary = rotateLeft(a, 5) + f + e + k + words[index];
      e = d;
      d = c;
      c = rotateLeft(b, 30);
      b = a;
      a = temporary;
    }
    h0 += a;
    h1 += b;
    h2 += c;
    h3 += d;
    h4 += e;
  }

  std::array<uint8_t, 20> result{};
  const std::array<uint32_t, 5> hash{h0, h1, h2, h3, h4};
  for (size_t index = 0; index < hash.size(); ++index) {
    result[index * 4] = static_cast<uint8_t>(hash[index] >> 24U);
    result[index * 4 + 1] = static_cast<uint8_t>(hash[index] >> 16U);
    result[index * 4 + 2] = static_cast<uint8_t>(hash[index] >> 8U);
    result[index * 4 + 3] = static_cast<uint8_t>(hash[index]);
  }
  return result;
}

uint8_t parseHex(char character) {
  if (character >= '0' && character <= '9') return character - '0';
  if (character >= 'a' && character <= 'f') return character - 'a' + 10;
  if (character >= 'A' && character <= 'F') return character - 'A' + 10;
  throw std::invalid_argument("UUID namespace contains a non-hex character");
}

std::array<uint8_t, 16> parseUuid(const std::string& value) {
  constexpr std::array<size_t, 4> separators{8, 13, 18, 23};
  if (value.size() != 36 ||
      std::any_of(
          separators.begin(),
          separators.end(),
          [&value](size_t index) { return value[index] != '-'; })) {
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

} // namespace

std::string formatUuid(const std::array<uint8_t, 16>& bytes) {
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (size_t index = 0; index < bytes.size(); ++index) {
    if (index == 4 || index == 6 || index == 8 || index == 10) output << '-';
    output << std::setw(2) << static_cast<unsigned>(bytes[index]);
  }
  return output.str();
}

void applyUuidVersionAndVariant(std::array<uint8_t, 16>& bytes, uint8_t version) {
  if (version > 0x0fU) throw std::invalid_argument("UUID version must fit in four bits");
  bytes[6] = static_cast<uint8_t>((bytes[6] & 0x0fU) | (version << 4U));
  bytes[8] = static_cast<uint8_t>((bytes[8] & 0x3fU) | 0x80U);
}

std::string uuidV5Core(const std::string& name, const std::string& nameSpace) {
  const auto namespaceBytes = parseUuid(nameSpace);
  std::vector<uint8_t> input(namespaceBytes.begin(), namespaceBytes.end());
  input.insert(input.end(), name.begin(), name.end());
  const auto digest = sha1(input);
  std::array<uint8_t, 16> bytes{};
  std::copy_n(digest.begin(), bytes.size(), bytes.begin());
  applyUuidVersionAndVariant(bytes, 5);
  return formatUuid(bytes);
}

} // namespace expo::harmony
