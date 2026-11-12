# @expo-harmony-copyright
#
# Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
# Released under MIT license. https://github.com/renbaoshuo/expo-harmony
# @end-expo-harmony-copyright

cmake_minimum_required(VERSION 3.5)
project(expo_video_metadata)

add_library(expo_video_metadata SHARED VideoMetadata.cpp)
target_compile_features(expo_video_metadata PRIVATE cxx_std_17)
target_compile_options(expo_video_metadata PRIVATE -Wall -Wextra)
target_link_libraries(expo_video_metadata PRIVATE libace_napi.z.so libnative_media_avsource.so libnative_media_core.so libnative_media_codecbase.so)
