#include <jni.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/wait.h>
#include <android/log.h>

#define TAG "ClashGoNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static void child_fail(const char *message, int code) {
    write(STDERR_FILENO, message, strlen(message));
    _exit(code);
}

// The tun fd has to survive exec so mihomo can own the VpnService queue. Move it
// to a fixed descriptor inside the child: dup2 both guarantees the number in the
// config and clears FD_CLOEXEC, so a failed Kotlin-side clear cannot leave
// mihomo without a queue (it only logs a TUN error and keeps running).
static void child_prepare_tun_fd(int tunFd, int childTunFd) {
    char buf[192];
    // 预览内核没有 tun：Kotlin 传 -1/-1 表示"不要 fd"，子进程照常 exec。
    if (tunFd < 0 && childTunFd < 0) return;
    if (tunFd <= 2 || childTunFd <= 2) {
        child_fail("invalid tun fd\n", 125);
    }
    if (tunFd != childTunFd && dup2(tunFd, childTunFd) < 0) {
        int n = snprintf(buf, sizeof(buf), "dup2 tun fd %d -> %d failed: %s\n",
                         tunFd, childTunFd, strerror(errno));
        if (n > 0) write(STDERR_FILENO, buf, (size_t) n);
        _exit(125);
    }
    int flags = fcntl(childTunFd, F_GETFD);
    if (flags < 0) {
        int n = snprintf(buf, sizeof(buf), "tun fd %d unavailable: %s\n", childTunFd, strerror(errno));
        if (n > 0) write(STDERR_FILENO, buf, (size_t) n);
        _exit(125);
    }
    if ((flags & FD_CLOEXEC) != 0) {
        if (fcntl(childTunFd, F_SETFD, flags & ~FD_CLOEXEC) < 0) {
            int n = snprintf(buf, sizeof(buf), "clear tun fd CLOEXEC failed: %s\n", strerror(errno));
            if (n > 0) write(STDERR_FILENO, buf, (size_t) n);
            _exit(125);
        }
    }
    int after = fcntl(childTunFd, F_GETFD);
    int n = snprintf(buf, sizeof(buf),
                     "[native] tun fd=%d child fd=%d flags before=0x%x after=0x%x\n",
                     tunFd, childTunFd, flags, after);
    if (n > 0) {
        write(STDERR_FILENO, buf, (size_t) n);
        LOGI("tun fd=%d child fd=%d flags before=0x%x after=0x%x",
             tunFd, childTunFd, flags, after);
    }
    if (after < 0 || (after & FD_CLOEXEC) != 0) {
        child_fail("tun fd still close-on-exec\n", 125);
    }
}

