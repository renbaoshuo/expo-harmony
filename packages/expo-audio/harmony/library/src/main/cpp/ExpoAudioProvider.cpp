#include "ExpoAudioProvider.h"

#include <atomic>
#include <exception>
#include <memory>
#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

#include <hilog/log.h>

namespace jsi = facebook::jsi;

namespace expo::harmony::audio {
namespace {

constexpr const char *kModuleName = "ExpoAudio";
constexpr const char *kServiceName = "ExpoAudioService";
constexpr const char *kPlayerClass = "AudioPlayer";
constexpr const char *kRecorderClass = "AudioRecorder";
constexpr const char *kPlaylistClass = "AudioPlaylist";
constexpr const char *kReleaseMessage = "EXPO_AUDIO_RELEASE_OBJECT";
constexpr unsigned int kLogDomain = 0xD00390A;
constexpr const char *kLogTag = "ExpoAudio";
constexpr size_t kReleaseAttempts = 3;

folly::dynamic copyArguments(Invocation &invocation, size_t offset = 0) {
  auto arguments = folly::dynamic::array();

  for (size_t index = offset; index < invocation.argumentCount(); ++index) {
    arguments.push_back(
        jsi::dynamicFromValue(invocation.runtime(), invocation.argument(index)));
  }

  return arguments;
}

void appendArguments(
    folly::dynamic &destination,
    folly::dynamic source) {
  for (auto &value : source) {
    destination.push_back(std::move(value));
  }
}

class AudioSharedObject : public NativeSharedObject {
public:
  AudioSharedObject(
      std::weak_ptr<RuntimeContext> context,
      std::string kind)
      : context_(std::move(context)),
        kind_(std::move(kind)) {}

  void setObjectId(long objectId) noexcept {
    objectId_ = objectId;
  }

  long objectId() const noexcept {
    return objectId_;
  }

  const std::string &kind() const noexcept {
    return kind_;
  }

  void releasePlatformObject() noexcept {
    if (released_.exchange(true, std::memory_order_acq_rel)) {
      return;
    }

    auto context = context_.lock();

    if (!context || !context->isAlive() || objectId_ <= 0) {
      return;
    }

    for (size_t attempt = 0; attempt < kReleaseAttempts; ++attempt) {
      try {
        context->postPlatformMessage(
            kReleaseMessage,
            folly::dynamic::object("objectId", objectId_)("kind", kind_));
        return;
      } catch (const std::exception &error) {
        if (attempt + 1 < kReleaseAttempts) {
          continue;
        }

        OH_LOG_Print(
            LOG_APP,
            LOG_WARN,
            kLogDomain,
            kLogTag,
            "Unable to release %{public}s %{public}ld after retries: %{private}s",
            kind_.c_str(),
            objectId_,
            error.what());
      } catch (...) {
        if (attempt + 1 < kReleaseAttempts) {
          continue;
        }

        OH_LOG_Print(
            LOG_APP,
            LOG_WARN,
            kLogDomain,
            kLogTag,
            "Unable to release %{public}s %{public}ld after retries",
            kind_.c_str(),
            objectId_);
      }
    }

    released_.store(false, std::memory_order_release);
  }

