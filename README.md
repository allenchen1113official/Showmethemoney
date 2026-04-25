# Show Me The Money — 台股看盤儀表板

一個以單頁 HTML 打造、部署於 GitHub Pages 的台股看盤工具。前端零建置（無 webpack / 無 npm build），所有市場資料即時抓取自公開 API，使用者個人化資料（自選股、推薦快照、各類快取）由 Supabase 託管，提供跨裝置同步與匿名公用快取。

> 「Show me the money!」— 把市場關鍵數字、籌碼、新聞輿情，一次攤在你面前。

---

## ✨ 功能特色

### 大盤總覽
- **加權指數（TAIEX）／櫃買指數（OTC）**：即時報價、漲跌幅、成交量
- **台指期（TXF）日盤 / 夜盤**：當日結算與夜盤連續報價
- **三大法人大盤買賣超**（外資 / 投信 / 自營商，BFI82U）
- **景氣燈號**：國發會 NDC 領先指標分數與紅黃藍燈
- **財經行事曆**：央行理事會、CPI、FOMC、除權息高峰等重點日期

### 自選股
- 支援上市（TSE）/ 上櫃（OTC）混合
- 持股數、平均成本、損益試算
- 拖曳排序、快速新增 / 刪除
- 自動帶出近期新聞（含中英文翻譯）
- **跨裝置同步**：登入後自動以 Supabase 同步，手機 / 電腦 / 平板無縫切換

### 推薦個股（智能選股）
每日依以下條件動態挑選：
- **技術面**：近期收盤站上均線、成交量放大
- **籌碼面**：外資 **連續 3 日**淨買超 **且** 投信 **連續 3 日**淨買超（雙重確認）
- **基本面**：合理 P/E、殖利率（Goodinfo）
- 每日快照存入 `recommendation_snapshots`，支援回看歷史推薦

### 新聞與輿情
- **自選股新聞**：依代號抓取相關報導，自動翻譯英文標題為繁中
- **財經新聞 Top 5**：UDN、Google News
- **Reddit 熱門**：r/wallstreetbets、r/stocks、r/investing
- **PTT 八卦／股板**：熱門推文

### 帳號 / 同步
- Supabase Auth（Email magic link / OAuth）
- Row Level Security：每位使用者只能讀寫自己的 portfolio
- 視窗 visibility / focus 自動拉取雲端最新資料

### 其他
- 理財格言輪播
- 翻譯快取（Google Translate）30 天 TTL，省流量
- 全網頁深色 UI，行動裝置 RWD

---

## 🏗️ 技術架構

```
┌──────────────────────────────────────────────────────────┐
│  index.html  (single-file SPA, ~190KB)                   │
│  ├─ Vanilla JS + Supabase JS UMD                         │
│  ├─ CACHE_CFG / cacheGet / cacheSet  (L2 cache helpers)  │
│  ├─ localStorage (L1 cache)                              │
│  └─ Drag & Drop / Pointer Events                         │
└──────────────────────────────────────────────────────────┘
              │                          │
              ▼                          ▼
   ┌────────────────────┐      ┌────────────────────────┐
   │ Public APIs        │      │ Supabase (Postgres)    │
   │ ─ TWSE / TPEX      │      │ ─ portfolios (RLS)     │
   │ ─ TAIFEX           │      │ ─ api_cache (KV)       │
   │ ─ Yahoo Finance    │      │ ─ stock_daily          │
   │ ─ Goodinfo         │      │ ─ stock_fundamentals   │
   │ ─ NDC 景氣燈號     │      │ ─ institutional_flow   │
   │ ─ Reddit / PTT     │      │ ─ three_institutionals │
   │ ─ UDN / GoogleNews │      │ ─ business_cycle       │
   │ ─ Google Translate │      │ ─ news_items           │
   └────────────────────┘      │ ─ recommendation_…     │
                               │ ─ translations         │
                               │ ─ fin_calendar         │
                               └────────────────────────┘
```

### 雙層快取策略
- **L1 — localStorage**：瀏覽器本地，秒級反應
- **L2 — Supabase**：跨裝置共享、匿名讀取、登入者回寫
- **TTL 規則**（`CACHE_CFG.ttl`）：

  | 類別 | TTL |
  | --- | --- |
  | NDC 景氣燈號 | 24h |
  | TWSE 日線 / Goodinfo | 12h / 6h |
  | BFI82U / T86 | 6h |
  | TWSE 即時報價 | 60s |
  | 新聞 | 10 分鐘 |
  | 翻譯 | 30 天 |

### 緊急停用快取
若懷疑快取造成顯示異常，於瀏覽器 DevTools Console 執行：
```js
CACHE_CFG.enabled = false;
location.reload();
```

---

## 🚀 部署 / 本地開發

### 1. 取得專案
```bash
git clone https://github.com/allenchen1113official/Showmethemoney.git
cd Showmethemoney
```

