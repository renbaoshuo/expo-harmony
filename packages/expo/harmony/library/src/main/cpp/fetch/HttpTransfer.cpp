/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "HttpTransfer.h"

#include <memory>
#include <stdexcept>
#include <string_view>

namespace expo::fetch {
namespace {

std::string_view trim(std::string_view value) {
  auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string_view::npos) return {};
  return value.substr(first, value.find_last_not_of(" \t\r\n") - first + 1);
}

struct Response {
  CURL *easy;
  const std::function<bool(Event)> &emit;
  bool delivered = false;
  std::string statusText;
  HeaderList headers;

  size_t receiveHeader(std::string_view line) {
    if (delivered) return line.size();

    if (line.starts_with("HTTP/")) {
      const auto versionEnd = line.find(' ');
      const auto codeEnd = line.find(' ', versionEnd + 1);

      headers.clear();
      statusText = codeEnd == std::string_view::npos ? "" : trim(line.substr(codeEnd + 1));
    } else if (trim(line).empty()) {
      long status = 0;
      curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &status);

      if (status >= 200) {
        Event event;
        event.status = status;
        event.statusText = std::move(statusText);
        event.headers = std::move(headers);

        if (!emit(std::move(event))) return 0;
        delivered = true;
      }
    } else {
      const auto colon = line.find(':');
      if (colon != std::string_view::npos) {
        headers.emplace_back(trim(line.substr(0, colon)), trim(line.substr(colon + 1)));
      }
    }

    return line.size();
  }
};

size_t onHeader(char *data, size_t size, size_t count, void *context) noexcept {
  try {
    return static_cast<Response *>(context)->receiveHeader(std::string_view(data, size * count));
  } catch (...) {
    return 0;
  }
}

size_t onBody(char *data, size_t size, size_t count, void *context) noexcept {
  const auto length = size * count;
  if (!length) return 0;

  try {
    Event event;
    event.data.assign(data, data + length);

    return static_cast<Response *>(context)->emit(std::move(event)) ? length : 0;
  } catch (...) {
    return 0;
  }
}

void check(CURLcode result) {
  if (result != CURLE_OK) throw std::runtime_error(curl_easy_strerror(result));
}

void check(CURLMcode result) {
  if (result != CURLM_OK) throw std::runtime_error(curl_multi_strerror(result));
}

struct HeaderOptions {
  curl_slist *head = nullptr;
  ~HeaderOptions() { curl_slist_free_all(head); }

  void append(const std::string &line) {
    auto *next = curl_slist_append(head, line.c_str());
    if (!next) throw std::bad_alloc();
    head = next;
  }
};

}  // namespace

void HttpTransfer::cancel() {
  cancelled_ = true;
  std::lock_guard lock(mutex_);
  if (multi_) curl_multi_wakeup(multi_);
}

void HttpTransfer::run(const std::function<bool(Event)> &emit) {
  Event event;

  try {
    static const auto initialized = curl_global_init(CURL_GLOBAL_DEFAULT);
    check(initialized);

    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> easy(curl_easy_init(), curl_easy_cleanup);
    std::unique_ptr<CURLM, decltype(&curl_multi_cleanup)> multi(curl_multi_init(), curl_multi_cleanup);
    if (!easy || !multi) throw std::runtime_error("Unable to initialize the HTTP transfer");

    Response response{easy.get(), emit, false, {}, {}};
    HeaderOptions headers;
    for (const auto &[name, value] : request_.headers) {
      // libcurl uses a semicolon to send an explicitly empty field.
      headers.append(name + (value.empty() ? ";" : ": " + value));
    }

    auto set = [&](CURLoption option, auto value) { check(curl_easy_setopt(easy.get(), option, value)); };
    set(CURLOPT_URL, request_.url.c_str());
    set(CURLOPT_PROTOCOLS_STR, "http,https");
    set(CURLOPT_CUSTOMREQUEST, request_.method.c_str());
    set(CURLOPT_HTTPHEADER, headers.head);
    set(CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
    set(CURLOPT_NOSIGNAL, 1L);
    set(CURLOPT_FOLLOWLOCATION, 0L);
    set(CURLOPT_ACCEPT_ENCODING, "gzip");
    set(CURLOPT_CAPATH, "/etc/security/certificates");

    set(CURLOPT_SUPPRESS_CONNECT_HEADERS, 1L);
    set(CURLOPT_PROXY, request_.proxyHost.c_str());
    set(CURLOPT_NOPROXY, "");
    if (!request_.proxyHost.empty()) {
      set(CURLOPT_PROXYPORT, request_.proxyPort);
      if (!request_.proxyUsername.empty()) {
        set(CURLOPT_PROXYUSERNAME, request_.proxyUsername.c_str());
        set(CURLOPT_PROXYPASSWORD, request_.proxyPassword.c_str());
      }
    }

    set(CURLOPT_HEADERFUNCTION, onHeader);
    set(CURLOPT_HEADERDATA, &response);
    set(CURLOPT_WRITEFUNCTION, onBody);
    set(CURLOPT_WRITEDATA, &response);

    if (request_.body) {
      const auto &body = *request_.body;
      set(CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(body.size()));
      set(CURLOPT_POSTFIELDS, body.empty() ? "" : body.data());
    }
    if (request_.method == "HEAD") set(CURLOPT_NOBODY, 1L);

    check(curl_multi_add_handle(multi.get(), easy.get()));
    {
      std::lock_guard lock(mutex_);
      multi_ = multi.get();
    }

    // The cancellation thread must stop seeing the handle before curl frees it.
    auto detach = [this, &multi, &easy](void *) {
      std::lock_guard lock(mutex_);
      multi_ = nullptr;
      curl_multi_remove_handle(multi.get(), easy.get());
    };
    std::unique_ptr<void, decltype(detach)> attached(multi.get(), detach);

    int running = 0;
    while (!cancelled_) {
      check(curl_multi_perform(multi.get(), &running));
      if (!running) break;
      check(curl_multi_poll(multi.get(), nullptr, 0, 1000, nullptr));
    }

    if (cancelled_) throw std::runtime_error("HTTP transfer was cancelled");

    int remaining = 0;
    auto *message = curl_multi_info_read(multi.get(), &remaining);
    if (message && message->msg == CURLMSG_DONE) check(message->data.result);
    if (!response.delivered) throw std::runtime_error("HTTP transfer returned no final response");
  } catch (const std::exception &error) {
    event.error = error.what();
  }

  emit(std::move(event));
}

}  // namespace expo::fetch
