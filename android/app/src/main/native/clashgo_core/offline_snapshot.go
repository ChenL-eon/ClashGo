package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/age"
	"github.com/metacubex/mihomo/config"
	constant "github.com/metacubex/mihomo/constant"
)

const offlineTestConcurrency = 5

// 离线解析与在线校验共用 age 全局密钥和 provider 缓存，两个 JNI 调用同时进入会互相覆盖密钥。
var offlineParseMu sync.Mutex

type offlineProviderSnapshot struct {
	Name    string           `json:"name"`
	Proxies []constant.Proxy `json:"proxies"`
}

type offlineSnapshot struct {
	Mode      string                             `json:"mode"`
	Proxies   map[string]constant.Proxy          `json:"proxies"`
	Groups    []constant.Proxy                   `json:"groups"`
	Providers map[string]offlineProviderSnapshot `json:"providers"`
}

type offlineDelaySnapshot struct {
	Delays map[string]int `json:"delays"`
}

// 停止态没有内核 REST，但配置与 provider 缓存都在磁盘上；这里复用运行时的变换与解析流程，
// 把解析结果直接序列化成与 /proxies、/group、/providers/proxies 相同的形状。
func parseOfflineConfig(workDir, transformPath, ageSecretKey string) (*config.Config, string, error) {
	out, err := readTransformedConfig(workDir, transformPath, ageSecretKey)
	if err != nil {
		return nil, "", err
	}
	rawCfg, err := config.UnmarshalRawConfig(out)
	if err != nil {
		return nil, "", fmt.Errorf("unmarshal config: %w", err)
	}
	patchProvidersPath(rawCfg, filepath.Join(workDir, "providers"))
	cfg, err := config.ParseRawConfig(rawCfg)
	if err != nil {
		return nil, "", fmt.Errorf("parse config: %w", err)
	}
	// ParseRawConfig 只创建 provider，缓存要等 executor.Initial() 才读入；
	// 离线没有内核启动流程，必须在导出前自己完成，否则组里只剩 COMPATIBLE 占位。
	for _, provider := range cfg.Providers {
		if err := provider.Initial(); err != nil {
			destroyProviders(cfg)
			return nil, "", fmt.Errorf("init provider %s: %w", provider.Name(), err)
		}
	}
	for _, provider := range cfg.RuleProviders {
		if err := provider.Initial(); err != nil {
			destroyProviders(cfg)
			return nil, "", fmt.Errorf("init rule provider %s: %w", provider.Name(), err)
		}
	}
	mode := string(rawCfg.Mode)
	if mode == "" {
		mode = "rule"
	}
	return cfg, mode, nil
}

func collectOfflineProxies(cfg *config.Config) map[string]constant.Proxy {
	proxies := make(map[string]constant.Proxy, len(cfg.Proxies))
	for name, proxy := range cfg.Proxies {
		proxies[name] = proxy
	}
	for _, provider := range cfg.Providers {
		for _, proxy := range provider.Proxies() {
			if _, ok := proxies[proxy.Name()]; !ok {
				proxies[proxy.Name()] = proxy
			}
		}
	}
	return proxies
}

//export clashgoOfflineProxySnapshot
func clashgoOfflineProxySnapshot(cWorkDir, cTransform, cKey *C.char) *C.char {
	return guardString(func() string {
		workDir := C.GoString(cWorkDir)
		transformPath := C.GoString(cTransform)
		key := C.GoString(cKey)

		offlineParseMu.Lock()
		defer offlineParseMu.Unlock()
		age.SetGlobalSecretKeys(key)
		defer age.SetGlobalSecretKeys()

		cfg, mode, err := parseOfflineConfig(workDir, transformPath, key)
		if err != nil {
			return "error: " + err.Error()
		}
		defer destroyProviders(cfg)

		groups := make([]constant.Proxy, 0)
		for _, proxy := range cfg.Proxies {
			if _, ok := proxy.Adapter().(outboundgroup.ProxyGroup); ok {
				groups = append(groups, proxy)
			}
		}
		providers := make(map[string]offlineProviderSnapshot, len(cfg.Providers))
		for name, provider := range cfg.Providers {
			providers[name] = offlineProviderSnapshot{Name: name, Proxies: provider.Proxies()}
		}

		data, err := json.Marshal(offlineSnapshot{
			Mode:      mode,
			Proxies:   cfg.Proxies,
			Groups:    groups,
			Providers: providers,
		})
		if err != nil {
			return "error: marshal snapshot: " + err.Error()
		}
		return string(data)
	})
}

//export clashgoTestOfflineDelays
func clashgoTestOfflineDelays(cWorkDir, cTransform, cKey, cNames, cURL *C.char, cTimeout C.int, cUnifiedDelay C.int) *C.char {
	return guardString(func() string {
		workDir := C.GoString(cWorkDir)
		transformPath := C.GoString(cTransform)
		key := C.GoString(cKey)
		testURL := C.GoString(cURL)
		timeout := int(cTimeout)
		if timeout <= 0 {
			timeout = 5000
		}

		var names []string
		if err := json.Unmarshal([]byte(C.GoString(cNames)), &names); err != nil {
			return "error: parse names: " + err.Error()
		}

		offlineParseMu.Lock()
		age.SetGlobalSecretKeys(key)
		cfg, _, err := parseOfflineConfig(workDir, transformPath, key)
		// 离线进程没有 executor.Initial 这条启动路径，unified-delay 不会自己写进全局开关；
		// 不补这一步，停止态测到的是含 DNS/TCP/TLS 建连的第一次请求，和运行态不可比。
		if err == nil {
			adapter.UnifiedDelay.Store(cUnifiedDelay != 0)
		}
		age.SetGlobalSecretKeys()
		offlineParseMu.Unlock()
		if err != nil {
			return "error: " + err.Error()
		}
		defer destroyProviders(cfg)

		proxies := collectOfflineProxies(cfg)
		expectedStatus, err := utils.NewUnsignedRanges[uint16]("")
		if err != nil {
			return "error: expected status: " + err.Error()
		}

		results := make(map[string]int, len(names))
		var (
			mu    sync.Mutex
			wg    sync.WaitGroup
			slots = make(chan struct{}, offlineTestConcurrency)
		)
		for _, name := range names {
			proxy, ok := proxies[name]
			if !ok {
				mu.Lock()
				results[name] = -1
				mu.Unlock()
				continue
			}
			wg.Add(1)
			go func(name string, proxy constant.Proxy) {
				defer wg.Done()
				slots <- struct{}{}
				defer func() { <-slots }()

				ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Millisecond)
				defer cancel()
				delay, err := proxy.URLTest(ctx, testURL, expectedStatus)
				if err != nil || delay == 0 {
					delay = 0
				}
				result := int(delay)
				if result == 0 {
					result = -1
				}
				mu.Lock()
				results[name] = result
				mu.Unlock()
			}(name, proxy)
		}
		wg.Wait()

		data, err := json.Marshal(offlineDelaySnapshot{Delays: results})
		if err != nil {
			return "error: marshal delays: " + err.Error()
		}
		return string(data)
	})
}
