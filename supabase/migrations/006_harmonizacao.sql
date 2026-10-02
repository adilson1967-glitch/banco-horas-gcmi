-- ============================================================================
-- 006_harmonizacao.sql
-- Gestão Banco de Horas GCMI — v110
--
-- OBJETIVO
--   Harmonizar o pacote de infraestrutura (migrations 001–004, vindas do
--   projeto "banco-horas-gcmi" de 15/09/2026) com as migrations de regras
--   de negócio da v110 (005_regras_v110.sql), eliminando as divergências
--   encontradas na comparação entre os dois conjuntos.
--
--   Esta migration NÃO cria regra de negócio nova. Ela apenas reconcilia
--   o que já existe em 001–005 e fecha lacunas de segurança.
--
-- ── DIVERGÊNCIAS TRATADAS (cada uma tem bloco numerado abaixo) ──────────────
--   [1] CAMINHO DO CLAIM
--       003/004 gravam e leem o papel em auth.jwt() ->> 'role' (raiz).
--       005 grava e lê em app_metadata.role. Incompatíveis: com o hook de
--       004 ativo, a fn_current_role() de 005 devolveria NULL.
--       DECISÃO: caminho único = 'role' na raiz (padrão de 003/004).
--       O hook passa a gravar o papel nos DOIS lugares (raiz + app_metadata)
--       para compatibilidade com código cliente já escrito.
--
--   [2] COLUNAS DE public.user_roles
--       004 cria (user_id, role, atualizado_em, atualizado_por).
--       005 cria (user_id, role, granted_by, granted_at, updated_at).
--       Como ambas usam CREATE TABLE IF NOT EXISTS, a que rodasse primeiro
--       venceria e a outra quebraria. DECISÃO: manter as duas famílias de
--       colunas (adicionadas de forma idempotente) e escrever sempre nas duas.
--
--   [3] NOME DA FUNÇÃO DO HOOK
--       004: public.custom_access_token_hook(jsonb)   <- canônica
--       005: public.fn_custom_access_token_hook(jsonb)
--       DECISÃO: canônica = custom_access_token_hook (é o nome que a
--       documentação do Supabase espera no painel). A de 005 passa a ser
--       um wrapper que delega para a canônica.
--
--   [4] RECURSÃO DE POLICY EM user_roles
--       004 documenta que consultar public.user_roles dentro de uma policy
--       da própria tabela causa "infinite recursion detected in policy for
--       relation user_roles" (confirmado contra Postgres real).
--       As policies p_user_roles_sel / p_user_roles_mod criadas pelo loop
--       de 005 fazem exatamente isso, via fn_is_gerencial().
--       DECISÃO: remover as policies de 005 e manter apenas as de 004,
--       que checam o claim e não reconsultam a tabela.
--
--   [5] anexo_historico — IMUTABILIDADE (append-only)
--       003 cria de propósito SOMENTE SELECT + INSERT, sem UPDATE/DELETE,
--       para preservar a trilha mesmo contra o perfil gerencial.
--       O loop de 005 aplicava "for all" ao gerencial nessa tabela, o que
--       reintroduziria UPDATE/DELETE e quebraria a imutabilidade.
--       DECISÃO: remover a policy "for all" de 005. Trilha volta a ser
--       append-only.
--
--   [6] RLS PERMISSIVA DE 001 ANULANDO O RBAC DE 003 (falha crítica)
--       001 cria, para cada tabela, políticas "authenticated write <t>"
--       do tipo FOR ALL USING (true) WITH CHECK (true).
--       Políticas permissivas são somadas com OR. Portanto, as policies
--       restritivas criadas em 003 para banco_horas_snapshot NÃO tinham
--       efeito: qualquer usuário autenticado continuava podendo
--       INSERT/UPDATE/DELETE. O RBAC estava, na prática, desligado.
--       DECISÃO: remover todas as políticas permissivas de 001 e manter
--       apenas as políticas por papel.
--
--   [7] RLS PERMISSIVA NAS TABELAS NORMALIZADAS
--       servidores, horas_extras e compensacoes ficavam com USING (true)
--       para leitura E escrita em 001, e nem 003 nem 005 as restringiam.
--       DECISÃO: SELECT para autenticados; escrita apenas para gerencial.
--
-- ── PRÉ-REQUISITOS ─────────────────────────────────────────────────────────
--   Rodar DEPOIS de 001, 002, 003, 004 e 005.
--   Idempotente: pode ser reexecutada sem duplicar nem falhar.
--
-- ── PASSO MANUAL (não é SQL) ───────────────────────────────────────────────
--   Authentication → Hooks → Custom Access Token →
--   selecionar public.custom_access_token_hook.
--   Antes disso, preencher os e-mails dos administradores em 004 (a lista
--   está vazia de propósito) ou promover o primeiro gerencial manualmente.
--
-- ── RESSALVA HONESTA ──────────────────────────────────────────────────────
--   Este arquivo NÃO foi executado contra um projeto Supabase real nem
--   contra um Postgres local nesta sessão (não há servidor disponível).
--   A sintaxe foi validada com libpg_query; a semântica das policies deve
--   ser testada em homologação antes da produção.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 0) BOOTSTRAP IDEMPOTENTE
--    No Supabase tudo abaixo já existe e os blocos são no-op.
--    Fora do Supabase (Postgres puro) cria o mínimo para o arquivo rodar,
--    permitindo teste local das funções e policies.
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto;

