#pragma once

namespace expo::harmony::protocol {

inline constexpr const char kViewEvent[] = "EXPO_VIEW_EVENT";
inline constexpr const char kLifecycleEvent[] = "EXPO_LIFECYCLE_EVENT";
inline constexpr const char kLifecycleDestroyAck[] = "EXPO_LIFECYCLE_DESTROY_ACK";
inline constexpr const char kContentAppeared[] = "EXPO_CONTENT_APPEARED";
inline constexpr const char kModuleEvent[] = "EXPO_MODULE_EVENT";
inline constexpr const char kSharedObjectEvent[] = "EXPO_SHARED_OBJECT_EVENT";
inline constexpr const char kSharedObjectMarker[] = "__expoHarmonySharedObject";
inline constexpr const char kViewComponentName[] = "ViewManagerAdapter_ExpoModulesCore";
inline constexpr const char kViewModuleNameProp[] = "expoModuleName";
inline constexpr const char kViewRevisionProp[] = "expoViewRevision";
inline constexpr const char kViewNameProp[] = "expoViewName";

inline constexpr const char kViewPhaseCreate[] = "CREATE";
inline constexpr const char kViewPhaseProps[] = "PROPS";
inline constexpr const char kViewPhaseDestroy[] = "DESTROY";
inline constexpr const char kLifecycleDestroy[] = "DESTROY";

}  // namespace expo::harmony::protocol
