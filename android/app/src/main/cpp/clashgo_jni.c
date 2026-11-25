#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "libmihomo.h"

static size_t utf8_encode(uint32_t code, char *out) {
    if (code <= 0x7F) {
        out[0] = (char) code;
        return 1;
    }
    if (code <= 0x7FF) {
        out[0] = (char) (0xC0 | (code >> 6));
        out[1] = (char) (0x80 | (code & 0x3F));
        return 2;
    }
    if (code <= 0xFFFF) {
        out[0] = (char) (0xE0 | (code >> 12));
        out[1] = (char) (0x80 | ((code >> 6) & 0x3F));
        out[2] = (char) (0x80 | (code & 0x3F));
        return 3;
    }
    out[0] = (char) (0xF0 | (code >> 18));
    out[1] = (char) (0x80 | ((code >> 12) & 0x3F));
    out[2] = (char) (0x80 | ((code >> 6) & 0x3F));
    out[3] = (char) (0x80 | (code & 0x3F));
    return 4;
}

// JNI 的 GetStringUTFChars 是 Modified UTF-8：补充平面字符被拆成两个三字节代理，
// Go 按标准 UTF-8 解码会得到 U+FFFD。这里显式做 UTF-16 <-> 标准 UTF-8。
static char *jstring_to_cstr(JNIEnv *env, jstring s) {
    if (!s) return NULL;
    jsize length = (*env)->GetStringLength(env, s);
    const jchar *chars = (*env)->GetStringChars(env, s, NULL);
    if (!chars) return NULL;

    // 每个 UTF-16 单元最多产生 3 字节，代理对最多 4 字节，4*length+1 足够。
    char *out = malloc((size_t) length * 4 + 1);
    if (!out) {
        (*env)->ReleaseStringChars(env, s, chars);
        return NULL;
    }

    size_t offset = 0;
    for (jsize i = 0; i < length; i++) {
        uint32_t code = chars[i];
        if (code >= 0xD800 && code <= 0xDBFF && i + 1 < length &&
            chars[i + 1] >= 0xDC00 && chars[i + 1] <= 0xDFFF) {
            code = 0x10000 + (((code - 0xD800) << 10) | (chars[i + 1] - 0xDC00));
            i++;
        } else if (code >= 0xD800 && code <= 0xDFFF) {
            code = 0xFFFD;
        }
        offset += utf8_encode(code, out + offset);
    }
    out[offset] = '\0';

    (*env)->ReleaseStringChars(env, s, chars);
    return out;
}

