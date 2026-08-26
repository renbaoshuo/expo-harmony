#pragma once

namespace expo::harmony::protocol {

inline constexpr const char kViewEvent[] = "EXPO_VIEW_EVENT";
inline constexpr const char kLifecycleEvent[] = "EXPO_LIFECYCLE_EVENT";
inline constexpr const char kModuleEvent[] = "EXPO_MODULE_EVENT";
inline constexpr const char kSharedObjectEvent[] = "EXPO_SHARED_OBJECT_EVENT";
inline constexpr const char kViewCommand[] = "EXPO_VIEW_COMMAND";
inline constexpr const char kViewEventEmit[] = "EXPO_VIEW_EVENT_EMIT";

inline constexpr const char kViewPhaseCreate[] = "CREATE";
inline constexpr const char kViewPhaseProps[] = "PROPS";
inline constexpr const char kViewPhaseDestroy[] = "DESTROY";
inline constexpr const char kLifecycleDestroy[] = "DESTROY";
inline constexpr const char kLifecycleForeground[] = "FOREGROUND";
inline constexpr const char kLifecycleBackground[] = "BACKGROUND";
inline constexpr const char kLifecycleUserLeaves[] = "USER_LEAVES";
inline constexpr const char kLifecycleActivityDestroy[] = "ACTIVITY_DESTROY";
inline constexpr const char kLifecycleNewIntent[] = "NEW_INTENT";
inline constexpr const char kLifecycleActivityResult[] = "ACTIVITY_RESULT";

}  // namespace expo::harmony::protocol
