import org.gradle.api.DefaultTask
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import javax.inject.Inject

@CacheableTask
abstract class RustBuildTask : DefaultTask() {

    @get:Inject
    abstract val execOps: ExecOperations

    @get:Internal
    abstract val rustRoot: DirectoryProperty

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val rustSources: ConfigurableFileCollection

    @get:Input
    abstract val abi: Property<String>

    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val ndkDirectory: DirectoryProperty

    @get:Input
    abstract val minSdk: Property<Int>

    @get:Input
    abstract val cargoExecutable: Property<String>

    @get:Optional
    @get:Input
    abstract val cargoTargetDir: Property<String>

    @get:OutputFile
    abstract val outputFile: RegularFileProperty

    @TaskAction
    fun build() {
        val abi = abi.get()
        val triple = ABI_TO_TARGET[abi]
            ?: error("Unsupported ABI for Rust: $abi; expected one of ${ABI_TO_TARGET.keys}")
        val sdkLevel = minSdk.get()
        val ndk = ndkDirectory.get().asFile
        val clang = ndk
            .resolve("toolchains/llvm/prebuilt/${hostTag()}/bin")
            .resolve(if (isWindows()) "clang.exe" else "clang")
        if (!clang.isFile) {
            error("NDK clang not found at ${clang.absolutePath}; check NDK installation")
        }

        val out = outputFile.get().asFile
        out.parentFile.mkdirs()
        val root = rustRoot.get().asFile
        val targetDir = cargoTargetDir.orNull?.let(::File) ?: root.resolve("target")
        val envPrefix = "CARGO_TARGET_${triple.uppercase().replace('-', '_')}"

        execOps.exec {
            workingDir = root
            commandLine(
                cargoExecutable.get(),
                "build",
                "--locked",
                "--release",
                "--target",
                triple,
            )
            environment("${envPrefix}_LINKER", clang.absolutePath)
            // 直接使用 clang 驱动而不是 NDK 的 .cmd 包装脚本：cargo 在 Windows 上无法执行 .cmd。
            environment(
                "${envPrefix}_RUSTFLAGS",
                "-C link-arg=--target=$triple$sdkLevel -C link-arg=-Wl,-z,max-page-size=16384",
            )
        }

        val built = targetDir.resolve("$triple/release/libclashgo_backend.so")
        if (!built.isFile) {
            error("Rust build finished but ${built.absolutePath} is missing")
        }
        Files.copy(built.toPath(), out.toPath(), StandardCopyOption.REPLACE_EXISTING)
    }

    private fun isWindows(): Boolean = System.getProperty("os.name").lowercase().startsWith("windows")

    private fun hostTag(): String {
        val osName = System.getProperty("os.name").lowercase()
        return when {
            osName.startsWith("windows") -> "windows-x86_64"
            osName.startsWith("mac") || osName.contains("darwin") -> "darwin-x86_64"
            else -> "linux-x86_64"
        }
    }

    companion object {
        private val ABI_TO_TARGET = mapOf(
            "arm64-v8a" to "aarch64-linux-android",
            "x86_64" to "x86_64-linux-android",
        )
    }
}
