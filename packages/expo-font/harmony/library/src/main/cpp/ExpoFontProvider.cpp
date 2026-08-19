#include "ExpoFontProvider.h"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace expo::harmony::font {
namespace {

constexpr const char *kServiceName = "ExpoFontService";

std::string percentDecode(std::string value) {
  std::string decoded;
  decoded.reserve(value.size());

  auto digit = [](char ch) -> int {
    if (ch >= '0' && ch <= '9') {
      return ch - '0';
    }
    if (ch >= 'a' && ch <= 'f') {
      return ch - 'a' + 10;
    }
    if (ch >= 'A' && ch <= 'F') {
      return ch - 'A' + 10;
    }
    return -1;
  };

  for (size_t i = 0; i < value.size(); ++i) {
    if (value[i] != '%') {
      decoded.push_back(value[i]);
      continue;
    }

    if (i + 2 >= value.size()) {
      throw CodedError("ERR_FONT_SOURCE", "Font URI has an invalid escape sequence.");
    }

    const int high = digit(value[i + 1]);
    const int low = digit(value[i + 2]);
    if (high < 0 || low < 0) {
      throw CodedError("ERR_FONT_SOURCE", "Font URI has an invalid escape sequence.");
    }

    const char ch = static_cast<char>((high << 4) | low);
    if (ch == '\0') {
      throw CodedError("ERR_FONT_SOURCE", "Font URI contains a NUL byte.");
    }

    decoded.push_back(ch);
    i += 2;
  }

  return decoded;
}

std::filesystem::path pathFromUri(const std::string &uri) {
  constexpr std::string_view prefix = "file://";
  if (!uri.starts_with(prefix)) {
    throw CodedError("ERR_FONT_SOURCE", "Harmony fonts must use a local file URI.");
  }

  auto encoded = uri.substr(prefix.size());
  constexpr std::string_view localhost = "localhost/";
  if (encoded.starts_with(localhost)) {
    encoded.erase(0, localhost.size() - 1);
  }

  const auto path = std::filesystem::path(percentDecode(encoded)).lexically_normal();
  if (!path.is_absolute()) {
    throw CodedError("ERR_FONT_SOURCE", "Font URI must contain an absolute local path.");
  }

  return path;
}

bool isBlank(const std::string &value) {
  return value.empty() || std::all_of(value.begin(), value.end(), [](unsigned char ch) {
           return std::isspace(ch) != 0;
         });
}

bool isInside(const std::filesystem::path &root, const std::filesystem::path &path) {
  auto rootIt = root.begin();
  auto pathIt = path.begin();

  for (; rootIt != root.end(); ++rootIt, ++pathIt) {
    if (pathIt == path.end() || *rootIt != *pathIt) {
      return false;
    }
  }

  return true;
}

class FontState final {
public:
  FontState(
      std::shared_ptr<RuntimeContext> context,
      std::vector<std::filesystem::path> roots)
      : context_(std::move(context)), roots_(std::move(roots)) {}

  std::vector<std::string> loaded() const {
    std::scoped_lock lock(mutex_);

    std::vector<std::string> families;
    families.reserve(fonts_.size());
    for (const auto &font : fonts_) {
      families.push_back(font.first);
    }

    return families;
  }

  std::optional<std::string> sourceFor(const std::string &family) const {
    std::scoped_lock lock(mutex_);

    const auto font = fonts_.find(family);
    if (font == fonts_.end() || font->second.empty()) {
      return std::nullopt;
    }

    return font->second.back();
  }

  void loadBundled(const std::string &family, const std::string &uri) {
    if (isBlank(family)) {
      throw CodedError("ERR_FONT_FAMILY", "Bundled font family cannot be empty.");
    }

    const auto source = validate(uri);

    {
      std::scoped_lock lock(mutex_);
      const auto font = fonts_.find(family);
      if (font != fonts_.end()
          && std::find(font->second.begin(), font->second.end(), source) != font->second.end()) {
        return;
      }
    }

    registerWithRnoh(family, source);

    std::scoped_lock lock(mutex_);
    auto font = fonts_.find(family);
    if (font == fonts_.end()) {
      fonts_.emplace(family, std::vector<std::string>{source});
    } else {
      font->second.push_back(source);
    }
  }

  void load(const std::string &family, const std::string &uri) {
    if (isBlank(family)) {
      throw CodedError("ERR_FONT_FAMILY", "Font family cannot be empty.");
    }

    const auto source = validate(uri);

    {
      std::scoped_lock lock(mutex_);
      const auto font = fonts_.find(family);
      if (font != fonts_.end() && font->second.size() == 1 && font->second[0] == source) {
        return;
      }
    }

    registerWithRnoh(family, source);

    std::scoped_lock lock(mutex_);
    fonts_[family] = {source};
  }

private:
  void registerWithRnoh(const std::string &family, const std::string &source) const {
    auto context = context_.lock();
    if (!context || !context->isAlive()) {
      throw CodedError("ERR_FONT_MANAGER", "The RNOH runtime is no longer available.");
    }

    context->invokePlatformServiceSync(
        kServiceName,
        "registerFont",
        folly::dynamic::array(family, source));
  }

