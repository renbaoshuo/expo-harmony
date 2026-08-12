#include "api/NativeValueParser.h"

#include <algorithm>
#include <charconv>
#include <cerrno>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace expo::harmony {

namespace {

bool isAsciiAlpha(char value) {
  return (value >= 'a' && value <= 'z') ||
      (value >= 'A' && value <= 'Z');
}

bool isAsciiDigit(char value) {
  return value >= '0' && value <= '9';
}

bool isHexDigit(char value) {
  return isAsciiDigit(value) ||
      (value >= 'a' && value <= 'f') ||
      (value >= 'A' && value <= 'F');
}

bool isSchemeCharacter(char value) {
  return isAsciiAlpha(value) || isAsciiDigit(value) ||
      value == '+' || value == '-' || value == '.';
}

bool isUriAsciiCharacter(char value) {
  return isAsciiAlpha(value) || isAsciiDigit(value) ||
      std::string_view("-._~:/?#[]@!$&'()*+,;=%").find(value) !=
          std::string_view::npos;
}

void validateCommonUriCharacters(std::string_view value) {
  int bracketDepth = 0;
  for (size_t index = 0; index < value.size(); ++index) {
    const auto byte = static_cast<unsigned char>(value[index]);
    if (byte <= 0x20U || byte == 0x7fU ||
        (byte < 0x80U && !isUriAsciiCharacter(value[index]))) {
      throw std::invalid_argument("URI contains a character outside the RFC 3986 syntax");
    }
    if (value[index] == '%') {
      if (index + 2 >= value.size() ||
          !isHexDigit(value[index + 1]) || !isHexDigit(value[index + 2])) {
        throw std::invalid_argument("URI contains an invalid percent escape");
      }
      index += 2;
      continue;
    }
    if (value[index] == '[') {
      if (++bracketDepth != 1) {
        throw std::invalid_argument("URI contains nested brackets");
      }
    } else if (value[index] == ']') {
      if (--bracketDepth != 0) {
        throw std::invalid_argument("URI contains an unmatched closing bracket");
      }
    }
  }
  if (bracketDepth != 0) {
    throw std::invalid_argument("URI contains an unmatched opening bracket");
  }
}

std::vector<std::string_view> splitIpv6Groups(std::string_view value) {
  std::vector<std::string_view> result;
  size_t start = 0;
  while (start <= value.size()) {
    const auto separator = value.find(':', start);
    result.push_back(value.substr(
        start,
        separator == std::string_view::npos ? value.size() - start : separator - start));
    if (separator == std::string_view::npos) break;
    start = separator + 1;
  }
  return result;
}

bool isValidIpv4(std::string_view value) {
  size_t start = 0;
  int components = 0;
  while (start <= value.size()) {
    const auto separator = value.find('.', start);
    const auto component = value.substr(
        start,
        separator == std::string_view::npos ? value.size() - start : separator - start);
    if (component.empty() || component.size() > 3 ||
        !std::all_of(component.begin(), component.end(), isAsciiDigit)) {
      return false;
    }
    unsigned int number = 0;
    for (const char digit : component) number = number * 10U + (digit - '0');
    if (number > 255U) return false;
    ++components;
    if (separator == std::string_view::npos) break;
    start = separator + 1;
  }
  return components == 4;
}

bool isValidIpv6(std::string_view value) {
  const auto zone = value.find("%25");
  if (zone != std::string_view::npos) {
    const auto zoneName = value.substr(zone + 3);
    if (zoneName.empty() || zoneName.find('%') != std::string_view::npos) return false;
    value = value.substr(0, zone);
  } else if (value.find('%') != std::string_view::npos) {
    return false;
  }
  if (value.empty()) return false;

  const auto compression = value.find("::");
  if (compression != std::string_view::npos &&
      value.find("::", compression + 2) != std::string_view::npos) {
    return false;
  }
  const auto left = compression == std::string_view::npos
      ? value
      : value.substr(0, compression);
  const auto right = compression == std::string_view::npos
      ? std::string_view{}
      : value.substr(compression + 2);
  size_t groupCount = 0;
  bool sawIpv4 = false;
  const auto validateSide = [&](std::string_view side, bool finalSide) {
    if (side.empty()) return true;
    const auto groups = splitIpv6Groups(side);
    for (size_t index = 0; index < groups.size(); ++index) {
      const auto group = groups[index];
      if (group.empty()) return false;
      if (group.find('.') != std::string_view::npos) {
        if (!finalSide || index + 1 != groups.size() || sawIpv4 || !isValidIpv4(group)) {
          return false;
        }
        groupCount += 2;
        sawIpv4 = true;
      } else {
        if (group.size() > 4 ||
            !std::all_of(group.begin(), group.end(), isHexDigit)) {
          return false;
        }
        ++groupCount;
      }
    }
    return true;
  };
  if (!validateSide(left, compression == std::string_view::npos) ||
      !validateSide(right, true)) {
    return false;
  }
  return compression == std::string_view::npos ? groupCount == 8 : groupCount < 8;
}

void validateBracketedAuthority(std::string_view value) {
  const auto schemeSeparator = value.find(':');
  size_t authorityStart = std::string_view::npos;
  if (value.starts_with("//")) {
    authorityStart = 2;
  } else if (schemeSeparator != std::string_view::npos &&
             value.substr(schemeSeparator + 1).starts_with("//")) {
    authorityStart = schemeSeparator + 3;
  }
  if (authorityStart == std::string_view::npos) {
    const auto firstPathDelimiter = value.find_first_of("/?#");
    const bool opaque = schemeSeparator != std::string_view::npos &&
        (firstPathDelimiter == std::string_view::npos || schemeSeparator < firstPathDelimiter) &&
        !value.substr(schemeSeparator + 1).starts_with('/');
    if (!opaque) {
      const auto pathEnd = value.find_first_of("?#");
      const auto hierarchicalPath = value.substr(
          0,
          pathEnd == std::string_view::npos ? value.size() : pathEnd);
      if (hierarchicalPath.find_first_of("[]") != std::string_view::npos) {
        throw std::invalid_argument("hierarchical URI path contains a raw bracket");
      }
    }
    return;
  }
  const auto authorityEnd = value.find_first_of("/?#", authorityStart);
  const auto authority = value.substr(
      authorityStart,
      authorityEnd == std::string_view::npos
          ? value.size() - authorityStart
          : authorityEnd - authorityStart);
  const auto at = authority.rfind('@');
  if (at != std::string_view::npos &&
      authority.substr(0, at).find_first_of("[]@") != std::string_view::npos) {
    throw std::invalid_argument("authority user info contains an illegal bracket or @ character");
  }
  const auto hostAndPort = authority.substr(at == std::string_view::npos ? 0 : at + 1);
  if (!hostAndPort.starts_with('[')) {
    if (hostAndPort.find_first_of("[]") != std::string_view::npos) {
      throw std::invalid_argument("authority contains misplaced brackets");
    }
  } else {
    const auto closingBracket = hostAndPort.find(']');
    if (closingBracket == std::string_view::npos ||
        !isValidIpv6(hostAndPort.substr(1, closingBracket - 1))) {
      throw std::invalid_argument("authority contains an invalid IPv6 host");
    }
    const auto suffix = hostAndPort.substr(closingBracket + 1);
    if (!suffix.empty() &&
        (!suffix.starts_with(':') || suffix.size() == 1 ||
         !std::all_of(suffix.begin() + 1, suffix.end(), isAsciiDigit))) {
      throw std::invalid_argument("authority contains invalid text after its IPv6 host");
    }
  }
  if (authorityEnd != std::string_view::npos) {
    const auto pathEnd = value.find_first_of("?#", authorityEnd);
    const auto pathPart = value.substr(
        authorityEnd,
        pathEnd == std::string_view::npos ? value.size() - authorityEnd : pathEnd - authorityEnd);
    if (pathPart.find_first_of("[]") != std::string_view::npos) {
      throw std::invalid_argument("hierarchical URI path contains a raw bracket");
    }
  }
}

std::string normalizedColorText(std::string_view value) {
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) {
    value.remove_prefix(1);
  }
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) {
    value.remove_suffix(1);
  }
  std::string result(value);
  std::transform(
      result.begin(),
      result.end(),
      result.begin(),
      [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
  return result;
}

double parseDecimal(std::string_view text) {
  size_t index = 0;
  if (index < text.size() && (text[index] == '+' || text[index] == '-')) {
    ++index;
  }

  const auto integerStart = index;
  while (index < text.size() && isAsciiDigit(text[index])) {
    ++index;
  }
  const bool hasIntegerDigits = index > integerStart;

  bool hasFractionDigits = false;
  if (index < text.size() && text[index] == '.') {
    ++index;
    const auto fractionStart = index;
    while (index < text.size() && isAsciiDigit(text[index])) {
      ++index;
    }
    hasFractionDigits = index > fractionStart;
    if (!hasFractionDigits) {
      throw std::invalid_argument("color component is not a CSS number");
    }
  }

  if (!hasIntegerDigits && !hasFractionDigits) {
    throw std::invalid_argument("color component is not a CSS number");
  }

  if (index < text.size() && (text[index] == 'e' || text[index] == 'E')) {
    ++index;
    if (index < text.size() && (text[index] == '+' || text[index] == '-')) {
      ++index;
    }
    const auto exponentStart = index;
    while (index < text.size() && isAsciiDigit(text[index])) {
      ++index;
    }
    if (index == exponentStart) {
      throw std::invalid_argument("color component is not a CSS number");
    }
  }

  if (index != text.size()) {
    throw std::invalid_argument("color component is not a CSS number");
  }

  const std::string owned(text);
  char* end = nullptr;
  errno = 0;
  const auto result = std::strtod(owned.c_str(), &end);
  if (errno == ERANGE || end != owned.c_str() + owned.size() ||
      !std::isfinite(result)) {
    throw std::invalid_argument("color component is not a finite number");
  }
  return result;
}

uint8_t normalizedByte(double value) {
  if (!std::isfinite(value) || value < 0 || value > 1) {
    throw std::invalid_argument("normalized color components must be between 0 and 1");
  }
  return static_cast<uint8_t>(std::lround(value * 255.0));
}

uint8_t rgbByte(double value) {
  if (!std::isfinite(value) || value < 0 || value > 255) {
    throw std::invalid_argument("RGB color components must be between 0 and 255");
  }
  return static_cast<uint8_t>(std::lround(value));
}

std::vector<std::string_view> splitComponents(std::string_view value) {
  std::vector<std::string_view> result;
  size_t start = 0;
  while (start <= value.size()) {
    const auto comma = value.find(',', start);
    auto component = value.substr(
        start,
        comma == std::string_view::npos ? value.size() - start : comma - start);
    while (!component.empty() &&
           std::isspace(static_cast<unsigned char>(component.front()))) {
      component.remove_prefix(1);
    }
    while (!component.empty() &&
           std::isspace(static_cast<unsigned char>(component.back()))) {
      component.remove_suffix(1);
    }
    if (component.empty()) {
      throw std::invalid_argument("color contains an empty component");
    }
    result.push_back(component);
    if (comma == std::string_view::npos) break;
    start = comma + 1;
  }
  return result;
}

uint32_t parseRgbFunction(const std::string& value) {
  const bool hasAlpha = value.starts_with("rgba(");
  const size_t prefixLength = hasAlpha ? 5 : 4;
  if (!value.ends_with(')')) {
    throw std::invalid_argument("RGB color is missing a closing parenthesis");
  }
  const auto components = splitComponents(
      std::string_view(value).substr(prefixLength, value.size() - prefixLength - 1));
  if (components.size() != (hasAlpha ? 4U : 3U)) {
    throw std::invalid_argument("rgb() requires three components and rgba() requires four");
  }
  const auto red = rgbByte(parseDecimal(components[0]));
  const auto green = rgbByte(parseDecimal(components[1]));
  const auto blue = rgbByte(parseDecimal(components[2]));
  const auto alpha = hasAlpha ? normalizedByte(parseDecimal(components[3])) : 0xffU;
  return (static_cast<uint32_t>(alpha) << 24U) |
      (static_cast<uint32_t>(red) << 16U) |
      (static_cast<uint32_t>(green) << 8U) |
      blue;
}

const std::unordered_map<std::string, uint32_t>& namedColors() {
  static const std::unordered_map<std::string, uint32_t> values = {
      {"aliceblue", 0xfff0f8ffu},
      {"antiquewhite", 0xfffaebd7u},
      {"aqua", 0xff00ffffu},
      {"aquamarine", 0xff7fffd4u},
      {"azure", 0xfff0ffffu},
      {"beige", 0xfff5f5dcu},
      {"bisque", 0xffffe4c4u},
      {"black", 0xff000000u},
      {"blanchedalmond", 0xffffebcdu},
      {"blue", 0xff0000ffu},
      {"blueviolet", 0xff8a2be2u},
      {"brown", 0xffa52a2au},
      {"burlywood", 0xffdeb887u},
      {"cadetblue", 0xff5f9ea0u},
      {"chartreuse", 0xff7fff00u},
      {"chocolate", 0xffd2691eu},
      {"coral", 0xffff7f50u},
      {"cornflowerblue", 0xff6495edu},
      {"cornsilk", 0xfffff8dcu},
      {"crimson", 0xffdc143cu},
      {"cyan", 0xff00ffffu},
      {"darkblue", 0xff00008bu},
      {"darkcyan", 0xff008b8bu},
      {"darkgoldenrod", 0xffb8860bu},
      {"darkgray", 0xffa9a9a9u},
      {"darkgreen", 0xff006400u},
      {"darkgrey", 0xffa9a9a9u},
      {"darkkhaki", 0xffbdb76bu},
      {"darkmagenta", 0xff8b008bu},
      {"darkolivegreen", 0xff556b2fu},
      {"darkorange", 0xffff8c00u},
      {"darkorchid", 0xff9932ccu},
      {"darkred", 0xff8b0000u},
      {"darksalmon", 0xffe9967au},
      {"darkseagreen", 0xff8fbc8fu},
      {"darkslateblue", 0xff483d8bu},
      {"darkslategray", 0xff2f4f4fu},
      {"darkslategrey", 0xff2f4f4fu},
      {"darkturquoise", 0xff00ced1u},
      {"darkviolet", 0xff9400d3u},
      {"deeppink", 0xffff1493u},
      {"deepskyblue", 0xff00bfffu},
      {"dimgray", 0xff696969u},
      {"dimgrey", 0xff696969u},
      {"dodgerblue", 0xff1e90ffu},
      {"firebrick", 0xffb22222u},
      {"floralwhite", 0xfffffaf0u},
      {"forestgreen", 0xff228b22u},
      {"fuchsia", 0xffff00ffu},
      {"gainsboro", 0xffdcdcdcu},
      {"ghostwhite", 0xfff8f8ffu},
      {"gold", 0xffffd700u},
      {"goldenrod", 0xffdaa520u},
      {"gray", 0xff808080u},
      {"green", 0xff008000u},
      {"greenyellow", 0xffadff2fu},
      {"grey", 0xff808080u},
      {"honeydew", 0xfff0fff0u},
      {"hotpink", 0xffff69b4u},
      {"indianred", 0xffcd5c5cu},
      {"indigo", 0xff4b0082u},
      {"ivory", 0xfffffff0u},
      {"khaki", 0xfff0e68cu},
      {"lavender", 0xffe6e6fau},
      {"lavenderblush", 0xfffff0f5u},
      {"lawngreen", 0xff7cfc00u},
      {"lemonchiffon", 0xfffffacdu},
      {"lightblue", 0xffadd8e6u},
      {"lightcoral", 0xfff08080u},
      {"lightcyan", 0xffe0ffffu},
      {"lightgoldenrodyellow", 0xfffafad2u},
      {"lightgray", 0xffd3d3d3u},
      {"lightgreen", 0xff90ee90u},
      {"lightgrey", 0xffd3d3d3u},
      {"lightpink", 0xffffb6c1u},
      {"lightsalmon", 0xffffa07au},
      {"lightseagreen", 0xff20b2aau},
      {"lightskyblue", 0xff87cefau},
      {"lightslategray", 0xff778899u},
      {"lightslategrey", 0xff778899u},
      {"lightsteelblue", 0xffb0c4deu},
      {"lightyellow", 0xffffffe0u},
      {"lime", 0xff00ff00u},
      {"limegreen", 0xff32cd32u},
      {"linen", 0xfffaf0e6u},
      {"magenta", 0xffff00ffu},
      {"maroon", 0xff800000u},
      {"mediumaquamarine", 0xff66cdaau},
      {"mediumblue", 0xff0000cdu},
      {"mediumorchid", 0xffba55d3u},
      {"mediumpurple", 0xff9370dbu},
      {"mediumseagreen", 0xff3cb371u},
      {"mediumslateblue", 0xff7b68eeu},
      {"mediumspringgreen", 0xff00fa9au},
      {"mediumturquoise", 0xff48d1ccu},
      {"mediumvioletred", 0xffc71585u},
      {"midnightblue", 0xff191970u},
      {"mintcream", 0xfff5fffau},
      {"mistyrose", 0xffffe4e1u},
      {"moccasin", 0xffffe4b5u},
      {"navajowhite", 0xffffdeadu},
      {"navy", 0xff000080u},
      {"oldlace", 0xfffdf5e6u},
      {"olive", 0xff808000u},
      {"olivedrab", 0xff6b8e23u},
      {"orange", 0xffffa500u},
      {"orangered", 0xffff4500u},
      {"orchid", 0xffda70d6u},
      {"palegoldenrod", 0xffeee8aau},
      {"palegreen", 0xff98fb98u},
      {"paleturquoise", 0xffafeeeeu},
      {"palevioletred", 0xffdb7093u},
      {"papayawhip", 0xffffefd5u},
      {"peachpuff", 0xffffdab9u},
      {"peru", 0xffcd853fu},
      {"pink", 0xffffc0cbu},
      {"plum", 0xffdda0ddu},
      {"powderblue", 0xffb0e0e6u},
      {"purple", 0xff800080u},
      {"rebeccapurple", 0xff663399u},
      {"red", 0xffff0000u},
      {"rosybrown", 0xffbc8f8fu},
      {"royalblue", 0xff4169e1u},
      {"saddlebrown", 0xff8b4513u},
      {"salmon", 0xfffa8072u},
      {"sandybrown", 0xfff4a460u},
      {"seagreen", 0xff2e8b57u},
      {"seashell", 0xfffff5eeu},
      {"sienna", 0xffa0522du},
      {"silver", 0xffc0c0c0u},
      {"skyblue", 0xff87ceebu},
      {"slateblue", 0xff6a5acdu},
      {"slategray", 0xff708090u},
      {"slategrey", 0xff708090u},
      {"snow", 0xfffffafau},
      {"springgreen", 0xff00ff7fu},
      {"steelblue", 0xff4682b4u},
      {"tan", 0xffd2b48cu},
      {"teal", 0xff008080u},
      {"thistle", 0xffd8bfd8u},
      {"tomato", 0xffff6347u},
      {"transparent", 0x00000000u},
      {"turquoise", 0xff40e0d0u},
      {"violet", 0xffee82eeu},
      {"wheat", 0xfff5deb3u},
      {"white", 0xffffffffu},
      {"whitesmoke", 0xfff5f5f5u},
      {"yellow", 0xffffff00u},
      {"yellowgreen", 0xff9acd32u},
  };
  return values;
}

} // namespace

