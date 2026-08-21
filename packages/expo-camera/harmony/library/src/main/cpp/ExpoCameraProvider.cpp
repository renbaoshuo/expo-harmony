#include "ExpoCameraProvider.h"

#include <exception>
#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

#include <hilog/log.h>

namespace jsi = facebook::jsi;

namespace expo::harmony::camera {
namespace {

constexpr const char *kModuleName = "ExpoCamera";
constexpr const char *kServiceName = "ExpoCameraService";
constexpr const char *kComponentName = "ViewManagerAdapter_ExpoCamera";
constexpr unsigned int kLogDomain = 0xD003901;
constexpr const char *kLogTag = "ExpoCamera";

void invokeLifecycle(RuntimeContext &context, const char *method) {
  try {
    context.invokePlatformService(kServiceName, method);
  } catch (const std::exception &error) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kLogDomain,
        kLogTag,
        "Expo Camera lifecycle call %{public}s failed: %{private}s",
        method,
        error.what());
  } catch (...) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kLogDomain,
        kLogTag,
        "Expo Camera lifecycle call %{public}s failed with an unknown native exception",
        method);
  }
}

class PictureRefObject final : public NativeSharedObject {
public:
  PictureRefObject(std::string uri, double width, double height)
      : uri_(std::move(uri)), width_(width), height_(height) {}

  std::string nativeRefType() const override {
    return "image";
  }

  const std::string &uri() const noexcept {
    return uri_;
  }

  double width() const noexcept {
    return width_;
  }

  double height() const noexcept {
    return height_;
  }

private:
  std::string uri_;
  double width_;
  double height_;
};

folly::dynamic copyArguments(Invocation &invocation, size_t offset = 0) {
  auto args = folly::dynamic::array();
  for (size_t i = offset; i < invocation.argumentCount(); ++i) {
    args.push_back(
        jsi::dynamicFromValue(invocation.runtime(), invocation.argument(i)));
  }

  return args;
}

FunctionDefinition platformFunction(
    std::string name,
    size_t arity,
    size_t required,
    std::string method) {
  return FunctionDefinition{
      .name = std::move(name),
      .arity = arity,
      .requiredArity = required,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [method = std::move(method),
               required,
               arity](Invocation &invocation) {
        invocation.requireArgumentCount(required, arity);

        return invocation.context().invokePlatformService(
            kServiceName, method, copyArguments(invocation));
      }};
}

FunctionDefinition viewPlatformFunction(
    std::string name,
    size_t arity,
    size_t required,
    std::string method) {
  return FunctionDefinition{
      .name = std::move(name),
      .arity = arity,
      .requiredArity = required,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [method = std::move(method),
               required,
               arity](Invocation &invocation) {
        invocation.requireArgumentCount(required, arity);

        const auto handle = requireViewHandle(invocation, kComponentName);
        auto args = folly::dynamic::array(handle.tag());
        auto values = copyArguments(invocation);
        for (auto &value : values) {
          args.push_back(std::move(value));
        }

        return invocation.context().invokePlatformService(
            kServiceName, method, std::move(args));
      }};
}

FunctionDefinition pictureViewPlatformFunction() {
  return FunctionDefinition{
      .name = "takePicture",
      .arity = 1,
      .requiredArity = 1,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [](Invocation &invocation) {
        invocation.requireArgumentCount(1, 1);

        const auto handle = requireViewHandle(invocation, kComponentName);
        auto args = folly::dynamic::array(handle.tag());
        args.push_back(jsi::dynamicFromValue(
            invocation.runtime(), invocation.argument(0)));

        auto context = invocation.sharedContext();
        auto promise = context->invokePlatformService(
            kServiceName, "takePicture", std::move(args));
        if (!promise.isObject()) {
          throw CodedError(
              "ERR_PLATFORM_ADAPTER",
              "The Harmony camera did not return a Promise.");
        }

        auto object = promise.getObject(invocation.runtime());
        auto then = object.getProperty(invocation.runtime(), "then")
                        .getObject(invocation.runtime())
                        .getFunction(invocation.runtime());
        auto materialize = jsi::Function::createFromHostFunction(
            invocation.runtime(),
            jsi::PropNameID::forAscii(
                invocation.runtime(), "materializeExpoCameraPicture"),
            1,
            [context](
                jsi::Runtime &runtime,
                const jsi::Value &,
                const jsi::Value *arguments,
                size_t count) -> jsi::Value {
              if (count == 0 || !arguments[0].isObject()) {
                return count == 0
                         ? jsi::Value::undefined()
                         : jsi::Value(runtime, arguments[0]);
              }

              auto result = arguments[0].getObject(runtime);
              auto marker = result.getProperty(runtime, "pictureRef");
              if (!marker.isBool() || !marker.getBool()) {
                return jsi::Value(runtime, arguments[0]);
              }

              auto uri = result.getProperty(runtime, "uri");
              auto width = result.getProperty(runtime, "width");
              auto height = result.getProperty(runtime, "height");
              if (!uri.isString() || !width.isNumber() || !height.isNumber()) {
                throw CodedError(
                    "ERR_CAMERA_PICTURE_REF",
                    "The Harmony camera returned an invalid picture reference.");
              }

              return context->materializeNativeSharedObject(
                  kModuleName,
                  "Picture",
                  std::make_shared<PictureRefObject>(
                      uri.asString(runtime).utf8(runtime),
                      width.asNumber(),
                      height.asNumber()));
            });

        return then.callWithThis(invocation.runtime(), object, materialize);
      }};
}