  std::string validate(const std::string &uri) const {
    auto localUri = uri;

    if (uri.starts_with("asset://") || uri.starts_with("rawfile://")) {
      auto context = context_.lock();
      if (!context || !context->isAlive()) {
        throw CodedError("ERR_FONT_MANAGER", "The RNOH runtime is no longer available.");
      }

      const auto result = context->invokePlatformServiceSync(
          kServiceName,
          "materializeFont",
          folly::dynamic::array(uri));
      if (!result.isString()) {
        throw CodedError("ERR_FONT_SOURCE", "Harmony returned an invalid materialized font URI.");
      }

      localUri = result.getString(context->runtime()).utf8(context->runtime());
    }

    const auto path = pathFromUri(localUri);
    std::error_code error;
    const auto canonical = std::filesystem::canonical(path, error);

    if (error || !std::filesystem::is_regular_file(canonical)) {
      throw CodedError("ERR_FONT_SOURCE", "Font file '" + uri + "' does not exist.");
    }

    if (std::filesystem::file_size(canonical, error) == 0 || error) {
      throw CodedError("ERR_FONT_SOURCE", "Font file for the requested family is empty.");
    }

    const bool permitted = std::any_of(roots_.begin(), roots_.end(), [&](const auto &root) { return isInside(root, canonical); });
    if (!permitted) {
      throw CodedError("ERR_FONT_SOURCE_OUTSIDE_SANDBOX", "Font URI is outside the application sandbox.");
    }

    return canonical.string();
  }

  std::weak_ptr<RuntimeContext> context_;
  std::vector<std::filesystem::path> roots_;
  mutable std::mutex mutex_;
  std::map<std::string, std::vector<std::string>> fonts_;
};

std::filesystem::path directoryFromCore(const std::shared_ptr<RuntimeContext> &context, const std::string &method) {
  auto uri = context->callPlatformSync(method);

  return std::filesystem::weakly_canonical(pathFromUri(convertFromJS<std::string>(context, uri, method)));
}

void loadBundledFonts(
    const std::shared_ptr<RuntimeContext> &context,
    const std::shared_ptr<FontState> &state) {
  auto result = context->invokePlatformServiceSync(
      kServiceName, "bundledFonts", folly::dynamic::array());

  auto records = jsi::dynamicFromValue(context->runtime(), result);
  if (!records.isArray()) {
    return;
  }

  for (const auto &record : records) {
    if (!record.isObject() || !record.count("family") || !record.at("family").isString() || !record.count("uri") || !record.at("uri").isString()) {
      continue;
    }

    try {
      state->loadBundled(record.at("family").asString(), record.at("uri").asString());
    } catch (const CodedError &error) {
      if (error.code() == "ERR_FONT_MANAGER") {
        throw CodedError(error);
      }
    } catch (...) {
      // Platform font parsing/registration errors are isolated per entry.
    }
  }
}

class ExpoFontLoaderModule final : public ExpoModule {
public:
  explicit ExpoFontLoaderModule(std::shared_ptr<FontState> state) : state_(std::move(state)) {}

  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoFontLoader");

    module.function(typedFunction<std::vector<std::string>>(
        "getLoadedFonts", [state = state_]() { return state->loaded(); }));
    module.function(typedAsyncFunction<void, std::string, std::string>(
        "loadAsync", [state = state_](std::string family, std::string uri) {
          state->load(family, uri);
        },
        FunctionQueue::JavaScript));

    return std::move(module).build();
  }

private:
  std::shared_ptr<FontState> state_;
};

class ExpoFontUtilsModule final : public ExpoModule {
public:
  explicit ExpoFontUtilsModule(std::shared_ptr<FontState> state)
      : state_(std::move(state)) {}

  ModuleDefinition definition() override {
    ModuleBuilder module("ExpoFontUtils");

    module.function(FunctionDefinition{
        .name = "renderToImageAsync",
        .arity = 2,
        .requiredArity = 1,
        .async = true,
        .queue = FunctionQueue::JavaScript,
        .body = [state = state_](Invocation &invocation) {
          const auto glyphs = convertFromJS<std::string>(
              invocation.sharedContext(), invocation.argument(0), invocation.path());

          folly::dynamic options = folly::dynamic::object();
          if (invocation.argumentCount() > 1
              && !invocation.argument(1).isUndefined()
              && !invocation.argument(1).isNull()) {
            options = jsi::dynamicFromValue(invocation.runtime(), invocation.argument(1));
            if (!options.isObject()) {
              throw CodedError(
                  "ERR_FONT_RENDER_OPTIONS",
                  "ExpoFontUtils.renderToImageAsync expected an options object.");
            }
          }

          if (options.count("fontFamily") && options.at("fontFamily").isString()) {
            const auto source = state->sourceFor(options.at("fontFamily").asString());
            if (source) {
              options["fontPath"] = *source;
            }
          }

          return invocation.context().invokePlatformService(
              kServiceName,
              "renderToImage",
              folly::dynamic::array(glyphs, std::move(options)));
        }});

    return std::move(module).build();
  }

private:
  std::shared_ptr<FontState> state_;
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoFontProvider::modules(
    const std::shared_ptr<RuntimeContext> &context) {
  auto state = std::make_shared<FontState>(
      context,
      std::vector<std::filesystem::path>{
          directoryFromCore(context, "getDocumentsDirectory"),
          directoryFromCore(context, "getCacheDirectory"),
          directoryFromCore(context, "getTemporaryDirectory"),
      });

  loadBundledFonts(context, state);

  return {
      std::make_shared<ExpoFontLoaderModule>(state),
      std::make_shared<ExpoFontUtilsModule>(std::move(state)),
  };
}
}  // namespace expo::harmony::font
