package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"fmt"
	"os"
	"strings"
	"sync"
	"unsafe"

	"github.com/metacubex/mihomo/component/age"
	"github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/constant"
)

// Go 的崩溃穿过 C 边界会直接终止宿主进程，而这些函数是在应用自己的进程里跑的，死的是整个应用。
// 所以在这里把崩溃收成一个错误字符串返回；只能覆盖同一条协程。
func guardString(fn func() string) (ret *C.char) {
	defer func() {
		if r := recover(); r != nil {
			ret = C.CString(fmt.Sprintf("error: panic: %v", r))
		}
	}()
	return C.CString(fn())
}

var (
	cancelRegistry  sync.Map
	cancelledTokens sync.Map
	progressStore   sync.Map
	initOnce        sync.Once
)

// Kotlin 的取消钩子在阻塞 JNI 调用之前就已挂好，取消可能先于 Go 侧的 context 登记到达。
// 先把 token 记成已取消，登记时立即触发 cancel，避免那次取消被丢掉。
func beginCancelable(token int32) (context.Context, func()) {
	ctx, cancel := context.WithCancel(context.Background())
	cancelRegistry.Store(token, func() { cancel() })
	if _, ok := cancelledTokens.LoadAndDelete(token); ok {
		cancel()
	}
	return ctx, func() {
		cancel()
		cancelRegistry.Delete(token)
	}
}

//export clashgoCoreInit
func clashgoCoreInit(homeDir *C.char) {
	initOnce.Do(func() {
		constant.SetHomeDir(C.GoString(homeDir))
		// 面板按 UA 里的客户端名与版本裁剪节点（如 CMFA < 2.9.0 不下发 Hysteria2），版本必须如实；
		// 取内核 global-ua 默认值，与运行时刷新 provider 一致。
		http.SetUA("clash.meta/" + constant.Version)
	})
}

// Go 分配并返回的 C 字符串必须由 Go 这边释放，C 那边调 free 会破坏 Go 运行时的内存管理。
//export clashgoFreeString
func clashgoFreeString(s *C.char) {
	if s != nil {
		C.free(unsafe.Pointer(s))
	}
}

//export clashgoCancel
func clashgoCancel(token C.int) {
	key := int32(token)
	if v, ok := cancelRegistry.Load(key); ok {
		if cancel, ok := v.(func()); ok {
			cancel()
		}
		return
	}
	cancelledTokens.Store(key, struct{}{})
}

//export clashgoQueryProgress
func clashgoQueryProgress(token C.int) *C.char {
	if v, ok := progressStore.Load(int32(token)); ok {
		if s, ok := v.(string); ok {
			return C.CString(s)
		}
	}
	return nil
}

// PC 保存的是解密后的明文订阅，备份导出时用它解出明文；未加密的内容原样写到 dst。
//export clashgoDecryptFile
func clashgoDecryptFile(cSrc, cDst, cKey *C.char) *C.char {
	return guardString(func() string {
		data, err := os.ReadFile(C.GoString(cSrc))
		if err != nil {
			return "error: " + err.Error()
		}
		plain, err := age.DecryptBytes(data, strings.TrimSpace(C.GoString(cKey)))
		if err != nil {
			return "error: " + err.Error()
		}
		if err := os.WriteFile(C.GoString(cDst), plain, 0o600); err != nil {
			return "error: " + err.Error()
		}
		return ""
	})
}

//export clashgoGenAgeKeyPair
func clashgoGenAgeKeyPair() *C.char {
	return guardString(func() string {
		sk, pk, err := age.GenX25519KeyPair()
		if err != nil {
			return "error: " + err.Error()
		}
		return sk + "\n" + pk
	})
}

//export clashgoGenAgeHybridKeyPair
func clashgoGenAgeHybridKeyPair() *C.char {
	return guardString(func() string {
		sk, pk, err := age.GenHybridKeyPair()
		if err != nil {
			return "error: " + err.Error()
		}
		return sk + "\n" + pk
	})
}

func main() {}
