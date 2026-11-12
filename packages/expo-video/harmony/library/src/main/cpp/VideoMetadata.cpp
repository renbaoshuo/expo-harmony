/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include <cmath>
#include <climits>
#include <map>
#include <memory>

#include <napi/native_api.h>
#include <multimedia/player_framework/native_avsource.h>

namespace {
constexpr double MAX_SAFE_INTEGER = 9007199254740991.0;
constexpr const char *ERROR_CODE = "ERR_VIDEO_METADATA";

struct RangeRequest {
  int32_t fd = -1;
  int64_t offset = 0;
  int64_t length = 0;
  std::map<uint32_t, const char *> ranges;
  bool failed = false;
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
};

using Source = std::unique_ptr<OH_AVSource, decltype(&OH_AVSource_Destroy)>;
using Format = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>;

const char *videoRange(int32_t transfer) {
  switch (transfer) {
    case TRANSFER_CHARACTERISTIC_HLG: return "hlg";
    case TRANSFER_CHARACTERISTIC_PQ: return "pq";
    default: return "sdr";
  }
}

void readRanges(napi_env, void *data) {
  auto &request = *static_cast<RangeRequest *>(data);
  try {
    Source source(OH_AVSource_CreateWithFD(request.fd, request.offset, request.length), OH_AVSource_Destroy);
    if (!source) return;

    Format format(OH_AVSource_GetSourceFormat(source.get()), OH_AVFormat_Destroy);
    int32_t count = 0;
    if (!format || !OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_TRACK_COUNT, &count)) return;

    for (int32_t index = 0; index < count; ++index) {
      Format track(OH_AVSource_GetTrackFormat(source.get(), index), OH_AVFormat_Destroy);
      int32_t type = MEDIA_TYPE_AUD;
      if (!track || !OH_AVFormat_GetIntValue(track.get(), OH_MD_KEY_TRACK_TYPE, &type) || type != MEDIA_TYPE_VID) continue;

      int32_t transfer = TRANSFER_CHARACTERISTIC_UNSPECIFIED;
      OH_AVFormat_GetIntValue(track.get(), OH_MD_KEY_TRANSFER_CHARACTERISTICS, &transfer);
      request.ranges.emplace(static_cast<uint32_t>(index), videoRange(transfer));
    }
  } catch (...) {
    request.failed = true;
  }
}

void reject(napi_env env, napi_deferred deferred, const char *message) {
  napi_value error = nullptr;
  bool pending = false;
  napi_is_exception_pending(env, &pending);
  if (pending) {
    napi_get_and_clear_last_exception(env, &error);
  } else {
    napi_value code = nullptr, text = nullptr;
    if (napi_create_string_utf8(env, ERROR_CODE, NAPI_AUTO_LENGTH, &code) != napi_ok ||
        napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &text) != napi_ok ||
        napi_create_error(env, code, text, &error) != napi_ok) return;
  }
  napi_reject_deferred(env, deferred, error);
}

void complete(napi_env env, napi_status status, void *data) {
  std::unique_ptr<RangeRequest> request(static_cast<RangeRequest *>(data));
  napi_delete_async_work(env, request->work);

  if (status != napi_ok || request->failed) {
    reject(env, request->deferred, "Video metadata extraction failed or was cancelled.");
    return;
  }

  napi_value result = nullptr;
  if (napi_create_object(env, &result) != napi_ok) {
    reject(env, request->deferred, "Could not create video range metadata.");
    return;
  }

  for (const auto &[index, range] : request->ranges) {
    napi_value value = nullptr;
    if (napi_create_string_utf8(env, range, NAPI_AUTO_LENGTH, &value) != napi_ok ||
        napi_set_element(env, result, index, value) != napi_ok) {
      reject(env, request->deferred, "Could not create video range metadata.");
      return;
    }
  }

  napi_resolve_deferred(env, request->deferred, result);
}

bool integer(napi_env env, napi_value value, double min, double max, int64_t &output) {
  double number = 0;
  if (napi_get_value_double(env, value, &number) != napi_ok || !std::isfinite(number) ||
      std::trunc(number) != number || number < min || number > max) return false;
  output = static_cast<int64_t>(number);
  return true;
}

napi_value readVideoRanges(napi_env env, napi_callback_info info) {
  size_t count = 4;
  napi_value args[4] = {};
  if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok) return nullptr;

  int64_t fd = -1, offset = 0, length = 0;
  if (count != 3 || !integer(env, args[0], 0, INT_MAX, fd) ||
      !integer(env, args[1], 0, MAX_SAFE_INTEGER, offset) || !integer(env, args[2], 1, MAX_SAFE_INTEGER, length)) {
    napi_throw_type_error(env, ERROR_CODE, "Expected a file descriptor, nonnegative offset and positive length.");
    return nullptr;
  }

  std::unique_ptr<RangeRequest> request;
  try {
    request = std::make_unique<RangeRequest>();
  } catch (const std::exception &error) {
    napi_throw_error(env, ERROR_CODE, error.what());
    return nullptr;
  }

  request->fd = static_cast<int32_t>(fd);
  request->offset = offset;
  request->length = length;

  napi_value promise = nullptr, name = nullptr;
  if (napi_create_string_utf8(env, "ExpoVideoMetadata", NAPI_AUTO_LENGTH, &name) != napi_ok ||
      napi_create_promise(env, &request->deferred, &promise) != napi_ok) return nullptr;
  if (napi_create_async_work(env, nullptr, name, readRanges, complete, request.get(), &request->work) != napi_ok ||
      napi_queue_async_work(env, request->work) != napi_ok) {
    if (request->work) napi_delete_async_work(env, request->work);
    reject(env, request->deferred, "Could not schedule video metadata extraction.");
    return promise;
  }

  request.release();
  return promise;
}

napi_value initialize(napi_env env, napi_value exports) {
  napi_property_descriptor methods[] = {
    {"readVideoRanges", nullptr, readVideoRanges, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  if (napi_define_properties(env, exports, 1, methods) != napi_ok) return nullptr;
  return exports;
}

napi_module module = {1, 0, nullptr, initialize, "expo_video_metadata", nullptr, {0}};
} // namespace

extern "C" __attribute__((constructor)) void registerVideoMetadata() {
  napi_module_register(&module);
}
