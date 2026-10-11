# AnthroBSK Skill

[English](README.md) | **繁體中文**

AnthroBSK 是一個 Agent 技能，用**像真人的方式**操作你真實登入的 Chromium 瀏覽器：
所有動作都透過模擬的滑鼠與鍵盤輸入完成，而不是直接注入 DOM 值。

它是 [Tencent BrowserSkill](https://github.com/Tencent/BrowserSkill)（MIT 授權）
所附 `browser-skill` 的衍生版本，改寫成以「人類化操作」為核心互動模型。

## 它有什麼不同

| 原始 browser-skill | AnthroBSK |
| --- | --- |
| `fill` 批次文字注入（`Input.insertText`） | 逐鍵 `bsk press`，ASCII **與中日韓文字皆已驗證**，每鍵間隔隨機 |
| `select` 直接設定 `<select>` 的值 | 點開下拉選單，用方向鍵選到選項，按 `Enter` |
| 固定或沒有節奏控制 | 隨機動作停頓（180–520 ms）、較長的「思考」停頓（700–2000 ms）、送出前停頓 |
| 沒有游標移動 | `scripts/human-pointer.ps1`：三次貝茲曲線的作業系統游標軌跡，含加減速、抖動、過衝後修正、隨機微停頓 |
| 語意化 DOM 指令 | 只用原生滑鼠事件（click／hover／wheel）與原生鍵盤事件（press／組合鍵／Tab／Escape） |

原始技能的安全規則全部保留：頁面內容一律視為不受信任的資料（具備提示注入防護）、
借用使用者分頁需要明確授權、絕不提取憑證／Cookie／權杖，且工作階段一定關閉。

## 這個專案「不是」什麼

在拿它去碰任何涉及機器人偵測的東西之前，請先讀這一節。

AnthroBSK 讓**互動模型**像真人。它**不會**讓產生出來的事件流變得跟真人無法區分，
也不是為了繞過反自動化系統而設計的。以下限制都是在真實頁面上**實測**得到的，不是推測。

**站得住的部分。** 瀏覽器是使用者本人真正的 Chrome，所以 `navigator.webdriver` 為
`false`、`navigator.plugins` 與 `navigator.languages` 都是真的，而且每個送出的事件
`isTrusted` 皆為 `true`。凡是「這個瀏覽器是不是被自動化框架操控？」這類檢查都會通過。

**站不住的部分**（Windows、Chrome 155、bsk 0.3.2）：

- **點擊時序。** 一次 `click` 到達頁面時只有一個 `mousemove`，接著 2–4 ms 後送出
  `mousedown`，再 0.8–2 ms 後送出 `mouseup`——整個手勢約 6 ms。真人移動 80–300 ms 之後
  會按住按鍵 60–120 ms。那個 `pointermove` 只帶一個合併事件，而且按鍵按下的期間
  `pressure` 仍為 `0`。`bsk click` 沒有提供按住時長或預先移動的參數，所以技能層無法補救。
- **輸入法事件。** 打出來的字元是 CDP 的 `char` 事件。遇到中文時，頁面看到的是
  `code: ""`、`keyCode: 0`，而且 `keypress.keyCode` 等於該字元的碼位（code point），
  不是虛擬鍵碼。整個過程**不會**送出 `compositionstart`／`compositionupdate`／
  `compositionend`，`isComposing` 全程維持 `false`。因此頁面可以判斷這些中文不是真的
  輸入法打出來的——真實輸入法在組字期間會是 `insertCompositionText` 搭配 `keyCode: 229`。
- **節奏。** 每一次 `bsk` 呼叫都會啟動一個行程，成本約 0.9–1.2 秒，這個固定開銷完全
  蓋過每鍵的停頓設定。實測到的按鍵間隔彼此只差幾個百分點——**比真人打字更規律，而不是更像人**。
- **游標軌跡。** Chrome 會合併 `mousemove`，所以一條很長的作業系統游標路徑，通常只有
  最後一點會到達頁面。

一句話總結：它能通過「這個操作是不是自動化的？」這種靜態檢查，但過不了行為層面的檢查。
如果你要對抗的是 Akamai、Cloudflare Bot Management、DataDome、HUMAN、Kasada 這類
專業反自動化系統，請把它視為不適用。

`SKILL.md` 裡的「Verified limitation」註記有同樣的實測數據，放在對應的段落脈絡中。

## 環境需求

- [`bsk` CLI 與瀏覽器擴充功能](https://github.com/Tencent/BrowserSkill)——AnthroBSK
  是建立在其上的技能層，不會代你安裝它們。
- Windows PowerShell（只有 `scripts/human-pointer.ps1` 需要；技能其餘部分與作業系統無關）。
- 任何能讀取 `SKILL.md` 形式技能的 Agent 宿主（Qoder、Claude Code、Codex、OpenCode、
  CodeBuddy……）。

## 安裝

把 `anthro-bsk` 資料夾複製到宿主的使用者層技能目錄：

```sh
# Qoder / 一般 AGENTS 慣例
cp -r anthro-bsk ~/.agents/skills/anthro-bsk

# Claude Code
cp -r anthro-bsk ~/.claude/skills/anthro-bsk

# WorkBuddy / CodeBuddy
cp -r anthro-bsk ~/.workbuddy-ai/skills/anthro-bsk
```

重新啟動工作階段（或重新載入技能），然後用 `/anthro-bsk` 或任何瀏覽器自動化需求觸發它。
**新安裝的技能要下一個工作階段才會生效**，當前這個不會。

> 小提醒：不要把它裝成 `browser-skill` 這個名字——那個名字由 `bsk install-skill` 管理，
> 更新時會把這個技能覆蓋掉。

## 使用範例

```
/anthro-bsk 打開 example.com，在搜尋框逐字輸入「台北 天氣」，然後按 Enter
```

Agent 會依序：啟動 `bsk` 工作階段 → 導覽 → 用 `screenshot`／`observe` 感知頁面 →
以原生滑鼠事件 hover／click → 用 `Ctrl+A` + `Delete` 清空欄位 → 用逐鍵 `bsk press`
搭配隨機停頓打字 → 重新截圖驗證 → 關閉工作階段。

## 已驗證行為

驗證時間 2026-10-11，環境為 Windows 11、Chrome 155.0.0.0、bsk CLI／擴充功能 0.3.2：

- 逐鍵 `bsk press` 能把 ASCII 與中日韓文字（例如 `Hello測試`）打進取得焦點的欄位。
- 繁體中文與簡體中文都能用，全形標點也可以；`繁體中文輸入測試，臺北天氣很好`
  逐字打進去後完整無誤。界線在於是否屬於 BMP，與繁簡無關：超出基本多文種平面
  （BMP）的字元（表情符號、CJK 擴充 B 以上）會被拒絕，回報 `press: unknown key`。
- `Ctrl+A` → `Delete` 會像真人一樣清空欄位；`Enter` 會送出。
- `bsk hover`／`click` 會以真實的 `mousemove`／`mousePressed`／`mouseReleased` 事件落地，
  且 `isTrusted: true`。
- `human-pointer.ps1` 會沿著隨機化的貝茲曲線移動作業系統游標，並輸出
  `ok path=(x,y)->(x,y) steps=N ms=T`。

**未驗證**：WorkBuddy 以外的宿主、Windows 以外的作業系統、0.3.2 以外的 bsk 版本。

## 已知限制

- Chrome 會**合併** `mousemove` 輸入：一條很長的作業系統游標軌跡，可能只有最後一點會
  到達 Agent Window 頁面。軌跡腳本能讓畫面看起來自然，但不保證能通過滑鼠軌跡類的
  機器人檢查。若要讓頁面真的觀察到移動，請沿著合理路徑 hover 2–4 個控制項，中間夾隨機停頓。
- 作業系統游標座標是虛擬螢幕空間中的實體像素。在縮放或雙螢幕以上的環境，請先確認一個落點。
- 像素點擊（`--image-x`／`--image-y`）在 `bsk` 中僅限 Canvas；HTML 目標要用 ref 或
  CSS 選擇器點擊，這仍然會送出原生滑鼠事件。
- `human-pointer.ps1` 會移動使用者真正的游標，所以在路徑執行期間滑鼠指標是被佔用的。
- 部分宿主會擋下從 POSIX shell 呼叫 `powershell -File ...`，也會擋下命令字串中直接出現的
  `Add-Type`。請改用宿主的 PowerShell 工具、以絕對路徑呼叫腳本。
- 檔案上傳與驗證碼／登入流程仍保留上游的逃生出口（`upload`、請求人工協助）。

## 授權

MIT © 2026 htlu1975。建立於 Tencent BrowserSkill 的 browser-skill（MIT © Tencent）
之上；詳見 `LICENSE` 與 `references/`。