FunctionDefinition eventPlatformFunction(
    std::string name,
    size_t arity,
    size_t required,
    std::string method,
    std::string event) {
  return FunctionDefinition{
      .name = std::move(name),
      .arity = arity,
      .requiredArity = required,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [method = std::move(method),
               event = std::move(event),
               required,
               arity](Invocation &invocation) {
        invocation.requireArgumentCount(required, arity);

        auto context = invocation.sharedContext();
        auto promise = context->invokePlatformService(
            kServiceName, method, copyArguments(invocation));
        if (!promise.isObject()) {
          throw CodedError(
              "ERR_PLATFORM_ADAPTER",
              "The Harmony barcode scanner did not return a Promise.");
        }

        auto object = promise.getObject(invocation.runtime());
        auto then = object.getProperty(invocation.runtime(), "then")
                        .getObject(invocation.runtime())
                        .getFunction(invocation.runtime());
        auto emit = jsi::Function::createFromHostFunction(
            invocation.runtime(),
            jsi::PropNameID::forAscii(
                invocation.runtime(), "emitExpoCameraEvent"),
            1,
            [context, event](
                jsi::Runtime &runtime,
                const jsi::Value &,
                const jsi::Value *arguments,
                size_t count) -> jsi::Value {
              if (count > 0 && !arguments[0].isNull() && !arguments[0].isUndefined()) {
                context->emitModuleEvent(
                    kModuleName,
                    event,
                    {jsi::dynamicFromValue(runtime, arguments[0])});
              }

              return jsi::Value::undefined();
            });

        return then.callWithThis(invocation.runtime(), object, emit);
      }};
}

jsi::Value stringMap(
    Invocation &invocation,
    std::initializer_list<std::pair<const char *, const char *>> entries) {
  folly::dynamic map = folly::dynamic::object();
  for (const auto &[key, entry] : entries) {
    map[key] = entry;
  }

  return jsi::valueFromDynamic(invocation.runtime(), map);
}