  void sharedObjectDidRelease() override {
    releasePlatformObject();
    NativeSharedObject::sharedObjectDidRelease();
  }

private:
  std::weak_ptr<RuntimeContext> context_;
  std::string kind_;
  long objectId_{0};
  std::atomic_bool released_{false};
};

class AudioPlayerObject final : public AudioSharedObject {
public:
  explicit AudioPlayerObject(std::weak_ptr<RuntimeContext> context)
      : AudioSharedObject(std::move(context), "player") {}
};

class AudioRecorderObject final : public AudioSharedObject {
public:
  explicit AudioRecorderObject(std::weak_ptr<RuntimeContext> context)
      : AudioSharedObject(std::move(context), "recorder") {}
};

class AudioPlaylistObject final : public AudioSharedObject {
public:
  explicit AudioPlaylistObject(std::weak_ptr<RuntimeContext> context)
      : AudioSharedObject(std::move(context), "playlist") {}
};

std::shared_ptr<AudioSharedObject> requireAudioObject(
    Invocation &invocation,
    const std::shared_ptr<NativeSharedObject> &object) {
  auto owner = std::dynamic_pointer_cast<AudioSharedObject>(object);

  if (!owner) {
    throw CodedError(
        "ERR_AUDIO_SHARED_OBJECT",
        invocation.path() + " received an incompatible native owner.");
  }

  return owner;
}

folly::dynamic objectArguments(
    const AudioSharedObject &owner,
    const char *operation,
    folly::dynamic values = folly::dynamic::array()) {
  auto arguments = folly::dynamic::array(
      owner.objectId(), owner.kind(), operation);

  appendArguments(arguments, std::move(values));

  return arguments;
}

template <typename Object>
std::shared_ptr<Object> createObject(Invocation &invocation) {
  auto context = invocation.sharedContext();
  auto object = std::make_shared<Object>(context);

  const auto objectId = context->registerNativeSharedObject(object);

  object->setObjectId(objectId);

  auto arguments = folly::dynamic::array(objectId, object->kind());

  appendArguments(arguments, copyArguments(invocation));

  try {
    (void)context->invokePlatformServiceSync(
        kServiceName, "createObject", std::move(arguments));
  } catch (const std::exception &error) {
    context->releaseSharedObject(objectId);

    throw CodedError(
        "ERR_AUDIO_CREATE_OBJECT",
        invocation.path() + " failed to create its native audio object: " + error.what());
  } catch (...) {
    context->releaseSharedObject(objectId);

    throw CodedError(
        "ERR_AUDIO_CREATE_OBJECT",
        invocation.path() + " failed to create its native audio object.");
  }

  return object;
}

SharedObjectPropertyDefinition objectProperty(
    std::string name,
    bool writable = false) {
  auto key = name;

  SharedObjectPropertyDefinition definition{
      .name = std::move(name),
      .getter = [key](
                    Invocation &invocation,
                    const std::shared_ptr<NativeSharedObject> &object) {
        auto owner = requireAudioObject(invocation, object);

        return invocation.context().invokePlatformServiceSync(
            kServiceName,
            "getObjectProperty",
            objectArguments(*owner, key.c_str()));
      }};

  if (writable) {
    definition.setter = [key](
                            Invocation &invocation,
                            const std::shared_ptr<NativeSharedObject> &object,
                            const jsi::Value &value) {
      auto owner = requireAudioObject(invocation, object);
      auto values = folly::dynamic::array(
          jsi::dynamicFromValue(invocation.runtime(), value));

      (void)invocation.context().invokePlatformServiceSync(
          kServiceName,
          "setObjectProperty",
          objectArguments(*owner, key.c_str(), std::move(values)));
    };
  }

  return definition;
}

SharedObjectFunctionDefinition objectFunction(
    std::string name,
    size_t arity,
    size_t requiredArity,
    bool async = false) {
  auto operation = name;
  return SharedObjectFunctionDefinition{
      .name = std::move(name),
      .arity = arity,
      .requiredArity = requiredArity,
      .async = async,
      .queue = FunctionQueue::JavaScript,
      .body = [operation = std::move(operation),
               arity,
               requiredArity,
               async](
                  Invocation &invocation,
                  const std::shared_ptr<NativeSharedObject> &object) {
        invocation.requireArgumentCount(requiredArity, arity);

        auto owner = requireAudioObject(invocation, object);
        auto arguments = objectArguments(
            *owner, operation.c_str(), copyArguments(invocation));

        if (async) {
          return invocation.context().invokePlatformService(
              kServiceName, "callObject", std::move(arguments));
        }

        return invocation.context().invokePlatformServiceSync(
            kServiceName, "callObject", std::move(arguments));
      }};
}

void observeObject(
    RuntimeContext &context,
    const std::shared_ptr<NativeSharedObject> &object,
    const std::string &eventName,
    bool observing) {
  auto owner = std::dynamic_pointer_cast<AudioSharedObject>(object);

  if (!owner) {
    return;
  }

  try {
    (void)context.invokePlatformServiceSync(
        kServiceName,
        "setObjectObserving",
        folly::dynamic::array(
            owner->objectId(), owner->kind(), eventName, observing));
  } catch (const std::exception &error) {
    OH_LOG_Print(
        LOG_APP,
        LOG_WARN,
        kLogDomain,
        kLogTag,
        "Unable to update %{public}s event observation: %{private}s",
        owner->kind().c_str(),
        error.what());
  }
}

ClassDefinition playerDefinition() {
  ClassDefinition definition;

  definition.name = kPlayerClass;
  definition.nativeType = std::type_index(typeid(AudioPlayerObject));
  definition.constructorArity = 4;
  definition.constructorRequiredArity = 4;
  definition.constructor = [](Invocation &invocation) {
    return createObject<AudioPlayerObject>(invocation);
  };

  definition.events = {"playbackStatusUpdate", "audioSampleUpdate"};
  definition.properties = {
      objectProperty("id"),
      objectProperty("playing"),
      objectProperty("muted", true),
      objectProperty("loop", true),
      objectProperty("paused"),
      objectProperty("isLoaded"),
      objectProperty("isAudioSamplingSupported"),
      objectProperty("isBuffering"),
      objectProperty("currentTime"),
      objectProperty("duration"),
      objectProperty("volume", true),
      objectProperty("playbackRate"),
      objectProperty("shouldCorrectPitch", true),
      objectProperty("currentStatus"),
  };
  definition.functions = {
      objectFunction("play", 0, 0),
      objectFunction("pause", 0, 0),
      objectFunction("replace", 1, 1),
      objectFunction("seekTo", 3, 1, true),
      objectFunction("setPlaybackRate", 2, 1),
      objectFunction("setAudioSamplingEnabled", 1, 1),
      objectFunction("setActiveForLockScreen", 3, 1),
      objectFunction("updateLockScreenMetadata", 1, 1),
      objectFunction("clearLockScreenControls", 0, 0),
      objectFunction("remove", 0, 0),
  };

  definition.startObservers.push_back({.everyEvent = true,
                                       .body = [](RuntimeContext &context,
                                                  const std::shared_ptr<NativeSharedObject> &object,
                                                  const std::string &eventName) {
                                         observeObject(context, object, eventName, true);
                                       }});
  definition.stopObservers.push_back({.everyEvent = true,
                                      .body = [](RuntimeContext &context,
                                                 const std::shared_ptr<NativeSharedObject> &object,
                                                 const std::string &eventName) {
                                        observeObject(context, object, eventName, false);
                                      }});

  return definition;
}

ClassDefinition recorderDefinition() {
  ClassDefinition definition;

  definition.name = kRecorderClass;
  definition.nativeType = std::type_index(typeid(AudioRecorderObject));
  definition.constructorArity = 1;
  definition.constructorRequiredArity = 1;
  definition.constructor = [](Invocation &invocation) {
    return createObject<AudioRecorderObject>(invocation);
  };

  definition.events = {"recordingStatusUpdate"};
  definition.properties = {
      objectProperty("id"),
      objectProperty("currentTime"),
      objectProperty("isRecording"),
      objectProperty("uri"),
  };
  definition.functions = {
      objectFunction("record", 1, 0),
      objectFunction("stop", 0, 0, true),
      objectFunction("pause", 0, 0),
      objectFunction("getAvailableInputs", 0, 0),
      objectFunction("getCurrentInput", 0, 0, true),
      objectFunction("setInput", 1, 1),
      objectFunction("getStatus", 0, 0),
      objectFunction("startRecordingAtTime", 1, 1),
      objectFunction("prepareToRecordAsync", 1, 0, true),
      objectFunction("recordForDuration", 1, 1),
  };

  definition.startObservers.push_back({.everyEvent = true,
                                       .body = [](RuntimeContext &context,
                                                  const std::shared_ptr<NativeSharedObject> &object,
                                                  const std::string &eventName) {
                                         observeObject(context, object, eventName, true);
                                       }});
  definition.stopObservers.push_back({.everyEvent = true,
                                      .body = [](RuntimeContext &context,
                                                 const std::shared_ptr<NativeSharedObject> &object,
                                                 const std::string &eventName) {
                                        observeObject(context, object, eventName, false);
                                      }});

  return definition;
}

ClassDefinition playlistDefinition() {
  ClassDefinition definition;

  definition.name = kPlaylistClass;
  definition.nativeType = std::type_index(typeid(AudioPlaylistObject));
  definition.constructorArity = 3;
  definition.constructorRequiredArity = 3;
  definition.constructor = [](Invocation &invocation) {
    return createObject<AudioPlaylistObject>(invocation);
  };

  definition.events = {"playlistStatusUpdate", "trackChanged"};
  definition.properties = {
      objectProperty("id"),
      objectProperty("currentIndex"),
      objectProperty("trackCount"),
      objectProperty("sources"),
      objectProperty("playing"),
      objectProperty("muted", true),
      objectProperty("isLoaded"),
      objectProperty("isBuffering"),
      objectProperty("currentTime"),
      objectProperty("duration"),
      objectProperty("volume", true),
      objectProperty("playbackRate", true),
      objectProperty("loop", true),
      objectProperty("currentStatus"),
  };
  definition.functions = {
      objectFunction("play", 0, 0),
      objectFunction("pause", 0, 0),
      objectFunction("next", 0, 0),
      objectFunction("previous", 0, 0),
      objectFunction("skipTo", 1, 1),
      objectFunction("seekTo", 1, 1, true),
      objectFunction("add", 1, 1),
      objectFunction("insert", 2, 2),
      objectFunction("remove", 1, 1),
      objectFunction("clear", 0, 0),
      objectFunction("destroy", 0, 0),
  };

  definition.startObservers.push_back({.everyEvent = true,
                                       .body = [](RuntimeContext &context,
                                                  const std::shared_ptr<NativeSharedObject> &object,
                                                  const std::string &eventName) {
                                         observeObject(context, object, eventName, true);
                                       }});
  definition.stopObservers.push_back({.everyEvent = true,
                                      .body = [](RuntimeContext &context,
                                                 const std::shared_ptr<NativeSharedObject> &object,
                                                 const std::string &eventName) {
                                        observeObject(context, object, eventName, false);
                                      }});

  return definition;
}

FunctionDefinition moduleFunction(
    std::string name,
    size_t arity,
    size_t requiredArity) {
  auto method = name;
  return FunctionDefinition{
      .name = std::move(name),
      .arity = arity,
      .requiredArity = requiredArity,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [method = std::move(method),
               arity,
               requiredArity](Invocation &invocation) {
        invocation.requireArgumentCount(requiredArity, arity);

        return invocation.context().invokePlatformService(
            kServiceName, method, copyArguments(invocation));
      }};
}

void invokeLifecycle(RuntimeContext &context, const char *method) {
  try {
    auto result = context.invokePlatformService(kServiceName, method);
    auto &runtime = context.runtime();

    if (!result.isObject()) {
      OH_LOG_Print(
          LOG_APP,
          LOG_WARN,
          kLogDomain,
          kLogTag,
          "Expo Audio lifecycle call %{public}s did not return a Promise",
          method);
      return;
    }

    auto promise = result.getObject(runtime);
    auto catchValue = promise.getProperty(runtime, "catch");
    if (!catchValue.isObject() || !catchValue.getObject(runtime).isFunction(runtime)) {
      OH_LOG_Print(
          LOG_APP,
          LOG_WARN,
          kLogDomain,
          kLogTag,
          "Expo Audio lifecycle call %{public}s returned an invalid Promise",
          method);
      return;
    }

    auto catchFunction = catchValue.getObject(runtime).getFunction(runtime);
    auto operation = std::string(method);
    auto onRejected = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "logExpoAudioLifecycleError"),
        1,
        [operation = std::move(operation)](
            jsi::Runtime &currentRuntime,
            const jsi::Value &,
            const jsi::Value *arguments,
            size_t count) -> jsi::Value {
          std::string message = "unknown platform error";

          try {
            if (count > 0) {
              if (arguments[0].isObject()) {
                auto error = arguments[0].getObject(currentRuntime);
                auto value = error.getProperty(currentRuntime, "message");
                if (value.isString()) {
                  message = value.getString(currentRuntime).utf8(currentRuntime);
                } else {
                  message = arguments[0].toString(currentRuntime).utf8(currentRuntime);
                }
              } else {
                message = arguments[0].toString(currentRuntime).utf8(currentRuntime);
              }
            }
          } catch (...) {
          }

          OH_LOG_Print(
              LOG_APP,
              LOG_WARN,
              kLogDomain,
              kLogTag,
              "Expo Audio lifecycle call %{public}s rejected: %{private}s",
              operation.c_str(),
              message.c_str());

          return jsi::Value::undefined();
        });

