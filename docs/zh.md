# tmux-agent-dock（中文說明）

> English: [README.md](../README.md)

![platform: macOS](https://img.shields.io/badge/platform-macOS-black)
![tmux ≥ 1.9](https://img.shields.io/badge/tmux-%E2%89%A5%201.9-1BB91F)
![fzf ≥ 0.43](https://img.shields.io/badge/fzf-%E2%89%A5%200.43-blue)

**以 macOS 為主**。掃描本身是純 tmux、原理上可攜，但停止動作裡的 process tree
處理與下面每一個狀態判定訊號都只在 macOS 驗過。Linux 多半能跑，但沒有斷言過。
實測環境：tmux next-3.8、fzf 0.73.1，2026-08。

![dock 開在右緣：四個 agent 依狀態排列——codex 卡在權限確認、閒置的 kimi、工作中的 gemini 與 claude——上方即時預覽選中 agent 的畫面](../docs/screenshot.png)

*這台 tmux server 上每個 agent 一份側欄，attention 新到舊，上方是選中那個的即時畫面。畫面錄自 forged agent，見 [§10](#10-關於這段錄影)。*

---

## 1. 這是什麼？

一個鍵打開 **dock**——當前 window 右緣一條全高側欄，即時列出這台 tmux server 上
所有正在跑的 AI agent pane。移動游標，dock 上半部就顯示那個 agent 的畫面；按 ⏎
跳過去，`⌃x` 終止它。

它回答「我哪個 agent 在等我、哪個還在做、哪個閒著」——不用一個個 window 切過去看。

**沒有 daemon**。dock 直接掃 tmux 找 agent——`list-panes` 找 pane、`capture-pane`
抓每個 pane 的畫面——再從畫面判狀態（working / waiting / idle），跟
[tmux-agent-status](https://github.com/operonlab/tmux-agent-status) 那顆狀態列
膠囊用的是同一套判定。背景不跑東西、不存東西、不外送。

**會偵測的 agent**：claude、codex、gemini、aider、cursor、agy、copilot、
opencode、amp、droid、qwen、kimi、hermes、pi、grok——任何 command 是其中之一的
pane，加上 terminal title 標記為 agent 的 `node`/`bun`/`deno` pane。加一個新的
只要在 `scripts/rows.sh` 與 `classify.awk` 各加一個字。

---

## 2. 快速開始

### 路徑 A — 沒有用外掛管理器（現在就能用）

```sh
git clone https://github.com/operonlab/tmux-agent-dock ~/.tmux/plugins/tmux-agent-dock
echo "run-shell ~/.tmux/plugins/tmux-agent-dock/agent-dock.tmux" >> ~/.tmux.conf
tmux source-file ~/.tmux.conf
```

然後按 **prefix + A**。

### 路徑 B — 使用 TPM（tmux 外掛管理器）

在 `~/.tmux.conf` 的 `run '~/.tmux/plugins/tpm/tpm'` 那行**上面**加：

```tmux
set -g @plugin 'operonlab/tmux-agent-dock'
```

按 **prefix + I** 安裝，再按 **prefix + A** 打開 dock。

---

## 3. 按鍵

| 鍵 | 作用 |
|----|------|
| prefix + A | 開 dock；再按一次收掉 |
| ↑ ↓ / 打字 | 移動 / 過濾清單；preview 跟著選中列 |
| ⏎ | 跳到選中 agent 的 pane |
| ⌃s | 循環排序：attention → tool |
| ⌃x | 終止選中 agent——`p` 殺進程（pane 留著）、`k` 砍整個 pane、`c` 取消 |
| q | 收掉 dock |

「attention」排序把需要你的排前面：waiting → idle → working（還在做的別打擾）。
你正附著的那個 pane 標 `▸`。

---

## 4. Demo

![往下移動 dock：上方 preview 跟著選中列，顯示每個 agent 的即時畫面——codex 卡在 migration 確認、閒置那個、還有兩個工作中](../docs/demo.gif)

往下移動，preview 跟著換：等你的那個、閒置的、還在做的兩個。⏎ 跳過去、`⌃x` 終止。

---

## 5. 選項

| 選項 | 預設 | 作用 |
|------|------|------|
| `@agent-dock-bind` | `A` | 開關 dock 的 prefix 鍵。設 `none` 不綁鍵。 |
| `@agent-dock-width` | `27%` | dock 寬度——百分比或絕對欄數。 |
| `@agent-dock-lang` | `en` | 介面語言；設 `zh` 把執行期字串切成繁體中文。 |

在 tmux 外呼叫腳本時可用的環境變數：

| 變數 | 預設 | 作用 |
|------|------|------|
| `AGENT_DOCK_LANG` | `en` | 同 `@agent-dock-lang` |
| `AGENT_DOCK_VCACHE` | `~/.cache/tmux-agent-dock/versions.tsv` | CLI 版本快取位置 |

---

## 6. 移除

```sh
bash ~/.tmux/plugins/tmux-agent-dock/scripts/teardown.sh
```

清掉綁鍵、收掉 dock pane。加 `--purge-cache` 會一併刪 `~/.cache/tmux-agent-dock`。
你的 `@agent-dock-*` 設定行不動，任何 agent pane 也不會被碰。最後把 `@plugin`／
`run-shell` 那行拿掉並重載 tmux。

---

## 7. 疑難排解 / FAQ

**按 prefix + A 沒反應。** 先確認綁鍵在：`tmux list-keys | grep agent-dock`。
如果 dock 開了但空的，代表沒有掃描器認得的 agent pane——跑
`bash ~/.tmux/plugins/tmux-agent-dock/scripts/rows.sh --no-color` 看它找到什麼。

**我在跑的某個 agent 沒出現。** 掃描器認 `pane_current_command`。有些啟動器把 CLI
包在 `node`/`bun` 下，那種只有在 terminal title 標記時才會被撿到。開 issue 附上
`pane_current_command` 的值（`tmux list-panes -a -F '#{pane_current_command}'`）。

**某個 pane 狀態判錯。** 狀態是 `classify.awk` 從 pane 可見畫面讀的（與
tmux-agent-status 共用），各 CLI 的訊號見它的
[detection matrix](https://github.com/operonlab/tmux-agent-status/blob/main/docs/detection-matrix.md)。
畫面捲走了會判成 `unknown`。

**會送任何東西到外面嗎？** 不會。唯一的網路呼叫是打 `127.0.0.1` 就地刷新 fzf
清單，而那個埠有每次執行產生的 `FZF_API_KEY` 保護。

**私有原版有、這版沒有的：** 精確的狀態持續時間、監聽 port、agent 在等什麼的
具體原因。那些來自一顆有狀態的 daemon；無狀態掃描重建不出來。

---

## 8. 運作原理（一段話）

`scripts/rows.sh` 跑 `tmux list-panes -a`，留下 command 是 agent 的 pane，抓每個
pane 的畫面丟給 `classify.awk` 判 working / waiting / idle，再印出每個 agent 一列
上色 TSV（attention 新到舊）。`scripts/dock.sh` 把它餵給 fzf：preview 是選中 agent
的 `tmux capture-pane`（`{2}:{3}`=session:target）、⏎ 跳轉、`⌃x` 終止。2 秒 ticker
透過 fzf 的 `--listen` 埠重跑掃描，讓清單與 header 保持即時。那個埠會接受任意
命令，所以 dock 每次執行產生一把 `FZF_API_KEY`，fzf 拒絕沒有它的請求。每個 fzf
placeholder 都保持 **bare** 讓 fzf 自己上引號——名字叫 `$(...)` 的 pane 或 session
只會被顯示，不會被執行。

---

## 9. 需求

| 需求 | 為什麼 | 缺了會怎樣 |
|------|--------|-----------|
| tmux ≥ 1.9 | `@` 開頭選項、`capture-pane -p` | 插件載不起來 |
| fzf ≥ 0.43 | `--listen` 帶 `$FZF_PORT`，以及保護它的 `FZF_API_KEY` | 0.38–0.42 有 `--listen` 但無 API key，不支援 |
| awk、ps | 狀態判定器與進程終止動作 | 核心工具，一定在 |
| curl | 每 2 秒就地刷新 | 清單仍可用，只是不自動更新 |

---

## 10. 關於這段錄影

上面的圖錄自 **forged agent**：`docs/demo-fixture.sh` 編譯一個印出固定畫面後阻塞
的小 native binary，讓它的 `pane_current_command` 讀作 `claude`/`codex`/…——不用
任何真的 CLI——再由 `docs/demo-setup.sh` 在隔離 tmux server 上擺四個。

這不是講究排場。dock 會把 agent 標題與即時畫面放到螢幕上，拿真實機器來錄就等於
把你在做什麼一起公開。

vhs 只錄畫面不錄按鍵，否則那串方向鍵與 ⏎ 的操作看起來會像自己跳的。
`docs/keycast-bezel.py` 產生 KeyCastr 風格的按鍵 bezel（與 operonlab tmux 家族
共用同一套元件），`docs/demo-overlay.sh` 再依 tape 的時間點把它們合成到原始畫面
上。重錄分三步：先 `vhs docs/demo.tape`，再 `python3 docs/keycast-bezel.py`，最後
`bash docs/demo-overlay.sh`。
