cmake_minimum_required(VERSION 3.22)
project(clashgo_native)

# JNI fork+exec helper. Android's ProcessBuilder closes every non-standard fd,
# but the VPN tun fd must survive into the mihomo child process.
add_library(clashgo_native SHARED process_helper.c)
target_compile_options(clashgo_native PRIVATE -Os -fvisibility=hidden -ffunction-sections -fdata-sections)
target_link_options(clashgo_native PRIVATE -Wl,--gc-sections -Wl,--strip-all)
target_link_libraries(clashgo_native PRIVATE log)
