# AnthroBSK Skill

[English](README.md) | **繁體中文**

AnthroBSK 是一個 Agent 技能，用**像真人的方式**操作你真實登入的 Chromium 瀏覽器：
所有動作都透過模擬的滑鼠與鍵盤輸入完成，而不是直接注入 DOM 值。

它是 [Tencent BrowserSkill](https://github.com/Tencent/BrowserSkill)（MIT 授權）
所附 `browser-skill` 的衍生版本，改寫成以「人類化操作」為核心互動模型。

> 儲存庫名稱是 `AnthroBSK`，但技能本身安裝為 `anthrobsk`。宿主的技能名稱驗證規則為
> `^[a-z0-9-]+$`，不接受大寫字母。`AnthroBSK` 是用在其他所有地方的顯示名稱。

## 它有什麼不同

| 原始 browser-skill | AnthroBSK |
| --- | --- |
| `fill` 批次文字注入（`Input.insertText`） | ASCII 用逐鍵 `bsk press`，要打字節奏時用 `scripts/human-keys.ps1`，中日韓文字用剪貼簿貼上 |
| `select` 直接設定 `<select>` 的值 | 點開下拉選單，用方向鍵選到選項，按 `Enter` |
| 固定或沒有節奏控制 | 隨機動作停頓（180–520 ms）、較長的「思考」停頓（700–2000 ms）、送出前停頓 |
| 沒有游標移動 | `scripts/human-pointer.ps1`：三次貝茲曲線的作業系統游標軌跡，**頁面真的收得到**——實測一次跑出 54 個 `mousemove` |
| 語意化 DOM 指令 | 只用原生滑鼠事件（click／hover／wheel）與原生鍵盤事件（press／組合鍵／Tab／Escape） |

原始技能的安全規則全部保留：頁面內容一律視為不受信任的資料（具備提示注入防護）、
借用使用者分頁需要明確授權、絕不提取憑證／Cookie／權杖，且工作階段一定關閉。

## 這個專案「不是」什麼

在拿它去碰任何涉及機器人偵測的東西之前，請先讀這一節。

AnthroBSK 讓**互動模型**像真人。它**不會**讓產生出來的事件流變得跟真人無法區分，
也不是為了繞過反自動化系統而設計的。以下限制都是在真實頁面上**實測**得到的，不是推測。

**站得住的部分。** 瀏覽器是使用者本人真正的 Chrome，所以 `navigator.webdriver` 為
`false`、`navigator.plugins` 與 `navigator.languages` 都是真的，而且每個送出的事件
`isTrusted` 皆為 `true`。真實的游標軌跡也確實送達了——約 1.2 秒內 54 個 `mousemove`，
位移量在 2–22 px 之間變化、取樣間隔 5–49 ms，而且是走作業系統輸入佇列，不是在 DOM 層注入。

**站不住的部分**（Windows、Chrome 155、bsk 0.3.2）：

- **bsk 會在頁面裡自我揭露。** 擴充功能會把 `browser-skill-overlay` 元素注入頁面的主世界：
  `position: fixed`、`z-index: 2147483647`、覆蓋整個 viewport，並帶有 `data-bsk-overlay`、
  `data-bsk-overlay-surface`、`data-bsk-overlay-blocking` 屬性。任何網頁只要執行
  `document.querySelector('browser-skill-overlay')` 就知道有 Agent 在操作。這是最大的一個破口，
  而且不是本技能能藏得掉的。
- **作業系統層的點擊碰不到頁面內容。** 同一個覆蓋層的 `pointer-events` 是 `auto`，所以
  `document.elementFromPoint(x, y)` 會回傳 `BROWSER-SKILL-OVERLAY`，真正的控制項收不到
  `mousedown`／`click`。想中和它也沒用：它會被自動重新注入，而且它的
  `:host{all:initial !important}` 位於 CSS 的 `@layer` 內，所以行內
  `pointer-events: none !important` 與注入到它 shadow root 的規則**都會在串接中落敗**
  （未分層的 `!important` 是最弱的一種）。因此點擊只能走 `bsk click`，由它直接鎖定元素。
- **點擊時序。** 一次 `bsk click` 到達頁面時只有一個 `mousemove`，接著 2–4 ms 後送出
  `mousedown`，再 0.8–2 ms 後送出 `mouseup`——整個手勢約 6 ms。真人移動 80–300 ms 之後
  會按住按鍵 60–120 ms。那個 `pointermove` 只帶一個合併事件，而且按鍵按下的期間
  `pressure` 仍為 `0`。`bsk click` 沒有提供按住時長或預先移動的參數，技能層無法補救。
- **輸入法事件。** 打出來的字元是 CDP 的 `char` 事件。遇到中文時，頁面看到的是
  `code: ""`、`keyCode: 0`，而且 `keypress.keyCode` 等於該字元的碼位（code point），
  不是虛擬鍵碼。整個過程**不會**送出 `compositionstart`／`compositionupdate`／
  `compositionend`，`isComposing` 全程維持 `false`，因此頁面可以判斷這些中文不是真的
  輸入法打出來的——真實輸入法在組字期間會是 `insertCompositionText` 搭配 `keyCode: 229`。
  改用作業系統層按鍵也補不起來：要驅動真實輸入法就得處理候選字選擇，而且在此環境下
  鍵盤配置代碼解析為 `0x0`，字元轉譯並不可靠。本技能改用貼上，會產生真實的
  `insertFromPaste`，但貼上終究還是貼上。
- **透過 CLI 打 ASCII 的間隔。** 每一次 `bsk press` 都要一趟完整的 daemon 往返，所以連續
  按鍵之間約隔 660 ms——**比真人打字更規律，而不是更像人**。`scripts/human-keys.ps1`
  能修掉節奏問題（每鍵約 190 ms 且帶抖動），但僅限 ASCII。

一句話總結：它能通過「這個操作是不是自動化的？」這種靜態檢查，但過不了行為層面的檢查，
而且藏不住 bsk 留在頁面裡的足跡。如果你要對抗的是 Akamai、Cloudflare Bot Management、
DataDome、HUMAN、Kasada 這類專業反自動化系統，請把它視為不適用。

`SKILL.md` 裡的「Verified limitation」註記有同樣的實測數據，放在對應的段落脈絡中。

## 環境需求

- [`bsk` CLI 與瀏覽器擴充功能](https://github.com/Tencent/BrowserSkill)——AnthroBSK
  是建立在其上的技能層，不會代你安裝它們。
- Windows PowerShell——只有 `scripts/` 裡的兩支腳本需要；技能其餘部分與作業系統無關。
  兩支腳本都具 DPI 感知，且會在動作前先把 Agent Window 帶到前景。
- 任何能讀取 `SKILL.md` 形式技能的 Agent 宿主（Qoder、Claude Code、Codex、OpenCode、
  CodeBuddy……）。

## 安裝

把 `anthrobsk` 資料夾複製到宿主的使用者層技能目錄：

```sh
# Qoder / 一般 AGENTS 慣例
cp -r anthrobsk ~/.agents/skills/anthrobsk

# Claude Code
cp -r anthrobsk ~/.claude/skills/anthrobsk

# WorkBuddy / CodeBuddy
cp -r anthrobsk ~/.workbuddy-ai/skills/anthrobsk
```

重新啟動工作階段（或重新載入技能），然後用 `/anthrobsk` 或任何瀏覽器自動化需求觸發它。
**新安裝的技能要下一個工作階段才會生效**，當前這個不會。

> 小提醒：不要把它裝成 `browser-skill` 這個名字——那個名字由 `bsk install-skill` 管理，
> 更新時會把這個技能覆蓋掉。

## 使用範例

```
/anthrobsk 打開 example.com，在搜尋框逐鍵輸入 hello，接著貼上「台北 天氣」，然後按 Enter
```

Agent 會依序：啟動 `bsk` 工作階段 → 導覽 → 用 `screenshot`／`observe` 感知頁面 →
畫出真實游標軌跡並點擊 → 用 `Ctrl+A` + `Delete` 清空欄位 → ASCII 用 `human-keys.ps1` 打、
中文用貼上 → 重新截圖驗證 → 關閉工作階段。

## 已驗證行為

驗證時間 2026-10-11，環境為 Windows 11、Chrome 155.0.0.0、bsk CLI／擴充功能 0.3.2：

- `human-pointer.ps1` 沿著隨機化的貝茲曲線驅動作業系統游標，頁面收到真實軌跡：
  約 1.2 秒內 54 個 `mousemove`，位移量在 2–22 px 之間變化，取樣間隔 5–49 ms。
  單用 `SetCursorPos` 則產生**零個**頁面事件；`SendInput(MOUSEEVENTF_MOVE)` 回報 1
  卻什麼都沒做。
- `human-keys.ps1` 用 `keybd_event` 打 ASCII；`Hello, World 42! aBc` 以 191 ms/字元
  打完，大小寫與 Shift 使用全部正確。把錯字修正路徑強制拉到 30% 時，`the quick brown fox`
  依然完整無誤，而且頁面在過程中看到五次真實的「打錯鍵 → Backspace → 重打」序列。
- 逐鍵 `bsk press` 能把 ASCII 正確打進取得焦點的欄位（`key`／`code`／`keyCode`、
  `keypress`、`insertText` 皆正確），中文也可以，例如 `Hello測試`。繁體中文與簡體中文
  都能用，全形標點也可以；`繁體中文輸入測試，臺北天氣很好` 逐字打進去後完整無誤。
  界線在於是否屬於 BMP，與繁簡無關：超出基本多文種平面（BMP）的字元（表情符號、
  CJK 擴充 B 以上）會被拒絕，回報 `press: unknown key`。
- 混合輸入可行：`a`、`b` 用真實 `press` 事件，加上貼上的 `台北天氣`，最後到達的是
  `ab台北天氣`；貼上以單一個 `insertFromPaste` 落地，前面只有一次 `keydown V`。
- `Ctrl+A` → `Delete` 會像真人一樣清空欄位；`Enter` 會送出。
- `bsk hover`／`click` 會以真實的 `mousemove`／`mousePressed`／`mouseReleased` 事件落地，
  且 `isTrusted: true`。

**未驗證**：WorkBuddy 以外的宿主、Windows 以外的作業系統、0.3.2 以外的 bsk 版本。

## 已知限制

- 作業系統游標座標是 CSS viewport 像素，在執行時由視窗真實的 render widget 矩形換算而來。
  不要用 `devicePixelRatio` 代替：實測有一個視窗回報 `1.5`，但真實比例是 `1.0`；同一個
  視窗後來移到另一個螢幕，比例又變成 `1.5`。
- `mouse_event` 與 `keybd_event` 只有在 Agent Window 是前景視窗時才會送達頁面。兩支腳本
  都會強制搶前景並**驗證**是否搶到，搶不到就回傳非零結束碼，而不是對著錯的視窗亂動作。
  搶前景會把使用者正在做的事打斷。
- Chrome 會**合併** `mousemove`，所以頁面收到的事件比腳本送出的少：140 步產生 54 個事件。
  軌跡是真的，只是被抽稀了。
- 像素點擊（`--image-x`／`--image-y`）在 `bsk` 中僅限 Canvas；HTML 目標要用 ref 或
  CSS 選擇器點擊，這仍然會送出原生滑鼠事件。
- `human-pointer.ps1` 會移動使用者真正的游標，所以在路徑執行期間滑鼠指標是被佔用的。
- 部分宿主會擋下從 POSIX shell 呼叫 `powershell -File ...`，也會擋下命令字串中直接出現的
  `Add-Type`。請改用宿主的 PowerShell 工具、以絕對路徑呼叫腳本。
- 檔案上傳與驗證碼／登入流程仍保留上游的逃生出口（`upload`、請求人工協助）。

## 授權

MIT © 2026 htlu1975。建立於 Tencent BrowserSkill 的 browser-skill（MIT © Tencent）
之上；詳見 `LICENSE` 與 `references/`。
