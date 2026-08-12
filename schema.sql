-- プロンプト帳 (prompt-notebook) の Supabase スキーマ
-- メールマジックリンク認証（Supabase Auth）対応版
--
-- ★ 新規にSupabaseプロジェクトをセットアップする場合はこのファイルをそのまま実行してください。
-- ★ 既にテーブルが存在し、データも入っている既存プロジェクトを移行する場合は、
--    このファイルを直接実行せず、チャットの回答にあるSTEP1〜4を順番に実行してください
--    （user_id が NOT NULL のため、既存データのバックフィルが必要です）。
--
-- 何度実行しても安全（IF NOT EXISTS / CREATE OR REPLACE 系のみ使用）

-- ============================================================
-- 1. 本体テーブル：暗号化されたノート全体（ジャンル・プロンプト一覧など）
--    アプリ内の「書き出し」機能が作るJSONの notebook 部分（salt/iv/ciphertext）と同じ形。
--    ユーザーごとに1行（主キーは user_id）。中身はクライアント側で合言葉から作った鍵で
--    AES-GCM暗号化済みなので、Supabase側には平文は保存されません。
-- ============================================================
create table if not exists "prompt-notebook" (
  id text not null default 'notebook',
  user_id uuid not null references auth.users(id) on delete cascade,
  salt text not null,
  iv text not null,
  ciphertext text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id)
);

-- ============================================================
-- 2. 画像テーブル：添付画像（暗号化生成用ジャンルの添付画像）
--    アプリ内の「書き出し」機能が作るJSONの images 配列の1件分と同じ形。
--    画像バイナリも暗号化した上でbase64文字列にして保存します。
-- ============================================================
create table if not exists "prompt-notebook-images" (
  image_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  iv text not null,
  mime text not null,
  cipher_b64 text not null,
  updated_at timestamptz not null default now()
);

create index if not exists "prompt-notebook-images_user_id_idx"
  on "prompt-notebook-images" (user_id);

-- ============================================================
-- 3. RLS を有効化し、ログイン済み本人（auth.uid()）のデータのみ
--    読み書き削除できるように制限する（anonへの全許可は廃止）
--    ※ 中身は暗号化されていますが、ログインによるアクセス制限を
--      掛け合わせることで二重の保護にしています。
-- ============================================================
alter table "prompt-notebook" enable row level security;
alter table "prompt-notebook-images" enable row level security;

drop policy if exists "allow all for anon" on "prompt-notebook";
drop policy if exists "allow all for anon" on "prompt-notebook-images";

drop policy if exists "select own notebook" on "prompt-notebook";
create policy "select own notebook" on "prompt-notebook"
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "insert own notebook" on "prompt-notebook";
create policy "insert own notebook" on "prompt-notebook"
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "update own notebook" on "prompt-notebook";
create policy "update own notebook" on "prompt-notebook"
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "delete own notebook" on "prompt-notebook";
create policy "delete own notebook" on "prompt-notebook"
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists "select own images" on "prompt-notebook-images";
create policy "select own images" on "prompt-notebook-images"
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "insert own images" on "prompt-notebook-images";
create policy "insert own images" on "prompt-notebook-images"
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "update own images" on "prompt-notebook-images";
create policy "update own images" on "prompt-notebook-images"
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "delete own images" on "prompt-notebook-images";
create policy "delete own images" on "prompt-notebook-images"
  for delete to authenticated using (user_id = auth.uid());

-- ============================================================
-- 4. Realtime を有効化（他端末での変更をリアルタイムに受け取る）
--    supabase_realtime publication に未登録の場合のみ追加
--    ※ RLSが有効なため、Realtimeも自動的に本人の行のみに絞られます。
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