static uint32_t utf8_decode(const unsigned char *s, size_t length, size_t *consumed) {
    unsigned char b0 = s[0];
    if (b0 < 0x80) {
        *consumed = 1;
        return b0;
    }
    if (b0 >= 0xC2 && b0 <= 0xDF && length >= 2 && (s[1] & 0xC0) == 0x80) {
        *consumed = 2;
        return ((uint32_t) (b0 & 0x1F) << 6) | (s[1] & 0x3F);
    }
    if (b0 >= 0xE0 && b0 <= 0xEF && length >= 3 &&
        (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80) {
        uint32_t code = ((uint32_t) (b0 & 0x0F) << 12) |
                        ((uint32_t) (s[1] & 0x3F) << 6) | (s[2] & 0x3F);
        if (code < 0x800 || (code >= 0xD800 && code <= 0xDFFF)) {
            *consumed = 1;
            return 0xFFFD;
        }
        *consumed = 3;
        return code;
    }
    if (b0 >= 0xF0 && b0 <= 0xF4 && length >= 4 &&
        (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80 && (s[3] & 0xC0) == 0x80) {
        uint32_t code = ((uint32_t) (b0 & 0x07) << 18) |
                        ((uint32_t) (s[1] & 0x3F) << 12) |
                        ((uint32_t) (s[2] & 0x3F) << 6) | (s[3] & 0x3F);
        if (code < 0x10000 || code > 0x10FFFF) {
            *consumed = 1;
            return 0xFFFD;
        }
        *consumed = 4;
        return code;
    }
    *consumed = 1;
    return 0xFFFD;
}

static jstring go_cstr_to_jstring(JNIEnv *env, char *s) {
    if (!s) return NULL;
    size_t length = strlen(s);
    // UTF-8 每字节最多对应一个 UTF-16 单元，长度不会超过字节数。
    jchar *chars = malloc((length + 1) * sizeof(jchar));
    if (!chars) {
        clashgoFreeString(s);
        return NULL;
    }

    size_t offset = 0;
    size_t units = 0;
    while (offset < length) {
        size_t consumed = 0;
        uint32_t code = utf8_decode((const unsigned char *) s + offset, length - offset, &consumed);
        offset += consumed;
        if (code <= 0xFFFF) {
            chars[units++] = (jchar) code;
        } else {
            code -= 0x10000;
            chars[units++] = (jchar) (0xD800 | (code >> 10));
            chars[units++] = (jchar) (0xDC00 | (code & 0x3FF));
        }
    }

    jstring out = (*env)->NewString(env, chars, (jsize) units);
    free(chars);
    clashgoFreeString(s);
    return out;
}

JNIEXPORT void JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeCoreInit(
        JNIEnv *env, jclass clazz, jstring jHomeDir) {
    char *homeDir = jstring_to_cstr(env, jHomeDir);
    clashgoCoreInit(homeDir ? homeDir : "");
    free(homeDir);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeFetchAndValid(
        JNIEnv *env, jclass clazz,
        jstring jWorkDir, jstring jUrl, jboolean jForce, jstring jHttpProxy, jstring jUserAgent,
        jint jToken, jstring jAgeSecretKey) {
    char *workDir = jstring_to_cstr(env, jWorkDir);
    char *url = jstring_to_cstr(env, jUrl);
    char *httpProxy = jstring_to_cstr(env, jHttpProxy);
    char *userAgent = jstring_to_cstr(env, jUserAgent);
    char *ageSecretKey = jstring_to_cstr(env, jAgeSecretKey);

    char *result = clashgoFetchAndValid(
            workDir ? workDir : "",
            url ? url : "",
            jForce ? 1 : 0,
            httpProxy ? httpProxy : "",
            userAgent ? userAgent : "",
            (int) jToken,
            ageSecretKey ? ageSecretKey : "");

    free(workDir);
    free(url);
    free(httpProxy);
    free(userAgent);
    free(ageSecretKey);

    return go_cstr_to_jstring(env, result);
}

JNIEXPORT void JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeCancel(
        JNIEnv *env, jclass clazz, jint jToken) {
    clashgoCancel((int) jToken);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeQueryProgress(
        JNIEnv *env, jclass clazz, jint jToken) {
    char *progress = clashgoQueryProgress((int) jToken);
    return go_cstr_to_jstring(env, progress);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeExtractXzAsset(
        JNIEnv *env, jclass clazz, jstring jApk, jstring jEntry, jstring jTarget) {
    char *apk = jstring_to_cstr(env, jApk);
    char *entry = jstring_to_cstr(env, jEntry);
    char *target = jstring_to_cstr(env, jTarget);
    char *result = clashgoExtractXzAsset(apk ? apk : "", entry ? entry : "", target ? target : "");
    free(apk);
    free(entry);
    free(target);
    return go_cstr_to_jstring(env, result);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeDecryptFile(
        JNIEnv *env, jclass clazz, jstring jSource, jstring jTarget, jstring jKey) {
    char *source = jstring_to_cstr(env, jSource);
    char *target = jstring_to_cstr(env, jTarget);
    char *key = jstring_to_cstr(env, jKey);
    char *result = clashgoDecryptFile(source ? source : "", target ? target : "", key ? key : "");
    free(source);
    free(target);
    free(key);
    return go_cstr_to_jstring(env, result);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeValidateTransform(
        JNIEnv *env, jclass clazz, jstring jWorkDir, jstring jTransform, jstring jKey) {
    char *workDir = jstring_to_cstr(env, jWorkDir);
    char *transform = jstring_to_cstr(env, jTransform);
    char *key = jstring_to_cstr(env, jKey);
    char *result = clashgoValidateTransform(workDir ? workDir : "", transform ? transform : "", key ? key : "");
    free(workDir);
    free(transform);
    free(key);
    return go_cstr_to_jstring(env, result);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeOfflineProxySnapshot(
        JNIEnv *env, jclass clazz, jstring jWorkDir, jstring jTransform, jstring jKey) {
    char *workDir = jstring_to_cstr(env, jWorkDir);
    char *transform = jstring_to_cstr(env, jTransform);
    char *key = jstring_to_cstr(env, jKey);
    char *result = clashgoOfflineProxySnapshot(workDir ? workDir : "", transform ? transform : "", key ? key : "");
    free(workDir);
    free(transform);
    free(key);
    return go_cstr_to_jstring(env, result);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeTestOfflineDelays(
        JNIEnv *env, jclass clazz,
        jstring jWorkDir, jstring jTransform, jstring jKey, jstring jNames, jstring jUrl,
        jint jTimeout, jboolean jUnifiedDelay, jint jToken) {
    char *workDir = jstring_to_cstr(env, jWorkDir);
    char *transform = jstring_to_cstr(env, jTransform);
    char *key = jstring_to_cstr(env, jKey);
    char *names = jstring_to_cstr(env, jNames);
    char *url = jstring_to_cstr(env, jUrl);
    char *result = clashgoTestOfflineDelays(
            workDir ? workDir : "", transform ? transform : "", key ? key : "",
            names ? names : "[]", url ? url : "", jTimeout, jUnifiedDelay ? 1 : 0, (int) jToken);
    free(workDir);
    free(transform);
    free(key);
    free(names);
    free(url);
    return go_cstr_to_jstring(env, result);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeChainProxyContext(
        JNIEnv *env, jclass clazz, jstring jWorkDir, jstring jTransform, jstring jKey) {
    char *workDir = jstring_to_cstr(env, jWorkDir);
    char *transform = jstring_to_cstr(env, jTransform);
    char *key = jstring_to_cstr(env, jKey);
    char *result = clashgoChainProxyContext(workDir ? workDir : "", transform ? transform : "", key ? key : "");
    free(workDir);
    free(transform);
    free(key);
    return go_cstr_to_jstring(env, result);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeRuleContext(
        JNIEnv *env, jclass clazz, jstring jWorkDir, jstring jTransform, jstring jKey) {
    char *workDir = jstring_to_cstr(env, jWorkDir);
    char *transform = jstring_to_cstr(env, jTransform);
    char *key = jstring_to_cstr(env, jKey);
    char *result = clashgoRuleContext(workDir ? workDir : "", transform ? transform : "", key ? key : "");
    free(workDir);
    free(transform);
    free(key);
    return go_cstr_to_jstring(env, result);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeGenAgeKeyPair(
        JNIEnv *env, jclass clazz) {
    char *result = clashgoGenAgeKeyPair();
    return go_cstr_to_jstring(env, result);
}

JNIEXPORT jstring JNICALL
Java_com_clashgo_android_data_bridge_ClashGoCoreBridge_nativeGenAgeHybridKeyPair(
        JNIEnv *env, jclass clazz) {
    char *result = clashgoGenAgeHybridKeyPair();
    return go_cstr_to_jstring(env, result);
}
