#pragma once

// Replaced deterministically from app config during Harmony prebuild.
#define EXPO_HARMONY_APP_CONFIG_JSON ""
#define EXPO_HARMONY_BUNDLE_NAME "com.example.expo"
#define EXPO_HARMONY_VERSION_NAME "1.0.0"
#define EXPO_HARMONY_VERSION_CODE 1
#ifdef NDEBUG
#define EXPO_HARMONY_DEBUG_MODE false
#else
#define EXPO_HARMONY_DEBUG_MODE true
#endif
