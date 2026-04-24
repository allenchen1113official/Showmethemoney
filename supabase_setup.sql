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
--    舊版本可能是 text[]（單純代號陣列），需改用 to_jsonb() 才能正確轉型；
--    text / varchar 則用 ::jsonb 解析；其他型別則先轉 text 再 parse。
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

  if col_type is null then
    return;  -- 欄位不存在，略過
  end if;

  if col_type = 'jsonb' then
    return;  -- 已是目標型別
  end if;

  -- 舊欄位可能帶有與 jsonb 不相容的 DEFAULT（例如 '{}'::text[]），
  -- 先移除 DEFAULT 以避免 42804「default cannot be cast automatically」錯誤，
  -- 轉型完成後會在最後重新設定新的 jsonb DEFAULT。
  alter table public.portfolios alter column stocks drop default;

  if col_type = 'ARRAY' then
    -- 如 text[]、varchar[]：PostgreSQL 不允許 USING 子句含 subquery，
    -- 因此建立 helper function 包住 unnest + jsonb_agg 的聚合邏輯，
    -- 再在 USING 中呼叫該 function；轉型完成後即可 DROP 掉。
    create or replace function public._smtm_stocks_arr_to_jsonb(arr text[])
      returns jsonb
      language sql
      immutable
    as $f$
      select jsonb_build_object(
        'count', coalesce(array_length(arr, 1), 0),
        'items', coalesce(
          (
            select jsonb_agg(
                     jsonb_build_object('code', x, 'shares', 0, 'cost', 0)
                   )
              from unnest(arr) as x
          ),
          '[]'::jsonb
        ),
        'sort', 'mcap'
      );
    $f$;

    alter table public.portfolios
      alter column stocks type jsonb
      using public._smtm_stocks_arr_to_jsonb(stocks);

    drop function if exists public._smtm_stocks_arr_to_jsonb(text[]);
  elsif col_type in ('text', 'character varying', 'character') then
    -- 字串欄位（可能存 JSON 字串）：直接 parse
    alter table public.portfolios
      alter column stocks type jsonb using stocks::jsonb;
  else
    -- 其他型別：先轉 text 再 parse（保底）
    alter table public.portfolios
      alter column stocks type jsonb using (stocks::text)::jsonb;
  end if;
end$$;

-- 2b. 補回 jsonb 格式的 DEFAULT（前面為了轉型安全已 DROP 掉舊 default）
alter table public.portfolios
  alter column stocks set default '{"count":10,"items":[],"sort":"mcap"}'::jsonb;

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
