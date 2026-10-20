# Changelog

## v1.0.0-beta.1

The first Quotapus release: an unofficial fork of OpenUsage (synced with upstream 0.7.16-beta.1) that also counts the AI coding usage on your other computers.

### New Features
- Remote Devices: import Claude Code and Codex usage from Linux, Mac, Windows, and Windows + WSL machines over SSH, with a Tailscale machine picker, a WSL distribution picker, and a connection and log check before saving
- Live activity: tokens per minute for this Mac and each connected device, with Tokens, Models, and Spend cards
- Usage From: switch the dashboard between All Devices, This Mac, or one device
- Frosted glass panel with pace on every meter, Last 14 Days, and Top Models
- Extra log folders for archived Claude and Codex history (`~/.quotapus/config.json`)

### Bug Fixes
- Models priced by their own provider first, so Grok, GLM, DeepSeek, and Mistral no longer pick up a reseller's lower rate
- Codex reasoning tokens are no longer counted twice, and copied Codex sessions count once in live speed
- Launch no longer waits behind a Claude Desktop Keychain dialog
- SSH imports no longer leak file descriptors, work with Python 3.6+, and explain host, username, and Python errors

### Chores
- Renamed to Quotapus with its own icon; updates come from this repository
- Signed with Quotapus's own certificate: the first launch needs one **Open Anyway** in System Settings → Privacy & Security

---

### 中文說明

Quotapus 的第一個版本：OpenUsage 的非官方分支（已同步到上游 0.7.16-beta.1），額外會計算你其他電腦上的 AI 程式工具用量。

**新功能**
- 遠端裝置：透過 SSH 匯入 Linux、Mac、Windows、Windows + WSL 電腦上的 Claude Code 和 Codex 用量；可以從 Tailscale 直接選電腦、從清單選 WSL 發行版，儲存前會先檢查連線和有沒有 log
- 即時活動：顯示這台 Mac 和每台已連線裝置每分鐘用了多少 token，另有 Tokens、Models、Spend 三張卡片
- 用量來源切換：首頁可以切換顯示「所有裝置」、「這台 Mac」或「單一裝置」
- 毛玻璃面板，每個用量條都會顯示消耗速度，並加上「最近 14 天」和「熱門模型」
- 可以額外加入封存的 Claude 和 Codex 歷史 log 資料夾（`~/.quotapus/config.json`）

**錯誤修正**
- 計價改為優先用模型原廠的價格，Grok、GLM、DeepSeek、Mistral 不會再被算成轉售商較低的價格
- Codex 的推理 token 不再重複計算；複製出來的同一個 Codex 對話，在即時速度裡只算一次
- 啟動時不會再卡在 Claude Desktop 的鑰匙圈授權視窗
- SSH 匯入不再洩漏檔案描述子，支援 Python 3.6 以上，主機、帳號、Python 出錯時會說明原因

**其他**
- 更名為 Quotapus，換上自己的圖示；更新改從本 repo 發佈
- 使用 Quotapus 自己的憑證簽名：第一次打開時，要到「系統設定 → 隱私權與安全性」按一次**強制打開**

## Earlier History

Quotapus starts from OpenUsage 0.7.16-beta.1. For changes before the fork, see the [OpenUsage changelog](https://github.com/robinebers/openusage/blob/main/CHANGELOG.md).
