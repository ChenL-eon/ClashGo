package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sync/atomic"

	"github.com/metacubex/chi"
	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/hub/route"
)

// registerRuntimeProbe 注册运行状态探针和配置重载入口。
// reload 的第二个返回值标记配置本身是否可解析；调用方据此区分 400 与 500。
func registerRuntimeProbe(ready *atomic.Bool, reload func() (error, bool)) {
	// 扩展路由沿用控制器鉴权；进程号区分使用相同密钥的内核，初始化期间的 503 也带上，
	// 应用据此区分「自己仍在加载 provider」与「端口被其他程序占用」。
	route.Register(func(router chi.Router) {
		router.Get("/clashgo/runtime", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			if !ready.Load() {
				w.WriteHeader(http.StatusServiceUnavailable)
			}
			fmt.Fprintf(w, `{"pid":%d}`, os.Getpid())
		})

		router.Post("/clashgo/reload", func(w http.ResponseWriter, r *http.Request) {
			err, badConfig := reload()
			if err == nil {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			status := http.StatusInternalServerError
			if badConfig {
				status = http.StatusBadRequest
			}
			w.WriteHeader(status)
			_ = json.NewEncoder(w).Encode(map[string]string{"message": err.Error()})
		})
	})
}