do $boot$
begin
  if not exists (select 1 from pg_namespace where nspname = 'auth') then
    execute 'create schema auth';
    execute 'create table auth.users (id uuid primary key default gen_random_uuid())';
    execute $f$
      create or replace function auth.uid() returns uuid language sql stable as
      $g$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $g$;
    $f$;
    execute $f$
      create or replace function auth.jwt() returns jsonb language sql stable as
      $g$ select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $g$;
    $f$;
  end if;

  -- auth.jwt() pode não existir em ambientes onde só auth.uid() foi criada
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'auth' and p.proname = 'jwt'
  ) then
    execute $f$
      create or replace function auth.jwt() returns jsonb language sql stable as
      $g$ select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $g$;
    $f$;
  end if;
end
$boot$;

do $boot_roles$
declare r text;
begin
  foreach r in array array['anon','authenticated','service_role','supabase_auth_admin'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin', r);
    end if;
  end loop;
end
$boot_roles$;

-- ----------------------------------------------------------------------------
-- [2] public.user_roles — alinhar as duas famílias de colunas
--     Mantém o que 004 criou e acrescenta o que 005 esperava (e vice-versa).
-- ----------------------------------------------------------------------------
do $user_roles$
begin
  if to_regclass('public.user_roles') is not null then
    execute 'alter table public.user_roles add column if not exists atualizado_em timestamptz not null default now()';
    execute 'alter table public.user_roles add column if not exists atualizado_por uuid';
    execute 'alter table public.user_roles add column if not exists granted_by uuid';
    execute 'alter table public.user_roles add column if not exists granted_at timestamptz not null default now()';
    execute 'alter table public.user_roles add column if not exists updated_at timestamptz not null default now()';
    execute 'alter table public.user_roles enable row level security';
  end if;
end
$user_roles$;

do $comroles$
begin
  if to_regclass('public.user_roles') is not null then
    execute 'comment on table public.user_roles is ''Fonte de verdade do papel (gerencial/auditoria/operacional). O papel é propagado ao JWT pelo hook public.custom_access_token_hook e lido pelas policies via auth.jwt() ->> ''''role''''. Harmonizado por 006.'' ';
  end if;
end
$comroles$;
-- ----------------------------------------------------------------------------
-- [3] HOOK CANÔNICO — grava o papel em 'role' (raiz) e em 'app_metadata.role'
-- ----------------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $fn$
declare
  claims  jsonb;
  papel   text;
  app_meta jsonb;
begin
  select ur.role into papel
  from public.user_roles ur
  where ur.user_id = (event ->> 'user_id')::uuid;

  papel  := coalesce(papel, 'operacional');
  claims := coalesce(event -> 'claims', '{}'::jsonb);

  -- caminho canônico (usado por 003 e pelas policies desta migration)
  claims := jsonb_set(claims, '{role}', to_jsonb(papel), true);

  -- espelho para compatibilidade com código que lê app_metadata.role
  app_meta := coalesce(claims -> 'app_metadata', '{}'::jsonb);
  app_meta := app_meta || jsonb_build_object('role', papel);
  claims   := jsonb_set(claims, '{app_metadata}', app_meta, true);

  return jsonb_set(event, '{claims}', claims, true);
end
$fn$;

-- wrapper de compatibilidade (nome criado por 005)
create or replace function public.fn_custom_access_token_hook(event jsonb)
returns jsonb
language sql
stable
as $fn$
  select public.custom_access_token_hook(event);
$fn$;

comment on function public.custom_access_token_hook(jsonb) is
  'Hook de Custom Access Token. Canônica: é este o nome a registrar em Authentication > Hooks. Grava role na raiz e em app_metadata (006).';
comment on function public.fn_custom_access_token_hook(jsonb) is
  'Wrapper de compatibilidade criado por 005; delega para public.custom_access_token_hook. Não registrar no painel.';

-- ----------------------------------------------------------------------------
-- [1] FUNÇÕES DE PAPEL — caminho único do claim, sem recursão de policy
--     auth.jwt() ->> 'role' (raiz) tem precedência; app_metadata é fallback.
--     NÃO consultam public.user_roles (evita a recursão documentada em 004).
-- ----------------------------------------------------------------------------
create or replace function public.fn_current_role()
returns text
language sql
stable
as $fn$
  select coalesce(
    nullif(auth.jwt() ->> 'role', ''),
    nullif(auth.jwt() -> 'app_metadata' ->> 'role', ''),
    'operacional'
  );
$fn$;

comment on function public.fn_current_role() is
  'Papel do usuário lido exclusivamente do JWT. Sem subconsulta em user_roles — imune à recursão de policy (006, divergência [4]).';

create or replace function public.fn_is_gerencial()
returns boolean
language sql
stable
as $fn$
  select public.fn_current_role() = 'gerencial';
$fn$;

create or replace function public.fn_is_auditoria()
returns boolean
language sql
stable
as $fn$
  select public.fn_current_role() in ('gerencial','auditoria');
$fn$;

-- R-29: perfil de auditoria concedido pela função administrativa.
-- Checa o claim do solicitante (não a tabela) para não recorrer em policy.
create or replace function public.fn_concede_auditoria(p_user uuid, p_admin uuid default null)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_admin uuid;
begin
  if public.fn_current_role() <> 'gerencial' then
    raise exception 'R-29: somente a funcao administrativa (gerencial) pode conceder o perfil de auditoria.';
  end if;

  v_admin := coalesce(p_admin, auth.uid());

  insert into public.user_roles (user_id, role, granted_by, atualizado_por, granted_at, atualizado_em, updated_at)
  values (p_user, 'auditoria', v_admin, v_admin, now(), now(), now())
  on conflict (user_id) do update
    set role          = 'auditoria',
        granted_by    = v_admin,
        atualizado_por = v_admin,
        granted_at    = now(),
        atualizado_em = now(),
        updated_at    = now();

  return 'auditoria';
end
$fn$;

-- ----------------------------------------------------------------------------
-- [6]/[7] RLS — remover políticas permissivas de 001 e aplicar RBAC
-- ----------------------------------------------------------------------------

-- [6] banco_horas_snapshot: 001 criou "authenticated read/write snapshot"
--     com USING (true) / WITH CHECK (true). A de escrita anulava o RBAC de 003.
drop policy if exists "authenticated read snapshot"   on public.banco_horas_snapshot;
drop policy if exists "authenticated write snapshot"  on public.banco_horas_snapshot;

-- [7] tabelas normalizadas: remover as permissivas de 001
drop policy if exists "authenticated read servidores"    on public.servidores;
drop policy if exists "authenticated write servidores"   on public.servidores;
drop policy if exists "authenticated read horas_extras"  on public.horas_extras;
drop policy if exists "authenticated write horas_extras" on public.horas_extras;
drop policy if exists "authenticated read compensacoes"  on public.compensacoes;
drop policy if exists "authenticated write compensacoes" on public.compensacoes;

-- [5] anexo_historico: garantir que não exista policy "for all"
-- [4] user_roles: remover as policies de 005 (recursivas)
--     Também limpa as policies genéricas p_* que 005 criou por loop onde
--     003/004 já têm política equivalente e correta.
do $limpa$
declare t text;
begin
  foreach t in array array['anexos','anexo_historico','banco_horas_snapshot','user_roles'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists p_%s_sel on public.%I', t, t);
      execute format('drop policy if exists p_%s_mod on public.%I', t, t);
    end if;
  end loop;

  -- 005 aplicava "for all" em anexo_historico; remover explicitamente
  if to_regclass('public.anexo_historico') is not null then
    execute 'drop policy if exists p_anexo_historico_mod on public.anexo_historico';
    execute 'drop policy if exists anexo_historico_write_gerencial on public.anexo_historico';
    execute 'drop policy if exists anexo_historico_update_gerencial on public.anexo_historico';
    execute 'drop policy if exists anexo_historico_delete_gerencial on public.anexo_historico';
  end if;

  -- 005 criava estas com nome p_*; 003 já as tem com nome canônico
  if to_regclass('public.anexos') is not null then
    execute 'drop policy if exists p_anexos_sel on public.anexos';
    execute 'drop policy if exists p_anexos_mod on public.anexos';
  end if;

  -- 005 criava estas duas em user_roles (recursivas por subconsulta)
  if to_regclass('public.user_roles') is not null then
    execute 'drop policy if exists p_user_roles_sel on public.user_roles';
    execute 'drop policy if exists p_user_roles_mod on public.user_roles';
  end if;
end
$limpa$;

-- [7] RLS por papel nas tabelas normalizadas (SELECT livre a autenticados,
--     escrita restrita ao gerencial). Substitui o USING (true) de 001.
do $normalizadas$
declare t text;
begin
  foreach t in array array['servidores','horas_extras','compensacoes'] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);

      execute format('drop policy if exists %I on public.%I', t || '_select_authenticated', t);
      execute format(
        'create policy %I on public.%I for select to authenticated using (true)',
        t || '_select_authenticated', t);

      execute format('drop policy if exists %I on public.%I', t || '_insert_gerencial', t);
      execute format(
        'create policy %I on public.%I for insert to authenticated with check (public.fn_is_gerencial())',
        t || '_insert_gerencial', t);

      execute format('drop policy if exists %I on public.%I', t || '_update_gerencial', t);
      execute format(
        'create policy %I on public.%I for update to authenticated using (public.fn_is_gerencial()) with check (public.fn_is_gerencial())',
        t || '_update_gerencial', t);

      execute format('drop policy if exists %I on public.%I', t || '_delete_gerencial', t);
      execute format(
        'create policy %I on public.%I for delete to authenticated using (public.fn_is_gerencial())',
        t || '_delete_gerencial', t);
    end if;
  end loop;
end
$normalizadas$;

-- banco_horas_snapshot: 003 já criou as 4 policies por papel. Se por algum
-- motivo não existirem (aplicação parcial), recria de forma idempotente.
do $snapshot$
begin
  if to_regclass('public.banco_horas_snapshot') is not null then
    execute 'alter table public.banco_horas_snapshot enable row level security';

    execute 'drop policy if exists banco_horas_snapshot_select_authenticated on public.banco_horas_snapshot';
    execute 'create policy banco_horas_snapshot_select_authenticated on public.banco_horas_snapshot for select to authenticated using (true)';

    execute 'drop policy if exists banco_horas_snapshot_insert_gerencial on public.banco_horas_snapshot';
    execute 'create policy banco_horas_snapshot_insert_gerencial on public.banco_horas_snapshot for insert to authenticated with check (public.fn_is_gerencial())';

    execute 'drop policy if exists banco_horas_snapshot_update_gerencial on public.banco_horas_snapshot';
    execute 'create policy banco_horas_snapshot_update_gerencial on public.banco_horas_snapshot for update to authenticated using (public.fn_is_gerencial()) with check (public.fn_is_gerencial())';

    execute 'drop policy if exists banco_horas_snapshot_delete_gerencial on public.banco_horas_snapshot';
    execute 'create policy banco_horas_snapshot_delete_gerencial on public.banco_horas_snapshot for delete to authenticated using (public.fn_is_gerencial())';
  end if;
end
$snapshot$;

-- anexos: 003 já tem select_authenticated + write_gerencial. Garante presença.
do $anexos$
begin
  if to_regclass('public.anexos') is not null then
    execute 'alter table public.anexos enable row level security';

    execute 'drop policy if exists anexos_select_authenticated on public.anexos';
    execute 'create policy anexos_select_authenticated on public.anexos for select to authenticated using (true)';

    execute 'drop policy if exists anexos_write_gerencial on public.anexos';
    execute 'create policy anexos_write_gerencial on public.anexos for all to authenticated using (public.fn_is_gerencial()) with check (public.fn_is_gerencial())';
  end if;
end
$anexos$;

-- [5] anexo_historico: APPEND-ONLY. Somente SELECT + INSERT. Nenhuma policy
--     de UPDATE/DELETE — sem policy, o RLS nega por padrão. Vale até para
--     o perfil gerencial, por decisão de trilha de auditoria (003).
do $historico$
begin
  if to_regclass('public.anexo_historico') is not null then
    execute 'alter table public.anexo_historico enable row level security';

    execute 'drop policy if exists anexo_historico_select_authenticated on public.anexo_historico';
    execute 'create policy anexo_historico_select_authenticated on public.anexo_historico for select to authenticated using (true)';

    execute 'drop policy if exists anexo_historico_insert_gerencial on public.anexo_historico';
    execute 'create policy anexo_historico_insert_gerencial on public.anexo_historico for insert to authenticated with check (public.fn_is_gerencial())';
  end if;
end
$historico$;

-- [4] user_roles: manter as policies de 004 (checam o claim, sem recursão)
--     e acrescentar leitura ampla para o gerencial administrar papéis.
do $roles$
begin
  if to_regclass('public.user_roles') is not null then
    execute 'drop policy if exists user_roles_select_self on public.user_roles';
    execute 'create policy user_roles_select_self on public.user_roles for select to authenticated using (user_id = auth.uid())';

    execute 'drop policy if exists user_roles_select_gerencial on public.user_roles';
    execute 'create policy user_roles_select_gerencial on public.user_roles for select to authenticated using (public.fn_is_gerencial())';

    execute 'drop policy if exists user_roles_write_gerencial on public.user_roles';
    execute 'create policy user_roles_write_gerencial on public.user_roles for all to authenticated using (public.fn_is_gerencial()) with check (public.fn_is_gerencial())';
  end if;
end
$roles$;

-- ----------------------------------------------------------------------------
-- GRANTs do hook (idempotentes)
-- ----------------------------------------------------------------------------
do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    execute 'grant usage on schema public to supabase_auth_admin';
    execute 'grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin';
    execute 'grant execute on function public.fn_custom_access_token_hook(jsonb) to supabase_auth_admin';
    if to_regclass('public.user_roles') is not null then
      execute 'grant select on public.user_roles to supabase_auth_admin';
    end if;
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public';
    execute 'revoke execute on function public.fn_custom_access_token_hook(jsonb) from authenticated, anon, public';
  end if;
end
$grants$;

-- ----------------------------------------------------------------------------
-- VIEW DE CONFERÊNCIA — permite auditar o resultado da harmonização
-- ----------------------------------------------------------------------------
create or replace view public.vw_harmonizacao as
select 'claim'::text as item,
       'caminho unico do papel no JWT'::text as descricao,
       'role (raiz) + app_metadata.role (espelho)'::text as valor
union all
select 'hook', 'funcao a registrar em Authentication > Hooks', 'public.custom_access_token_hook'
union all
select 'hook_wrapper', 'wrapper de compatibilidade (nao registrar)', 'public.fn_custom_access_token_hook'
union all
select 'user_roles', 'policies ativas (sem subconsulta, sem recursao)',
       coalesce((select string_agg(p.polname, ' | ' order by p.polname)
                 from pg_policy p where p.polrelid = to_regclass('public.user_roles')), 'nenhuma')
union all
select 'anexo_historico', 'trilha append-only (deve ter apenas SELECT e INSERT)',
       coalesce((select string_agg(p.polname || ':' || p.polcmd::text, ' | ' order by p.polname)
                 from pg_policy p where p.polrelid = to_regclass('public.anexo_historico')), 'nenhuma')
union all
select 'banco_horas_snapshot', 'policies por papel',
       coalesce((select string_agg(p.polname, ' | ' order by p.polname)
                 from pg_policy p where p.polrelid = to_regclass('public.banco_horas_snapshot')), 'nenhuma')
union all
select 'tabelas_normalizadas', 'servidores / horas_extras / compensacoes',
       coalesce((select string_agg(p.polname, ' | ' order by p.polname)
                 from pg_policy p
                 where p.polrelid in (to_regclass('public.servidores'),
                                      to_regclass('public.horas_extras'),
                                      to_regclass('public.compensacoes'))), 'nenhuma');

comment on view public.vw_harmonizacao is
  'Conferência pós-006: mostra o caminho do claim, os hooks e as policies efetivamente instaladas.';

do $grantview$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant select on public.vw_harmonizacao to authenticated';
  end if;
end
$grantview$;

commit;

-- ============================================================================
-- CONFERÊNCIA SUGERIDA APÓS APLICAR
--   select * from public.vw_harmonizacao;
--   -- anexo_historico deve listar SOMENTE 'anexo_historico_select_authenticated'
--   -- e 'anexo_historico_insert_gerencial' (sem UPDATE/DELETE).
--   -- user_roles deve listar apenas as três policies sem subconsulta.
-- ============================================================================