void validateAbsoluteUrl(std::string_view value) {
  validateCommonUriCharacters(value);
  validateBracketedAuthority(value);
  const auto separator = value.find(':');
  if (separator == std::string_view::npos || separator == 0 ||
      !isAsciiAlpha(value.front()) ||
      !std::all_of(value.begin() + 1, value.begin() + separator, isSchemeCharacter)) {
    throw std::invalid_argument("URL does not have a valid absolute scheme");
  }
  const auto remainder = value.substr(separator + 1);
  if (remainder.empty()) {
    throw std::invalid_argument("URL has no scheme-specific part");
  }

  std::string scheme(value.substr(0, separator));
  std::transform(
      scheme.begin(), scheme.end(), scheme.begin(),
      [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
  if (scheme == "http" || scheme == "https") {
    if (!remainder.starts_with("//")) {
      throw std::invalid_argument("HTTP URL has no authority");
    }
    const auto authorityEnd = remainder.find_first_of("/?#", 2);
    const auto authority = remainder.substr(
        2,
        authorityEnd == std::string_view::npos
            ? remainder.size() - 2
            : authorityEnd - 2);
    const auto hostStart = authority.rfind('@') == std::string_view::npos
        ? 0
        : authority.rfind('@') + 1;
    const auto hostAndPort = authority.substr(hostStart);
    std::string_view host;
    std::string_view port;
    if (hostAndPort.starts_with('[')) {
      const auto closingBracket = hostAndPort.find(']');
      if (closingBracket == std::string_view::npos) {
        throw std::invalid_argument("HTTP URL has an unterminated IPv6 host");
      }
      host = hostAndPort.substr(1, closingBracket - 1);
      if (!isValidIpv6(host)) {
        throw std::invalid_argument("HTTP URL has an invalid IPv6 host");
      }
      const auto suffix = hostAndPort.substr(closingBracket + 1);
      if (!suffix.empty()) {
        if (!suffix.starts_with(':')) {
          throw std::invalid_argument("HTTP URL has invalid text after its IPv6 host");
        }
        port = suffix.substr(1);
      }
    } else {
      const auto portSeparator = hostAndPort.rfind(':');
      if (portSeparator != std::string_view::npos) {
        host = hostAndPort.substr(0, portSeparator);
        port = hostAndPort.substr(portSeparator + 1);
      } else {
        host = hostAndPort;
      }
    }
    if (host.empty()) {
      throw std::invalid_argument("HTTP URL has an empty host");
    }
    if (host.find_first_of("[]@") != std::string_view::npos) {
      throw std::invalid_argument("HTTP URL has an invalid host");
    }
    if (!hostAndPort.starts_with('[') && host.find(':') != std::string_view::npos) {
      throw std::invalid_argument("IPv6 hosts must be enclosed in brackets");
    }
    if (hostAndPort.ends_with(':') ||
        (!port.empty() && !std::all_of(port.begin(), port.end(), isAsciiDigit))) {
      throw std::invalid_argument("HTTP URL has an invalid port");
    }
  }
}

void validateUri(std::string_view value) {
  if (value.empty()) return; // java.net.URI.create("") is a valid relative URI.
  validateCommonUriCharacters(value);
  validateBracketedAuthority(value);
  const auto separator = value.find(':');
  const auto firstPathDelimiter = value.find_first_of("/?#");
  if (separator != std::string_view::npos &&
      (firstPathDelimiter == std::string_view::npos || separator < firstPathDelimiter)) {
    if (separator == 0 || !isAsciiAlpha(value.front()) ||
        !std::all_of(value.begin() + 1, value.begin() + separator, isSchemeCharacter)) {
      throw std::invalid_argument("URI has an invalid scheme");
    }
  }
}

uint32_t parseCssColor(std::string_view value) {
  auto normalized = normalizedColorText(value);
  if (normalized.empty()) {
    throw std::invalid_argument("color string is empty");
  }
  if (const auto iterator = namedColors().find(normalized);
      iterator != namedColors().end()) {
    return iterator->second;
  }
  if (normalized.starts_with("rgb(")) return parseRgbFunction(normalized);
  if (normalized.starts_with("rgba(")) return parseRgbFunction(normalized);

  if (normalized.front() == '#') normalized.erase(0, 1);
  if (normalized.size() == 3 || normalized.size() == 4) {
    std::string expanded;
    expanded.reserve(normalized.size() * 2);
    for (const char character : normalized) {
      expanded.push_back(character);
      expanded.push_back(character);
    }
    normalized = std::move(expanded);
  }
  if (normalized.size() == 6) normalized += "ff";
  if (normalized.size() != 8 ||
      !std::all_of(normalized.begin(), normalized.end(), isHexDigit)) {
    throw std::invalid_argument("color is not a CSS name, rgb()/rgba(), or RGB/RGBA hex value");
  }
  uint32_t rgba = 0;
  const auto [end, error] = std::from_chars(
      normalized.data(), normalized.data() + normalized.size(), rgba, 16);
  if (error != std::errc{} || end != normalized.data() + normalized.size()) {
    throw std::invalid_argument("color contains an invalid hex value");
  }
  return ((rgba & 0xffU) << 24U) | (rgba >> 8U);
}

uint32_t packNormalizedColor(std::span<const double> components) {
  if (components.size() != 3 && components.size() != 4) {
    throw std::invalid_argument("color arrays must contain three or four components");
  }
  const auto red = normalizedByte(components[0]);
  const auto green = normalizedByte(components[1]);
  const auto blue = normalizedByte(components[2]);
  const auto alpha = components.size() == 4 ? normalizedByte(components[3]) : 0xffU;
  return (static_cast<uint32_t>(alpha) << 24U) |
      (static_cast<uint32_t>(red) << 16U) |
      (static_cast<uint32_t>(green) << 8U) |
      blue;
}

} // namespace expo::harmony
