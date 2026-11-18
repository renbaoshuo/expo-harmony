/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <hiappevent/hiappevent.h>
#include <hiappevent/hiappevent_cfg.h>

#ifdef OH_APP_CRASH_PARAM_MERGE_CPPCRASH_APP_LOG
#pragma weak OH_HiAppEvent_CreateConfig
#pragma weak OH_HiAppEvent_DestroyConfig
#pragma weak OH_HiAppEvent_SetConfigItem
#pragma weak OH_HiAppEvent_SetEventConfig
#endif
