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

-- 2. 確保欄位型別正確（若舊表欄位不符，轉成 jsonb）
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'portfolios'
      and column_name = 'stocks' and data_type <> 'jsonb'
  ) then
    alter table public.portfolios
      alter column stocks type jsonb using stocks::jsonb;
  end if;
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