JNIEXPORT jint JNICALL
Java_com_clashgo_clash_1go_NativeProcess_nativeForkExec(
        JNIEnv *env, jobject thiz,
        jstring jBinary, jobjectArray jArgs, jstring jWorkDir, jstring jLogFile,
        jint tunFd, jint childTunFd) {

    const char *binary = (*env)->GetStringUTFChars(env, jBinary, NULL);
    const char *workDir = (*env)->GetStringUTFChars(env, jWorkDir, NULL);
    const char *logFile = jLogFile ? (*env)->GetStringUTFChars(env, jLogFile, NULL) : NULL;
    char **argv = NULL;
    int result = -1;
    int argc = 0;

    if (binary == NULL || workDir == NULL || (jLogFile != NULL && logFile == NULL)) {
        LOGE("GetStringUTFChars returned NULL");
        goto cleanup;
    }

    argc = (*env)->GetArrayLength(env, jArgs);
    argv = (char **) calloc(argc + 2, sizeof(char *));
    if (argv == NULL) {
        LOGE("calloc for argv failed");
        goto cleanup;
    }
    argv[0] = strdup(binary);
    if (argv[0] == NULL) {
        LOGE("strdup binary failed");
        goto cleanup;
    }
    for (int i = 0; i < argc; i++) {
        jstring jArg = (jstring) (*env)->GetObjectArrayElement(env, jArgs, i);
        if (jArg == NULL) {
            LOGE("null arg at %d", i);
            goto cleanup;
        }
        const char *arg = (*env)->GetStringUTFChars(env, jArg, NULL);
        if (arg != NULL) {
            argv[i + 1] = strdup(arg);
            (*env)->ReleaseStringUTFChars(env, jArg, arg);
        }
        (*env)->DeleteLocalRef(env, jArg);
        if (argv[i + 1] == NULL) {
            LOGE("strdup arg %d failed", i);
            goto cleanup;
        }
    }

    LOGI("fork+exec: %s, workDir=%s, log=%s", binary, workDir, logFile ? logFile : "(null)");

    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        if (chdir(workDir) != 0) {
            child_fail("chdir failed\n", 126);
        }
        if (logFile) {
            int fd = open(logFile, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
            if (fd >= 0) {
                dup2(fd, STDOUT_FILENO);
                dup2(fd, STDERR_FILENO);
                close(fd);
            }
        } else {
            dup2(STDERR_FILENO, STDOUT_FILENO);
        }
        child_prepare_tun_fd((int) tunFd, (int) childTunFd);
        execv(binary, argv);
        child_fail("execv failed\n", 127);
    }

    if (pid < 0) {
        LOGE("fork failed: %s", strerror(errno));
    } else {
        LOGI("child pid=%d", pid);
        result = pid;
    }

cleanup:
    if (argv != NULL) {
        for (int i = 0; argv[i] != NULL; i++) {
            free(argv[i]);
        }
        free(argv);
    }
    if (binary != NULL) (*env)->ReleaseStringUTFChars(env, jBinary, binary);
    if (workDir != NULL) (*env)->ReleaseStringUTFChars(env, jWorkDir, workDir);
    if (logFile != NULL) (*env)->ReleaseStringUTFChars(env, jLogFile, logFile);

    return result;
}

static pid_t waitpid_eintr(pid_t pid, int *status, int options) {
    pid_t r;
    do {
        r = waitpid(pid, status, options);
    } while (r < 0 && errno == EINTR);
    return r;
}

JNIEXPORT void JNICALL
Java_com_clashgo_clash_1go_NativeProcess_nativeKill(
        JNIEnv *env, jobject thiz, jint pid, jboolean force) {
    if (pid > 0) {
        int sig = force ? SIGKILL : SIGTERM;
        LOGI("killing pid=%d sig=%d", pid, sig);
        kill((pid_t) pid, sig);
    }
}

JNIEXPORT jint JNICALL
Java_com_clashgo_clash_1go_NativeProcess_nativeWaitpid(
        JNIEnv *env, jobject thiz, jint pid, jint timeoutMs) {
    if (pid <= 0) return -1;
    const long stepUs = 10 * 1000;
    long remainingUs = (long) timeoutMs * 1000;
    for (;;) {
        int status = 0;
        pid_t r = waitpid_eintr((pid_t) pid, &status, WNOHANG);
        if (r == (pid_t) pid) {
            if (WIFEXITED(status)) return WEXITSTATUS(status);
            if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
            return -1;
        }
        if (r < 0) return -1;
        if (remainingUs <= 0) return -1;
        usleep(stepUs);
        remainingUs -= stepUs;
    }
}

// Returns -2 while the child is alive, -1 when it cannot be reaped, otherwise
// the exit code. Using waitpid here is also what reaps the zombie.
JNIEXPORT jint JNICALL
Java_com_clashgo_clash_1go_NativeProcess_nativePollExit(
        JNIEnv *env, jobject thiz, jint pid) {
    if (pid <= 0) return -1;
    int status = 0;
    pid_t r = waitpid_eintr((pid_t) pid, &status, WNOHANG);
    if (r == 0) return -2;
    if (r < 0) return -1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return -1;
}