### 2. 設定 Supabase
1. 至 [supabase.com](https://supabase.com) 建立新專案
2. 進入 **SQL Editor**，依序執行：
   - `supabase_setup.sql` — 建立 `portfolios` 表（自選股，per-user RLS）
   - `supabase_cache_setup.sql` — 建立 13 個快取／結構化表 + 2 個 view（公用快取，anon 可讀、authenticated 可寫）
3. 複製專案的 **Project URL** 與 **anon public key**

### 3. 設定前端金鑰
編輯 `config.js`：
```js
window.SMTM_CONFIG = {
  SUPABASE_URL: 'https://xxxxx.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOi...',
};
```

> ⚠️ `config.js` 含 anon key，是公開可讀的金鑰（受 RLS 保護）。**切勿**將 service_role key 放入前端。

### 4. 本地預覽
```bash
python3 serve.py        # http://localhost:8000
# 或
npx http-server -p 8000
```

### 5. 部署到 GitHub Pages
```bash
./deploy.sh
# 或手動推 main 分支，GitHub Pages 會自動發布
```

---

## 📦 檔案結構

```
Showmethemoney/
├─ index.html                 # 主程式（HTML + CSS + JS 全部在一起）
├─ config.js                  # Supabase URL / anon key（請自行填入）
├─ supabase_setup.sql         # 自選股表 schema + RLS
├─ supabase_cache_setup.sql   # 13 張公用快取 / 結構化表 + RLS + view
├─ quotes.json                # 理財格言
├─ deploy.sh                  # 一鍵部署到 GitHub Pages
├─ serve.py                   # 本地 HTTP server
└─ README.md                  # 本文件
```

---

## 🗄️ 資料表總覽

### 個人資料
| 表 | 用途 |
|---|---|
| `portfolios` | 使用者自選股、持股、成本（per-user RLS） |

### 公用快取（anon 可讀、authenticated 可寫）
| 表 | 用途 |
|---|---|
| `api_cache` | 通用 KV 快取（source + endpoint → JSON payload + TTL） |
| `market_indices` | TAIEX / OTC / TXF / TXF_NIGHT 日線 |
| `stock_daily` | 個股日 K（TWSE / TPEX / yfinance 合併） |
| `stock_quotes` | 個股即時報價（覆蓋式） |
| `stock_fundamentals` | 個股 P/E、殖利率（Goodinfo） |
| `institutional_flow` | 個股級三大法人 T86 |
| `three_institutionals` | 大盤級三大法人 BFI82U |
| `business_cycle` | 景氣燈號 |
| `news_items` | Reddit / PTT / UDN / Google News |
| `recommendation_snapshots` | 每日推薦個股快照 |
| `translations` | Google Translate 翻譯快取 |
| `fin_calendar` | 財經行事曆 |

### View
- `v_stock_latest` — 各股最新一筆日 K
- `v_news_latest` — 最近 500 則新聞

---

## 🔐 安全與隱私

- **RLS 全面啟用**：所有資料表強制 Row Level Security
- **個人資料**：`portfolios` 僅本人可讀寫（`auth.uid() = user_id`）
- **公用快取**：所有人可讀；僅登入使用者可寫；無 DELETE policy（避免惡意清空）
- **API Key**：前端僅放 anon key，敏感操作仰賴 RLS 而非密鑰權限

---

## 🧪 故障排除

| 問題 | 解法 |
|---|---|
| 自選股無法存到雲端 | 確認已執行 `supabase_setup.sql`、已登入帳號 |
| 推薦個股一直空白 | 確認 `supabase_cache_setup.sql` 已執行；T86 在交易日 18:00 後才有資料 |
| 顯示資料疑似過舊 | Console 執行 `CACHE_CFG.enabled = false; location.reload()` |
| 跨裝置自選股不同步 | 登出再登入；或開啟自選股編輯 modal 會強制 pull 雲端 |
| Goodinfo 抓不到 | 對方有反爬，會自動 fallback 至 stock_fundamentals 快取 |

---

## 🛠️ 主要外部資料來源

| 來源 | 用途 |
|---|---|
| TWSE openapi / mis | 上市股價、日 K、三大法人 |
| TPEX openapi | 上櫃股價、日 K |
| TAIFEX | 台指期日 / 夜盤 |
| Yahoo Finance Chart API | 1 年日線、即時報價備援 |
| Goodinfo | P/E、殖利率 |
| 國發會 NDC | 景氣燈號 |
| Reddit JSON / PTT / UDN RSS / Google News RSS | 新聞輿情 |
| Google Translate (gtx) | 英文標題翻譯 |

> 本專案僅作學習與個人投資資訊輔助。資料準確性以原始來源為準，不構成任何投資建議。

---

## 📝 授權

個人專案，未指定授權。如需 fork / 商用請先聯繫。

## 🙋 作者

allenchen1113.official@gmail.com
