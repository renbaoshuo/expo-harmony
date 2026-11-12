/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include <cstdint>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include <napi/native_api.h>
#include <unicode/ucal.h>
#include <unicode/uloc.h>
#include <unicode/unum.h>

namespace {

using NumberFormat = std::unique_ptr<UNumberFormat, decltype(&unum_close)>;

napi_value NumberSymbol(napi_env env, const UNumberFormat *format, UNumberFormatSymbol symbol) {
  napi_value result = nullptr;

  if (format == nullptr) {
    napi_get_null(env, &result);

    return result;
  }

  UErrorCode status = U_ZERO_ERROR;
  int32_t size = unum_getSymbol(format, symbol, nullptr, 0, &status);

  if (status != U_BUFFER_OVERFLOW_ERROR && U_FAILURE(status)) {
    napi_get_null(env, &result);

    return result;
  }

  std::vector<UChar> buffer(static_cast<size_t>(size) + 1);
  status = U_ZERO_ERROR;
  size = unum_getSymbol(format, symbol, buffer.data(), static_cast<int32_t>(buffer.size()), &status);

  if (U_FAILURE(status) || size == 0) {
    napi_get_null(env, &result);
  } else {
    napi_create_string_utf16(env, reinterpret_cast<const char16_t *>(buffer.data()), size, &result);
  }

  return result;
}

NumberFormat OpenFormat(UNumberFormatStyle style, const char *locale) {
  UErrorCode status = U_ZERO_ERROR;
  NumberFormat format(unum_open(style, nullptr, 0, locale, nullptr, &status), unum_close);

  if (U_FAILURE(status)) {
    format.reset();
  }

  return format;
}

bool ReadLocale(napi_env env, napi_callback_info info, std::string &result) {
  size_t argc = 1;
  napi_value argument = nullptr;
  if (napi_get_cb_info(env, info, &argc, &argument, nullptr, nullptr) != napi_ok) {
    return false;
  }

  napi_valuetype type = napi_undefined;
  if (argc != 1 || napi_typeof(env, argument, &type) != napi_ok || type != napi_string) {
    napi_throw_type_error(env, "ERR_LOCALIZATION_LOCALE", "A BCP 47 language tag is required.");
    return false;
  }

  size_t size = 0;
  if (napi_get_value_string_utf8(env, argument, nullptr, 0, &size) != napi_ok) {
    return false;
  }

  std::vector<char> tag(size + 1);
  if (napi_get_value_string_utf8(env, argument, tag.data(), tag.size(), &size) != napi_ok) {
    return false;
  }

  // Reject a malformed suffix or embedded NUL even if ICU parsed a valid prefix.
  UErrorCode status = U_ZERO_ERROR;
  int32_t parsed = 0;
  int32_t length = uloc_forLanguageTag(tag.data(), nullptr, 0, &parsed, &status);
  if ((status != U_BUFFER_OVERFLOW_ERROR && U_FAILURE(status)) || parsed != static_cast<int64_t>(size) || size == 0) {
    napi_throw_range_error(env, "ERR_LOCALIZATION_LOCALE", "Invalid BCP 47 language tag.");
    return false;
  }

  std::vector<char> locale(static_cast<size_t>(length) + 1);
  status = U_ZERO_ERROR;
  uloc_forLanguageTag(tag.data(), locale.data(), static_cast<int32_t>(locale.size()), &parsed, &status);
  if (U_FAILURE(status)) {
    napi_throw_error(env, "ERR_LOCALIZATION_LOCALE", u_errorName(status));
    return false;
  }

  result.assign(locale.data(), length);

  return true;
}

napi_value GetNumericInfo(napi_env env, napi_callback_info info) {
  std::string locale;
  if (!ReadLocale(env, info, locale)) {
    return nullptr;
  }

  auto decimal = OpenFormat(UNUM_DECIMAL, locale.data());
  auto currency = OpenFormat(UNUM_CURRENCY, locale.data());

  // A regionless locale must not inherit ICU's process-default currency.
  char region[ULOC_COUNTRY_CAPACITY];
  UErrorCode status = U_ZERO_ERROR;
  int32_t length = uloc_getCountry(locale.data(), region, sizeof(region), &status);
  if (U_FAILURE(status) || length == 0) {
    currency.reset();
  }

  if (currency) {
    UChar code[4];
    status = U_ZERO_ERROR;
    int32_t count = unum_getSymbol(currency.get(), UNUM_INTL_CURRENCY_SYMBOL, code, 4, &status);

    // ISO 4217 XXX denotes no currency.
    if (U_FAILURE(status) || count == 0 || (count == 3 && code[0] == u'X' && code[1] == u'X' && code[2] == u'X')) {
      currency.reset();
    }
  }

  napi_value result = nullptr;
  if (napi_create_object(env, &result) != napi_ok) {
    return nullptr;
  }

  struct SymbolProperty {
    const char *name;
    const UNumberFormat *format;
    UNumberFormatSymbol symbol;
  };

  const SymbolProperty properties[] = {
      {"decimalSeparator", decimal.get(), UNUM_DECIMAL_SEPARATOR_SYMBOL},
      {"digitGroupingSeparator", decimal.get(), UNUM_GROUPING_SEPARATOR_SYMBOL},
      {"currencyCode", currency.get(), UNUM_INTL_CURRENCY_SYMBOL},
      {"currencySymbol", currency.get(), UNUM_CURRENCY_SYMBOL},
  };

  for (const auto &property : properties) {
    napi_value value = NumberSymbol(env, property.format, property.symbol);
    if (value == nullptr || napi_set_named_property(env, result, property.name, value) != napi_ok) {
      return nullptr;
    }
  }

  return result;
}

napi_value GetCalendarType(napi_env env, napi_callback_info info) {
  std::string locale;
  if (!ReadLocale(env, info, locale)) {
    return nullptr;
  }

  UErrorCode status = U_ZERO_ERROR;
  std::unique_ptr<UCalendar, decltype(&ucal_close)> calendar(
      ucal_open(nullptr, 0, locale.c_str(), UCAL_DEFAULT, &status), ucal_close);
  const char *type = nullptr;

  if (U_SUCCESS(status) && calendar) {
    type = ucal_getType(calendar.get(), &status);

    // ICU uses "gregorian" where Expo expects the Unicode identifier "gregory".
    if (U_SUCCESS(status) && type != nullptr) {
      type = uloc_toUnicodeLocaleType("calendar", type);

      // ICU 72 implements ISO week rules on a Gregorian calendar instance.
      char requested[sizeof("iso8601")];
      UErrorCode keyword = U_ZERO_ERROR;
      int32_t length = uloc_getKeywordValue(locale.c_str(), "calendar", requested, sizeof(requested), &keyword);
      if (U_SUCCESS(keyword) && length == 7 && std::string_view(requested, length) == "iso8601") {
        type = "iso8601";
      }
    }
  }

  napi_value result = nullptr;
  if (U_FAILURE(status) || type == nullptr || type[0] == '\0') {
    napi_get_null(env, &result);
  } else {
    napi_create_string_utf8(env, type, NAPI_AUTO_LENGTH, &result);
  }

  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"getNumericInfo", nullptr, GetNumericInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"getCalendarType", nullptr, GetCalendarType, nullptr, nullptr, nullptr, napi_default, nullptr},
  };

  if (napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties) != napi_ok) {
    return nullptr;
  }

  return exports;
}

napi_module module = {1, 0, nullptr, Init, "expo_localization", nullptr, {0}};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterExpoLocalization() {
  napi_module_register(&module);
}
