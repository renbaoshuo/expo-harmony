/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <curl/curl.h>
#include <atomic>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace expo::fetch {

using HeaderList = std::vector<std::pair<std::string, std::string>>;

struct Request {
  std::string url;
  std::string method;
  HeaderList headers;
  std::optional<std::vector<char>> body;
  std::string proxyHost;
  long proxyPort = 0;
  std::string proxyUsername;
  std::string proxyPassword;
};

struct Event {
  long status = 0;
  std::string statusText;
  HeaderList headers;
  std::vector<char> data;
  std::string error;
};

class HttpTransfer {
 public:
  explicit HttpTransfer(Request request) : request_(std::move(request)) {}
  void run(const std::function<bool(Event)> &emit);
  void cancel();

 private:
  Request request_;
  std::atomic<bool> cancelled_{false};
  std::mutex mutex_;
  CURLM *multi_ = nullptr;
};

}  // namespace expo::fetch