    (void)catchFunction.callWithThis(runtime, promise, onRejected);
  } catch (const std::exception &error) {
    OH_LOG_Print(
        LOG_APP,
        LOG_WARN,
        kLogDomain,
        kLogTag,
        "Expo Audio lifecycle call %{public}s failed: %{private}s",
        method,
        error.what());
  }
}

class ExpoAudioModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.klass(playerDefinition());
    module.klass(recorderDefinition());
    module.klass(playlistDefinition());

    module.function(moduleFunction("setIsAudioActiveAsync", 1, 1));
    module.function(moduleFunction("setAudioModeAsync", 1, 1));
    module.function(moduleFunction("requestRecordingPermissionsAsync", 0, 0));
    module.function(moduleFunction("requestNotificationPermissionsAsync", 0, 0));
    module.function(moduleFunction("getRecordingPermissionsAsync", 0, 0));
    module.function(moduleFunction("preload", 2, 2));
    module.function(moduleFunction("clearPreloadedSource", 1, 1));
    module.function(moduleFunction("clearAllPreloadedSources", 0, 0));
    module.function(moduleFunction("getPreloadedSources", 0, 0));

    module.onBackground([](RuntimeContext &context) {
      invokeLifecycle(context, "background");
    });
    module.onForeground([](RuntimeContext &context) {
      invokeLifecycle(context, "foreground");
    });
    module.onDestroy([](RuntimeContext &context) {
      invokeLifecycle(context, "destroy");
    });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoAudioProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoAudioModule>()};
}

}  // namespace expo::harmony::audio
