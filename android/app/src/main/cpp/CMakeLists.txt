cmake_minimum_required(VERSION 3.22)
project(clashgo)

# 每个 Native 任务共享一个编译/链接槽，整体并发由 Gradle worker 分配。
set_property(GLOBAL PROPERTY JOB_POOLS clashgo_native=1)
set(CMAKE_JOB_POOL_COMPILE clashgo_native)
set(CMAKE_JOB_POOL_LINK clashgo_native)

# 体积优化
set(CLASHGO_C_OPTS -Os -fvisibility=hidden -ffunction-sections -fdata-sections)
set(CLASHGO_LINK_OPTS -Wl,--gc-sections -Wl,--strip-all -Wl,--exclude-libs,ALL)

# libclashgo.so：fork+exec 与子进程判活的 JNI 实现（Android ProcessBuilder 会关掉 TUN fd）
add_library(clashgo SHARED process_helper.c)
target_link_libraries(clashgo PRIVATE log)
target_compile_options(clashgo PRIVATE ${CLASHGO_C_OPTS})
target_link_options(clashgo PRIVATE ${CLASHGO_LINK_OPTS})

# libmihomo.so（IMPORTED）：cgo c-shared
set(MIHOMO_CORE_DIR "${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}")
add_library(mihomo_imported SHARED IMPORTED)
set_target_properties(mihomo_imported PROPERTIES
        IMPORTED_LOCATION "${MIHOMO_CORE_DIR}/libmihomo.so"
        IMPORTED_SONAME "libmihomo.so")

# libclashgo_jni.so：薄 JNI 桥
add_library(clashgo_jni SHARED clashgo_jni.c)
target_include_directories(clashgo_jni PRIVATE "${MIHOMO_CORE_DIR}")
target_link_libraries(clashgo_jni PRIVATE log mihomo_imported)
target_compile_options(clashgo_jni PRIVATE ${CLASHGO_C_OPTS})
target_link_options(clashgo_jni PRIVATE ${CLASHGO_LINK_OPTS})

# libmihomo_runner.so：薄 PIE 可执行 wrapper
add_executable(mihomo_runner mihomo_wrapper.c)
target_link_libraries(mihomo_runner PRIVATE log dl)
set_target_properties(mihomo_runner PROPERTIES
        OUTPUT_NAME "mihomo_runner"
        PREFIX "lib"
        SUFFIX ".so")
target_compile_options(mihomo_runner PRIVATE ${CLASHGO_C_OPTS} -fPIE)
target_link_options(mihomo_runner PRIVATE ${CLASHGO_LINK_OPTS} -pie -Wl,-z,now -Wl,-z,relro)
