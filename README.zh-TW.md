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
| `fill` 批次文字注入（`Input.insertText`） | ASCII 用逐鍵 `bsk press`，要打字節奏時用 `scripts/human-keys.ps1`，中日韓文字走真實的作業系統輸入法 |
| `select` 直接設定 `<select>` 的值 | 點開下拉選單，用方向鍵選到選項，按 `Enter` |
| 固定或沒有節奏控制 | 隨機動作停頓（180–520 ms）、爆打後的停頓（每 8–15 鍵停 300–800 ms）、句尾停頓（400–900 ms）、送出前停頓 |
| 沒有游標移動 | `scripts/human-pointer.ps1`：最小顛簸（minimum-jerk）的作業系統游標軌跡，搭配有相關性的（Ornstein-Uhlenbeck）手抖——實測一次跑出 43–52 個 `mousemove` |
| 覆蓋層會吃掉作業系統點擊 | 用擴充功能自己的 `data-bsk-capture-hidden` 開關，讓真實游標軌跡與作業系統點擊能送達頁面內容 |
| 語意化 DOM 指令 | 只用原生滑鼠事件（click／hover／wheel）與原生鍵盤事件（press／組合鍵／Tab／Escape） |

原始技能的安全規則全部保留：頁面內容一律視為不受信任的資料（具備提示注入防護）、
借用使用者分頁需要明確授權、絕不提取憑證／Cookie／權杖，且工作階段一定關閉。

## 這個專案「不是」什麼

在拿它去碰任何涉及機器人偵測的東西之前，請先讀這一節。

AnthroBSK 讓**互動模型**像真人。它**不會**讓產生出來的事件流變得跟真人無法區分，
也不是為了繞過反自動化系統而設計的。以下限制都是在真實頁面上**實測**得到的，不是推測。

**站得住的部分。** 瀏覽器是使用者本人真正的 Chrome，所以 `navigator.webdriver` 為
`false`、`navigator.plugins` 與 `navigator.languages` 都是真的，而且每個送出的事件
`isTrusted` 皆為 `true`。有三件原本卡死的限制，現在已經攻克：

- **作業系統輸入能送達頁面內容。** 擴充功能自己的 `data-bsk-capture-hidden` 屬性可以
  把覆蓋層藏起來（`display: none`，命中測試直接穿透），所以作業系統層點擊會落在真正的
  控制項上，真實游標軌跡也送得進去——約 1.2–3.1 秒內 43–52 個 `mousemove`，帶有相關性
  手抖，而且走的是作業系統輸入佇列，不是在 DOM 層注入。
- **點擊具備真人時序。** 覆蓋層藏起來之後，`human-pointer.ps1 -Click` 會按住按鍵
  66–132 ms（`bsk click` 只有約 6 ms）、`pointerdown.pressure` 回報 0.5，而且按住的期間
  會送出 43–52 個 `pointermove`。`bsk click` 只送一個合併移動、`pressure` 為 0、整個手勢
  約 6 ms。
- **中日韓文字走真實輸入法。** `human-keys.ps1` 驅動作業系統鍵盤，所以微軟注音是真的在
  組字：每個鍵 `keyCode 229` 的 `Process` keydown、`compositionstart`／`update`／`end`、
  `insertCompositionText`、`isComposing: true`。打 `w961o3` 得到 `台北`，聲調符號會自動
  定字，不需要空白鍵。

**仍然站不住的部分**（Windows、Chrome 155、bsk 0.3.2）：

- **bsk 還是會在頁面裡自我揭露。** 把覆蓋層藏起來只是表面功夫：`browser-skill-overlay`
  元素仍然在 DOM 裡，是 `<html>` 的直接子元素，仍然帶著 `data-bsk-overlay`、
  `data-bsk-overlay-surface`、`data-bsk-overlay-blocking`。任何網頁只要執行
  `document.querySelector('browser-skill-overlay')` 就知道有 Agent 在操作。這是最大的
  一個破口，而且不是本技能能移除的——把節點刪掉，擴充功能會重新注入，還可能把 renderer
  卡死。
- **其他方法都中和不了覆蓋層。** 試過四種替代做法，全部失敗：行內
  `pointer-events: none !important`、注入到它 shadow root 的規則、未分層的 `!important`
  規則，以及單獨移除 `data-bsk-overlay-blocking`。覆蓋層的 `:host{all:initial
  !important}` 位於 shadow tree 內，而對 `!important` 宣告來說，**內層脈絡勝出**——
  shadow tree 的規則會擊敗所有 document 來源的宣告，連 `!important` 也一樣。只有擴充功能
  自己的開關有效。
- **藏起覆蓋層要付出代價。** `display: none` 意味著覆蓋層不再把頁面變暗，所以 `screenshot`
  不會拍到它——但頁面看起來也就正常了，因此截圖同樣無法證明覆蓋層是藏起來的。而且只有
  `screenshot` 會把屬性還原；`click`／`press`／`hover`／`observe` 都會讓它維持隱藏。
