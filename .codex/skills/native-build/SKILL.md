---
name: native-build
description: cgo / JNI 边界、libmihomo.so 与 Gradle 构建任务、Rust 后端、Baseline Profile。改 android/app/src/main/cpp/、android/app/src/main/native/stelliberty_core/、rust/、buildSrc/ 下的构建任务，或调 System.loadLibrary / 加 mihomo CLI flag 前必须先读。触发词包括 native, JNI, cgo, so 库, libmihomo, GoBuildTask, CMake, 构建任务, gradle 任务, RustBuildTask, cargo, downloadGeoFiles, GeoIP, baseline profile, 启动优化, mihomo patch, submodule, 交叉编译.
user_invocable: true
---

## 核心约束

1. `System.loadLibrary("mihomo")` 先于 `loadLibrary("stelliberty_jni")`：后者链接前者导出的符号。
2. `//export` 函数收住 panic：JNI 在进程内运行，panic 逸出 cgo 边界会终止整个应用。返回字符串的走 `guardString`。
3. cgo 返回的 `*C.char` 由 Go 侧释放：C 侧调用 `stellibertyFreeString()`。
4. 更新 mihomo submodule 或补丁后确认新代码进了 .so：`replacedModuleSources` 声明完整，任务才会重新编译。
5. Rust 后端只有 `nativeInit` / `nativeCall` 两个 JNI 符号：新能力加 `rust/stelliberty-backend/src/lib.rs` 的 `dispatch` 分支，不新增符号。
6. `nativeCall` 是阻塞调用，只能在 IO 线程调用；JNI 边界必须 `catch_unwind`，panic 转 `panic` 错误码，不能越过 FFI。
7. Rust 不持有 Android Context、不链接 mihomo：VpnService / TUN fd / SharedPreferences / root shell 留在 Kotlin，作为显式输入传进 Rust。

## Rust 构建

`RustBuildTask`（buildSrc）按 ABI 交叉编译到 `android/app/src/main/jniLibs/<ABI>/libstelliberty_backend.so`，由 `mergeJniLibFolders` 触发（纯 Kotlin 编译不需要 cargo）。cargo 不在 PATH 时用 `-Pstelliberty.cargo=<path>`；NDK 取 AGP 的 `ndkDirectory`，链接器直接用 NDK 的 `clang`（Windows 上不能把 `.cmd` 交给 cargo）。release 开 LTO、strip，并显式 `max-page-size=16384`。

## 指引索引

| 任务 | 指引 |
|---|---|
| 库加载顺序、SONAME、PIE wrapper、内存归属、panic 边界、fork+exec | `guides/jni.md` |
| GoBuildTask 三条硬约束、downloadGeoFiles、CMake 链接 | `guides/gradle.md` |
| 采集条件、三段 workaround、CI 的消费方式 | `guides/baseline-profile.md` |

编译命令与常规验证见仓库根的 [AGENTS.md](../../../AGENTS.md)。

## 维护

新加 mihomo CLI flag 同步注册到 `stelliberty_core/runtime.go` 的 `flag.NewFlagSet`：`ExitOnError` 遇到未注册的 flag 会直接让启动失败。

每次同步上游后确认 fd 模式 `forwarderBindInterface = true` 仍然生效，前提是新代码已进 .so（见 `guides/gradle.md`）。
