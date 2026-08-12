-- プロンプト帳 (prompt-notebook) の Supabase スキーマ
-- 何度実行しても安全（IF NOT EXISTS / CREATE OR REPLACE 系のみ使用）

-- ============================================================
-- 1. 本体テーブル：暗号化されたノート全体（ジャンル・プロンプト一覧など）
--    アプリ内の「書き出し」機能が作るJSONの notebook 部分（salt/iv/ciphertext）と同じ形。
--    行は常に1行（id = 'notebook'）。中身はクライアント側で合言葉から作った鍵で
--    AES-GCM暗号化済みなので、Supabase側には平文は保存されません。
-- ============================================================
create table if not exists "prompt-notebook" (
  id text primary key,
  salt text not null,
  iv text not null,
  ciphertext text not null,
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 2. 画像テーブル：添付画像（暗号化生成用ジャンルの添付画像）
--    アプリ内の「書き出し」機能が作るJSONの images 配列の1件分と同じ形。
--    画像バイナリも暗号化した上でbase64文字列にして保存します。
-- ============================================================
create table if not exists "prompt-notebook-images" (
  image_id text primary key,
  iv text not null,
  mime text not null,
  cipher_b64 text not null,
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 3. RLS を有効化し、publishable(anon) keyからの全操作を許可
--    ※このアプリはユーザー認証を持たないため、鍵を知っていれば
--      誰でも読み書き削除できます（中身は暗号化されているので内容は読めません）。
-- ============================================================
alter table "prompt-notebook" enable row level security;
alter table "prompt-notebook-images" enable row level security;

drop policy if exists "allow all for anon" on "prompt-notebook";
create policy "allow all for anon" on "prompt-notebook"
  for all
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists "allow all for anon" on "prompt-notebook-images";
create policy "allow all for anon" on "prompt-notebook-images"
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- ============================================================
-- 4. Realtime を有効化（他端末での変更をリアルタイムに受け取る）
--    supabase_realtime publication に未登録の場合のみ追加
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'prompt-notebook'
  ) then
    alter publication supabase_realtime add table "prompt-notebook";
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'prompt-notebook-images'
  ) then
    alter publication supabase_realtime add table "prompt-notebook-images";
  end if;
end $$;