- **作業系統滾輪確實送達頁面，但頁面無法被它捲動。** `human-wheel.ps1` 送出
  `mouse_event(MOUSEEVENTF_WHEEL)`；Windows 會把滾輪送給**游標下方**的視窗，而不是前景
  視窗，所以要先把游標停在滾動目標上（`-CssX/-CssY` 加 viewport 尺寸）。停好、覆蓋層也
  藏好之後，頁面確實收到 4 個真實的 `wheel` 事件——`isTrusted: true`、目標正確、deltaY 由
  236 遞減到 166、117、82——但每一個都帶著 `defaultPrevented: true`，盒子還是不動。頁面
  本身沒有任何 `wheel` 處理器，所以是擴充功能在 isolated world 的 `window` capture 階段對
  真實滾輪呼叫了 `preventDefault`。先前「作業系統滾輪完全無效」的記錄是游標定位造成的
  假象，在此更正。
- **`bsk` 捲動時，頁面看不到那個 wheel 事件。** `bsk wheel` 會改變 `scrollTop`（實測
  0 → 496），而且它的事件**沒有**被 `preventDefault`，但仍然到不了 `document` capture 或
  目標元素——`window.__wheelWinCap` 會增加，`__wheelDocCap` 卻始終是 0，即使 `scrollTop`
  確實改變了。可見 `window` 與 `document` 之間有東西呼叫了 `stopPropagation`。
- **`isTrusted` 分不出這兩個通道。** 由 CDP 派送的輸入（`bsk press`、`bsk click`）同樣以
  `isTrusted: true` 抵達，跟 `keybd_event` 的輸出沒有差別，因為兩者都是經由瀏覽器真正的
  輸入管線進入 renderer。別把它當成隱蔽性的保證。真正有差的是**時序與事件形狀**（見上面
  的時序條目）。
- **CDP 會繞過輸入法。** 在中文模式下 `bsk press a` 會插入字面上的 `a`，完全不產生組字，
  所以 CLI 沒辦法驅動中文這條路。而且輸入法模式是**黏著的**：打完中文之後，ASCII 按鍵會被
  轉成注音，直到在作業系統層按一次 Shift 才切回來（`bsk press Shift` 會被拒絕；腳本改用
  `keybd_event` 送出）。
- **`bsk press` 的間隔很規律。** 每一次 `bsk press` 都要一趟完整的 daemon 往返，所以連續
  按鍵之間約隔 660 ms——**比真人打字更規律，而不是更像人**。`human-keys.ps1` 能修掉節奏
  問題（對數常態間隔、爆打停頓、雙字母加速），但僅限 ASCII；中文現在能走輸入法了，代價是
  要提供拼音／注音讀音，而不是直接給字。

一句話總結：它能通過「這個操作是不是自動化的？」這種靜態檢查，但過不了行為層面的檢查，
而且藏不住 bsk 留在頁面裡的足跡。如果你要對抗的是 Akamai、Cloudflare Bot Management、
DataDome、HUMAN、Kasada 這類專業反自動化系統，請把它視為不適用。

`SKILL.md` 裡的「Verified limitation」註記有同樣的實測數據，放在對應的段落脈絡中。

## 環境需求

