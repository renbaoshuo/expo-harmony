/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

namespace expo::harmony::protocol {

inline constexpr const char kViewEvent[] = "EXPO_VIEW_EVENT";
inline constexpr const char kLifecycleEvent[] = "EXPO_LIFECYCLE_EVENT";
inline constexpr const char kLifecycleDestroyAck[] = "EXPO_LIFECYCLE_DESTROY_ACK";
inline constexpr const char kContentAppeared[] = "EXPO_CONTENT_APPEARED";
inline constexpr const char kModuleEvent[] = "EXPO_MODULE_EVENT";
inline constexpr const char kSharedObjectEvent[] = "EXPO_SHARED_OBJECT_EVENT";
inline constexpr const char kSharedObjectMarker[] = "__expoHarmonySharedObject";
inline constexpr const char kResolveSharedObjectInWorklet[] = "__resolveInWorklet";
inline constexpr const char kViewComponentPrefix[] = "ViewManagerAdapter_";
inline constexpr const char kViewComponentName[] = "ViewManagerAdapter_ExpoModulesCore";
inline constexpr const char kViewModuleNameProp[] = "expoModuleName";
inline constexpr const char kViewRevisionProp[] = "expoViewRevision";
inline constexpr const char kViewNameProp[] = "expoViewName";

inline constexpr const char kViewPhaseCreate[] = "CREATE";
inline constexpr const char kViewPhaseProps[] = "PROPS";
inline constexpr const char kViewPhaseDestroy[] = "DESTROY";
inline constexpr const char kLifecycleContentAppeared[] = "CONTENT_APPEARED";
inline constexpr const char kLifecycleDestroy[] = "DESTROY";

inline constexpr unsigned int kLogDomain = 0xD003900;
inline constexpr const char kLogTag[] = "ExpoModulesCore";

}  // namespace expo::harmony::protocol
