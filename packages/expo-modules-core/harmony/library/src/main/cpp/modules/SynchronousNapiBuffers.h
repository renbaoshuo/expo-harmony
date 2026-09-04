#pragma once

#include <cstdint>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <vector>

#include <napi/native_api.h>

namespace expo::harmony {

// Contains no runtime handles. Storage stays fixed once exposed to ArkTS.
struct SynchronousBinarySnapshot final {
  std::vector<uint8_t> bytes;
  size_t offset;
  size_t end;
  bool writable = false;
};

// Lives entirely on the ArkTS thread. Writable views are scoped to the call:
// detach them before native code reads the snapshots on the JS thread.
class SynchronousNapiBuffers final {
public:
  explicit SynchronousNapiBuffers(napi_env env) : env_(env) {
    if (napi_open_handle_scope(env_, &scope_) != napi_ok) {
      throw std::runtime_error("Could not open the synchronous binary handle scope.");
    }
  }
  ~SynchronousNapiBuffers() {
    detach();
    napi_close_handle_scope(env_, scope_);
  }
  SynchronousNapiBuffers(const SynchronousNapiBuffers &) = delete;
  SynchronousNapiBuffers &operator=(const SynchronousNapiBuffers &) = delete;

  napi_value get(const std::shared_ptr<SynchronousBinarySnapshot> &snapshot) {
    const auto found = buffers_.find(snapshot.get());
    if (found != buffers_.end()) return found->second.value;

    napi_value buffer = nullptr;
    napi_status status;
    if (snapshot->writable && !snapshot->bytes.empty()) {
      // Only the native snapshot is retained by the finalizer, never a JSI
      // handle or a pointer owned by the JS runtime.
      auto owner = std::make_unique<std::shared_ptr<SynchronousBinarySnapshot>>(snapshot);
      status = napi_create_external_arraybuffer(
          env_, snapshot->bytes.data(), snapshot->bytes.size(),
          [](napi_env, void *, void *hint) {
            delete static_cast<std::shared_ptr<SynchronousBinarySnapshot> *>(hint);
          }, owner.get(), &buffer);
      if (status == napi_ok) owner.release();
    } else {
      // Empty buffers need no external allocation; ordinary inputs keep their
      // existing independent-storage and retention semantics.
      void *data = nullptr;
      status = napi_create_arraybuffer(env_, snapshot->bytes.size(), &data, &buffer);
      if (status == napi_ok && !snapshot->bytes.empty()) {
        std::memcpy(data, snapshot->bytes.data(), snapshot->bytes.size());
      }
    }
    if (status != napi_ok) {
      throw std::runtime_error("Could not create a synchronous ArkTS binary buffer.");
    }
    buffers_.emplace(snapshot.get(), Entry{buffer, snapshot->writable});
    return buffer;
  }

  // Detect user detachment/transfer before ending the borrow. Do not commit
  // stale native bytes if ArkTS has changed the buffer's storage.
  napi_status finish() noexcept {
    for (const auto &[snapshot, entry] : buffers_) {
      if (!entry.writable) continue;
      bool detached = false;
      auto status = napi_is_detached_arraybuffer(env_, entry.value, &detached);
      if (status != napi_ok) return status;
      if (detached) return napi_generic_failure;
      void *data = nullptr;
      size_t length = 0;
      status = napi_get_arraybuffer_info(env_, entry.value, &data, &length);
      if (status != napi_ok) return status;
      if (length != snapshot->bytes.size() ||
          (length > 0 && data != snapshot->bytes.data())) return napi_generic_failure;
    }
    return detach();
  }

private:
  // Also attempted by the destructor on every exceptional exit. The external
  // finalizer retains storage even if the platform refuses detachment.
  napi_status detach() noexcept {
    napi_status result = napi_ok;
    for (auto &[snapshot, entry] : buffers_) {
      if (!entry.writable) continue;
      const auto status = napi_detach_arraybuffer(env_, entry.value);
      if (status == napi_ok) entry.writable = false;
      else result = status;
    }
    return result;
  }

  struct Entry {
    napi_value value;
    bool writable;
  };
  napi_env env_;
  napi_handle_scope scope_ = nullptr;
  std::unordered_map<const SynchronousBinarySnapshot *, Entry> buffers_;
};

} // namespace expo::harmony