- [`bsk` CLI 與瀏覽器擴充功能](https://github.com/Tencent/BrowserSkill)——AnthroBSK
  是建立在其上的技能層，不會代你安裝它們。
- Windows PowerShell——只有 `scripts/` 裡的腳本需要；技能其餘部分與作業系統無關。
  這些腳本都具 DPI 感知，且會在動作前先把 Agent Window 帶到前景。
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
用擴充功能自己的 `data-bsk-capture-hidden` 開關把覆蓋層藏起來 → 畫出真實游標軌跡並點擊 →
用 `Ctrl+A` + `Delete` 清空欄位 → ASCII 用 `human-keys.ps1` 打（若想要真實的組字痕跡，
中文改走作業系統輸入法）→ 重新截圖驗證 → 關閉工作階段。

## 已驗證行為

驗證時間 2026-10-11，環境為 Windows 11、Chrome 155.0.0.0、bsk CLI／擴充功能 0.3.2：

- **覆蓋層藏得起來。** 執行
  `bsk evaluate --session <id> 'document.querySelector("browser-skill-overlay").setAttribute("data-bsk-capture-hidden","")'`
  會把覆蓋層設成 `display: none`：`document.elementFromPoint(x, y)` 之後回傳真正的元素，
  作業系統點擊會把 `document.activeElement` 移到目標輸入框，按鈕的處理函式也只觸發一次。
  這個屬性**不會**被還原——10 秒後仍然隱藏。只有 `screenshot` 會清掉它；
  `click`／`press`／`hover`／`observe` 都會讓它維持隱藏。
- `human-pointer.ps1` 沿著最小顛簸路徑、帶相關性手抖驅動作業系統游標，頁面收到真實軌跡：
  約 1.2–3.1 秒內 43–52 個 `mousemove`。單用 `SetCursorPos` 則產生**零個**頁面事件；
  `SendInput(MOUSEEVENTF_MOVE)` 回報 1 卻什麼都沒做。
- **作業系統點擊現在具備真人時序。** 覆蓋層藏起來之後，`human-pointer.ps1 -Click` 跑出
  一次 151 個事件的結果：按住 104.5 ms（各次介於 66–132 ms）、路徑 3104.8 ms、
  `pointerdown.pressure` 為 0.5，按住的期間有 43–52 個 `pointermove`。同一個按鈕用
  `bsk click` 只按住約 6 ms、`pressure` 為 0、只有一個合併移動。
- **中日韓文字走真實輸入法。** `human-keys.ps1` 在微軟注音下打 `w961o3` 得到 `台北`：
  每個鍵一次 `keydown key="Process" keyCode=229`、每個鍵兩次 `keyup`、六次
  `compositionupdate`、`inputType: insertCompositionText`、`isComposing: true`，
  而且**零個不可信事件**。聲調符號會自動定字，不需要空白鍵。唯一的瑕疵是失焦時
  Chrome 會補送一個 `isTrusted: false` 的 `compositionend`。
- `human-keys.ps1` 用 `keybd_event` 打 ASCII；`Hello, World 42! aBc` 打完大小寫與 Shift
  使用全部正確。把錯字修正路徑強制拉到 30% 時，`the quick brown fox` 依然完整無誤，
  而且頁面在過程中看到真實的「打錯鍵 → Backspace → 重打」序列。
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
`human-wheel.ps1` 能通過語法解析與離線檢查；游標停好之後，它的 wheel 事件確實會到達
頁面，但會被擴充功能 `preventDefault`，所以它不會捲動頁面——要捲動請用 `bsk wheel`。

## 已知限制

- **藏起覆蓋層是作業系統輸入的前置條件。** 任何作業系統點擊或游標路徑，都必須先套用上面
  的 `data-bsk-capture-hidden` 配方，否則覆蓋層會把它吃掉。藏起來是刻意的表面取捨：頁面
  看起來變正常，所以截圖不會再拍到覆蓋層把頁面變暗。任何 `screenshot` 都會讓覆蓋層重新
  出現，所以截完要再藏一次。
- **滾輪被拆成兩條通道。** `bsk wheel` 能捲動頁面，但頁面自己的 `wheel` 處理器不會執行；
  `human-wheel.ps1` 會產生真實、頁面看得見的 `wheel` 事件，但被擴充功能 `preventDefault`
  所以不捲動。看需求選：要位移用 `bsk wheel`，要頁面看得見的事件用 `human-wheel.ps1`。
  詳見「仍然站不住的部分」。
- 作業系統游標座標是 CSS viewport 像素，在執行時由視窗真實的 render widget 矩形換算而來。
  不要用 `devicePixelRatio` 代替：實測有一個視窗回報 `1.5`，但真實比例是 `1.0`；同一個
  視窗後來移到另一個螢幕，比例又變成 `1.5`。
- `mouse_event` 與 `keybd_event` 只有在 Agent Window 是前景視窗時才會送達頁面。這些腳本
  都會強制搶前景並**驗證**是否搶到，搶不到就回傳非零結束碼，而不是對著錯的視窗亂動作。
  搶前景會把使用者正在做的事打斷。
- Chrome 會**合併** `mousemove`，所以頁面收到的事件比腳本送出的少：63–77 步產生 43–52 個
  事件。軌跡是真的，只是被抽稀了，而且最大的間隔落在路徑中段（指標最快的地方），不是
  兩端。
- **輸入法模式是黏著的，而且會靜默失敗。** 打完中文之後，ASCII 按鍵會被轉成注音（實測
  `abc` 進到欄位變成 `ㄇ`／`ㄏ`，而腳本仍回報 `typos=0`），連導覽鍵也會被吃掉（真實的
  OS `PageDown` 在按一次 Shift 之前完全不觸發 `keydown`）。用**作業系統層**的 Shift 切回
  即可——`human-keys.ps1 -ImeReset` 會在收尾時送一次。`bsk press Shift` 會被拒絕；
  腳本改用 `keybd_event` 送出。
- 像素點擊（`--image-x`／`--image-y`）在 `bsk` 中僅限 Canvas；HTML 目標要用 ref 或
  CSS 選擇器點擊，這仍然會送出原生滑鼠事件。覆蓋層藏起來之後，作業系統層的像素點擊也能
  到達 HTML（`human-pointer.ps1 -Click` 吃 CSS 座標）。
- `human-pointer.ps1` 會移動使用者真正的游標，所以在路徑執行期間滑鼠指標是被佔用的。
- 部分宿主會擋下從 POSIX shell 呼叫 `powershell -File ...`，也會擋下命令字串中直接出現的
  `Add-Type`。請改用宿主的 PowerShell 工具、以絕對路徑呼叫腳本。
- 檔案上傳與驗證碼／登入流程仍保留上游的逃生出口（`upload`、請求人工協助）。

## 授權

MIT © 2026 htlu1975。建立於 Tencent BrowserSkill 的 browser-skill（MIT © Tencent）
之上；詳見 `LICENSE` 與 `references/`。
