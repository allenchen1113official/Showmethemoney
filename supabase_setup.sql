-- ============================================================
-- Show Me The Money — Supabase 自選股儲存設定腳本
-- 使用方式：
--   1. 至 Supabase Dashboard → SQL Editor
--   2. 新建 query，貼上整份內容後按「Run」
--   3. 執行結果應看到「Success. No rows returned」
--   4. 回到看盤頁，登入帳號 → 編輯自選股 → 儲存
-- ------------------------------------------------------------
-- 本腳本為 idempotent（可重複執行）：重跑不會刪除既有資料。
-- ============================================================

-- 1. 建立 portfolios 資料表（若不存在）
create table if not exists public.portfolios (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  stocks     jsonb not null default '{"count":10,"items":[],"sort":"mcap"}'::jsonb,
  updated_at timestamptz not null default now()
);

-- 2. 確保 stocks 欄位為 jsonb 型別（舊版本可能是 text[]）
--    策略：不用 ALTER COLUMN ... TYPE（容易踩 default cast / subquery 等限制），
--          改採「備份成 text → DROP 舊欄位 → ADD 新 jsonb 欄位 → 從備份重建 → 清備份」。
--    idempotent：已經是 jsonb 時，只補回正確的 DEFAULT / NOT NULL。
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

  if col_type is null then
    raise notice '[smtm] stocks 欄位不存在，add 成 jsonb';
    alter table public.portfolios
      add column stocks jsonb not null
      default '{"count":10,"items":[],"sort":"mcap"}'::jsonb;
    return;
  end if;

  if col_type = 'jsonb' then
    raise notice '[smtm] stocks 已是 jsonb，只確認 default / not null';
    alter table public.portfolios alter column stocks drop default;
    alter table public.portfolios
      alter column stocks set default '{"count":10,"items":[],"sort":"mcap"}'::jsonb;
    alter table public.portfolios alter column stocks set not null;
    return;
  end if;

  -- 非 jsonb：完整重建
  raise notice '[smtm] 將 stocks 從 % 重建為 jsonb', col_type;

  -- 2.1 備份舊值為純 text（PostgreSQL 陣列會序列化成 "{a,b,c}" 格式）
  alter table public.portfolios add column if not exists _stocks_bak text;
  update public.portfolios set _stocks_bak = stocks::text;

  -- 2.2 drop 舊欄位（同時清掉連動的 default / constraint）
  alter table public.portfolios drop column stocks;

  -- 2.3 add 新 jsonb 欄位（先 nullable，以便後續 update；最後再 set not null）
  alter table public.portfolios
    add column stocks jsonb
    default '{"count":10,"items":[],"sort":"mcap"}'::jsonb;

  -- 2.4 依舊型別把備份還原成 jsonb
  if col_type = 'ARRAY' then
    -- 例如 text[]：備份值形如 {2330,2317,2454}
    update public.portfolios
      set stocks = jsonb_build_object(
        'count',
          coalesce(
            array_length(
              string_to_array(nullif(trim(both '{}' from _stocks_bak), ''), ','),
              1
            ),
            0
          ),
        'items',
          coalesce(
            (
              select jsonb_agg(
                       jsonb_build_object(
                         'code',  trim(both '"' from x),
                         'shares', 0,
                         'cost',   0
                       )
                     )
                from unnest(
                  string_to_array(nullif(trim(both '{}' from _stocks_bak), ''), ',')
                ) as x
              where trim(both '"' from x) <> ''
            ),
            '[]'::jsonb
          ),
        'sort', 'mcap'
      )
      where _stocks_bak is not null and _stocks_bak <> '';
  elsif col_type in ('text', 'character varying', 'character') then
    -- 可能是 JSON 字串：直接 parse
    update public.portfolios
      set stocks = _stocks_bak::jsonb
      where _stocks_bak is not null and _stocks_bak <> '';
  end if;

  -- 2.5 清掉備份欄位、補上 not null
  alter table public.portfolios drop column _stocks_bak;
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

-- 7. 驗證：查詢目前的 policies（應看到 4 筆）
-- select policyname, cmd from pg_policies where tablename = 'portfolios';

-- 8. 驗證：查詢自己的資料列（登入後執行）
-- select user_id, jsonb_array_length(stocks->'items') as item_count, updated_at
--   from public.portfolios where user_id = auth.uid();
