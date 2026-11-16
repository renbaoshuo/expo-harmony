# @expo-harmony-copyright
#
# Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
# Released under MIT license. https://github.com/renbaoshuo/expo-harmony
# @end-expo-harmony-copyright

cmake_minimum_required(VERSION 3.5)
project(expo_constants_fonts)

add_library(expo_constants_fonts SHARED SystemFonts.cpp)
target_compile_features(expo_constants_fonts PRIVATE cxx_std_17)
target_link_libraries(expo_constants_fonts PRIVATE libace_napi.z.so libnative_drawing.so)