class ExpoCameraModule final : public ExpoModule {
public:
  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);

    module.constant("Type", [](Invocation &invocation) {
      return stringMap(invocation, {{"front", "front"}, {"back", "back"}});
    });
    module.constant("FlashMode", [](Invocation &invocation) {
      return stringMap(
          invocation,
          {{"off", "off"},
           {"on", "on"},
           {"auto", "auto"},
           {"screen", "screen"}});
    });
    module.property(PropertyDefinition{
        .name = "isModernBarcodeScannerAvailable",
        .getter = [](Invocation &invocation) {
          return invocation.context().invokePlatformServiceSync(
              kServiceName,
              "isModernBarcodeScannerAvailable");
        }});
    module.property(typedProperty<bool>(
        "toggleRecordingAsyncAvailable", [] { return true; }));
    module.events({"onModernBarcodeScanned"});

    ClassDefinitionBuilder<PictureRefObject> picture("Picture");
    picture.extends("SharedRef");
    picture.constructor<>([]() -> std::shared_ptr<PictureRefObject> {
      throw CodedError(
          "ERR_CAMERA_PICTURE_REF",
          "Picture references can only be created by the camera.");
    });
    picture.property(typedSharedProperty<PictureRefObject, double>(
        "width", [](PictureRefObject &owner) { return owner.width(); }));
    picture.property(typedSharedProperty<PictureRefObject, double>(
        "height", [](PictureRefObject &owner) { return owner.height(); }));
    picture.function(SharedObjectFunctionDefinition{
        .name = "savePictureAsync",
        .arity = 1,
        .requiredArity = 0,
        .async = true,
        .queue = FunctionQueue::JavaScript,
        .body = [](Invocation &invocation,
                   const std::shared_ptr<NativeSharedObject> &object) {
          auto owner = std::dynamic_pointer_cast<PictureRefObject>(object);
          if (!owner) {
            throw CodedError(
                "ERR_CAMERA_PICTURE_REF",
                "The picture reference has an incompatible native owner.");
          }

          auto args = folly::dynamic::array(owner->uri());
          if (invocation.argumentCount() > 0) {
            args.push_back(jsi::dynamicFromValue(
                invocation.runtime(), invocation.argument(0)));
          }

          return invocation.context().invokePlatformService(
              kServiceName, "savePicture", std::move(args));
        }});
    module.klass(std::move(picture).build());

    module.function(platformFunction(
        "isAvailableAsync", 0, 0, "isAvailable"));
    module.function(platformFunction(
        "getCameraPermissionsAsync", 0, 0, "getCameraPermissions"));
    module.function(platformFunction(
        "requestCameraPermissionsAsync", 0, 0, "requestCameraPermissions"));
    module.function(platformFunction(
        "getMicrophonePermissionsAsync", 0, 0, "getMicrophonePermissions"));
    module.function(platformFunction(
        "requestMicrophonePermissionsAsync", 0, 0, "requestMicrophonePermissions"));
    module.function(platformFunction(
        "getAvailableVideoCodecsAsync", 0, 0, "getAvailableVideoCodecs"));
    module.function(platformFunction(
        "scanFromURLAsync", 2, 1, "scanFromURL"));
    module.function(eventPlatformFunction(
        "launchScanner", 1, 0, "launchScanner", "onModernBarcodeScanned"));
    module.function(platformFunction(
        "dismissScanner", 0, 0, "dismissScanner"));

    ViewDefinitionBuilder view("Default");
    view.defaultView()
        .componentName(kComponentName)
        .prototypeName(kModuleName)
        .prop("facing")
        .prop("flashMode")
        .prop("selectedLens")
        .prop("enableTorch")
        .prop("pictureSize")
        .prop("zoom")
        .prop("mode")
        .prop("barcodeScannerEnabled")
        .prop("barcodeScannerSettings")
        .prop("mute")
        .prop("animateShutter")
        .prop("videoQuality")
        .prop("videoStabilizationMode")
        .prop("autoFocus")
        .prop("responsiveOrientationWhenOrientationLocked")
        .prop("mirror")
        .prop("active")
        .prop("videoBitrate")
        .prop("ratio")
        .events({
            "onCameraReady",
            "onMountError",
            "onPictureSaved",
            "onBarcodeScanned",
            "onResponsiveOrientationChanged",
            "onAvailableLensesChanged",
        })
        .function(pictureViewPlatformFunction())
        .function(viewPlatformFunction(
            "getAvailablePictureSizes", 0, 0, "getAvailablePictureSizes"))
        .function(viewPlatformFunction(
            "getAvailableLenses", 0, 0, "getAvailableLenses"))
        .function(viewPlatformFunction(
            "record", 1, 0, "record"))
        .function(viewPlatformFunction(
            "toggleRecording", 0, 0, "toggleRecording"))
        .function(viewPlatformFunction(
            "stopRecording", 0, 0, "stopRecording"))
        .function(viewPlatformFunction(
            "resumePreview", 0, 0, "resumePreview"))
        .function(viewPlatformFunction(
            "pausePreview", 0, 0, "pausePreview"))
        .function(viewPlatformFunction(
            "launchModernScanner", 0, 0, "launchModernScanner"));

    module.view(std::move(view).build());

    module.onDestroy([](RuntimeContext &context) {
      invokeLifecycle(context, "destroy");
    });
    module.onBackground([](RuntimeContext &context) {
      invokeLifecycle(context, "background");
    });
    module.onForeground([](RuntimeContext &context) {
      invokeLifecycle(context, "foreground");
    });

    return std::move(module).build();
  }
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoCameraProvider::modules(
    const std::shared_ptr<RuntimeContext> &) {
  return {std::make_shared<ExpoCameraModule>()};
}

}  // namespace expo::harmony::camera

EXPO_HARMONY_REGISTER_VIEWS("ExpoCamera", "Default");
