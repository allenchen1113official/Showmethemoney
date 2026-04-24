-- ============================================================
-- Show Me The Money — Supabase 自選股儲存設定腳本（簡化版）
-- 使用方式：
--   1. 至 Supabase Dashboard → SQL Editor
--   2. 新建 query，貼上整份內容後按「Run」
--   3. 執行結果應看到「Success. No rows returned」
--   4. 回到看盤頁，登入帳號 → 編輯自選股 → 儲存
-- ------------------------------------------------------------
-- 本腳本會保留 user_id，並將舊的 stocks（text[]）代號搬到新的
-- jsonb 結構中；舊的 shares / cost 無法保留（舊資料沒有）。
-- idempotent：可重複執行。
-- ============================================================

-- 1. 建立 portfolios 資料表（若不存在）
create table if not exists public.portfolios (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  stocks     jsonb not null default '{"count":10,"items":[],"sort":"mcap"}'::jsonb,
  updated_at timestamptz not null default now()
);

-- 2. 把 stocks 欄位型別改成 jsonb（採用方案 B：保留舊代號）
--    作法：新增 stocks_new jsonb 欄位 → 搬資料 → DROP 舊 stocks → RENAME
--    idempotent：stocks 已是 jsonb 時整段略過。
do $$
declare
  col_type text;
  col_udt  text;
begin
  select data_type, udt_name
    into col_type, col_udt
    from information_schema.columns
   where table_schema = 'public'
     and table_name   = 'portfolios'
     and column_name  = 'stocks';

  raise notice '[smtm] stocks 欄位目前 data_type=%  udt_name=%', col_type, col_udt;

  if col_type = 'jsonb' then
    raise notice '[smtm] stocks 已是 jsonb，跳過重建';
    return;
  end if;

  -- 2.1 建立新欄位（帶 jsonb default）
  alter table public.portfolios
    add column if not exists stocks_new jsonb
    default '{"count":10,"items":[],"sort":"mcap"}'::jsonb;

  -- 2.2 把舊代號搬到 stocks_new
  if col_type = 'ARRAY' then
    -- 舊欄位為 text[] / varchar[]：unnest 產生 items 陣列
    update public.portfolios p
       set stocks_new = jsonb_build_object(
             'count', coalesce(array_length(p.stocks, 1), 0),
             'items', coalesce((
               select jsonb_agg(
                        jsonb_build_object(
                          'code',   x::text,
                          'shares', 0,
                          'cost',   0
                        )
                      )
                 from unnest(p.stocks) as x
                where x is not null and x::text <> ''
             ), '[]'::jsonb),
             'sort', 'mcap'
           )
     where p.stocks is not null;
  elsif col_type in ('text', 'character varying', 'character') then
    -- 舊欄位為字串：可能存 JSON 字串，直接 parse
    update public.portfolios p
       set stocks_new = p.stocks::jsonb
     where p.stocks is not null
       and p.stocks <> '';
  end if;

  -- 2.3 刪掉舊欄位、新欄位改名成 stocks
  alter table public.portfolios drop column stocks;
  alter table public.portfolios rename column stocks_new to stocks;

  -- 2.4 補 not null 約束（上一步的 default 會讓 null 列填入預設值）
  update public.portfolios set stocks = '{"count":10,"items":[],"sort":"mcap"}'::jsonb
    where stocks is null;
  alter table public.portfolios alter column stocks set not null;
end$$;

-- 3. 啟用 Row Level Security
alter table public.portfolios enable row level security;

-- 4. 刪除舊 policy（若有）避免重複衝突
drop policy if exists "portfolios_select_own"  on public.portfolios;
drop policy if exists "portfolios_insert_own"  on public.portfolios;
drop policy if exists "portfolios_update_own"  on public.portfolios;
drop policy if exists "portfolios_delete_own"  on public.portfolios;
drop policy if exists "Enable read access for own"   on public.portfolios;
drop policy if exists "Enable insert for own"        on public.portfolios;
drop policy if exists "Enable update for own"        on public.portfolios;

-- 5. 建立 RLS policies：使用者只能讀寫自己那筆
create policy "portfolios_select_own"
  on public.portfolios for select
  to authenticated
  using (auth.uid() = user_id);

create policy "portfolios_insert_own"
  on public.portfolios for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "portfolios_update_own"
  on public.portfolios for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "portfolios_delete_own"
  on public.portfolios for delete
  to authenticated
  using (auth.uid() = user_id);

-- 6. 自動更新 updated_at
create or replace function public.tg_portfolios_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end$$;

drop trigger if exists trg_portfolios_touch_updated_at on public.portfolios;
create trigger trg_portfolios_touch_updated_at
  before update on public.portfolios
  for each row execute function public.tg_portfolios_touch_updated_at();

-- 7. 驗證（執行完後可選擇性單獨跑以下查詢）
-- select column_name, data_type from information_schema.columns
--   where table_schema='public' and table_name='portfolios';
-- select policyname, cmd from pg_policies where tablename='portfolios';
-- select user_id, jsonb_array_length(stocks->'items') as items, updated_at
--   from public.portfolios where user_id = auth.uid();
