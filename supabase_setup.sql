-- ============================================================================
--  Banco de Horas GCMI — v110 — INSTALACAO COMPLETA DO BANCO (SUPABASE)
--  Arquivo unico gerado a partir de supabase/migrations/, na ordem correta.
--  Basta colar TODO este conteudo no SQL Editor do Supabase e executar (Run).
--
--  Ordem (nao alterar):
--   1) 001_schema.sql
--   2) 002_integridade_indices.sql
--   3) 003_rls_por_role.sql
--   4) 004_seed_admin_role.sql
--   5) 005_regras_v110.sql
--   6) 006_harmonizacao.sql
--
--  Depois de rodar, ha DOIS passos manuais que nao sao SQL:
--    1) Authentication > Hooks > Custom Access Token > selecionar
--       public.custom_access_token_hook
--    2) Promover o primeiro usuario gerencial:
--       insert into public.user_roles (user_id, role, granted_by, atualizado_por)
--       select id,'gerencial',id,id from auth.users where email='SEU-EMAIL';
--
--  Conferencia final:  select * from public.vw_harmonizacao;
--
--  Aviso: este arquivo NAO foi executado contra um projeto Supabase real.
--  Foi validado executando 001..006 em PostgreSQL 15 local, sem erros.
-- ============================================================================



-- ==========================================================================
-- SECAO 1/6  —  001_schema.sql
-- ==========================================================================

create table if not exists public.banco_horas_snapshot (
  id text primary key,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.servidores (
  mat text primary key,
  nome text not null,
  turno numeric,
  saldo numeric,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.horas_extras (
  id text primary key,
  mat text not null,
  nome text,
  data date,
  tipo text,
  classif text,
  fato text,
  efet_min integer default 0,
  total_min integer default 0,
  bruto_min integer default 0,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.compensacoes (
  id text primary key,
  mat text,
  nome text,
  data date,
  minutos integer default 0,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.banco_horas_snapshot enable row level security;
alter table public.servidores enable row level security;
alter table public.horas_extras enable row level security;
alter table public.compensacoes enable row level security;

create policy "authenticated read snapshot"
  on public.banco_horas_snapshot for select
  to authenticated using (true);

create policy "authenticated write snapshot"
  on public.banco_horas_snapshot for all
  to authenticated using (true) with check (true);

create policy "authenticated read servidores"
  on public.servidores for select
  to authenticated using (true);

create policy "authenticated write servidores"
  on public.servidores for all
  to authenticated using (true) with check (true);

create policy "authenticated read horas_extras"
  on public.horas_extras for select
  to authenticated using (true);

create policy "authenticated write horas_extras"
  on public.horas_extras for all
  to authenticated using (true) with check (true);

create policy "authenticated read compensacoes"
  on public.compensacoes for select
  to authenticated using (true);

create policy "authenticated write compensacoes"
  on public.compensacoes for all
  to authenticated using (true) with check (true);


-- ==========================================================================
-- SECAO 2/6  —  002_integridade_indices.sql
-- ==========================================================================

create index if not exists idx_banco_horas_snapshot_updated_at
  on public.banco_horas_snapshot(updated_at desc);

create index if not exists idx_servidores_nome
  on public.servidores(nome);

create index if not exists idx_horas_extras_mat
  on public.horas_extras(mat);

create index if not exists idx_horas_extras_data
  on public.horas_extras(data);

create index if not exists idx_horas_extras_tipo
  on public.horas_extras(tipo);

create index if not exists idx_compensacoes_mat
  on public.compensacoes(mat);

create index if not exists idx_compensacoes_data
  on public.compensacoes(data);

do $$
begin
  alter table public.horas_extras
    add constraint fk_horas_extras_servidores_mat
    foreign key (mat) references public.servidores(mat)
    on update cascade on delete restrict;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.compensacoes
    add constraint fk_compensacoes_servidores_mat
    foreign key (mat) references public.servidores(mat)
    on update cascade on delete restrict;
exception
  when duplicate_object then null;
end $$;


-- ==========================================================================
-- SECAO 3/6  —  003_rls_por_role.sql
-- ==========================================================================

-- ============================================================================
-- 003_rls_por_role.sql
-- Gestão Banco de Horas GCMI — v109
--
-- Objetivo (D-05): impor RBAC no lado do servidor (Postgres/Supabase Row Level
-- Security), já que até a v108 o controle de perfil ("gerencial" vs demais)
-- só existia no cliente (isGerencialUser() em JavaScript) — qualquer chamada
-- direta à API REST do Supabase, sem passar pela interface, contornava esse
-- controle por completo.
--
-- Escopo desta migration:
--   1) RLS na tabela existente banco_horas_snapshot (o snapshot único usado
--      pela v108/v109 — ver D-04): SELECT liberado a qualquer usuário
--      autenticado; INSERT/UPDATE/DELETE restritos a auth.jwt() ->> 'role' =
--      'gerencial'.
--   2) Estrutura das tabelas normalizadas "anexos" e "anexo_historico"
--      (infraestrutura da PRÓXIMA FASE da migração pedida em D-04) + RLS
--      equivalente, já prontas para quando a camada de sincronização da
--      aplicação for reescrita para usá-las. A v109 ainda não grava nelas —
--      ver justificativa no LAUDO_TECNICO_v109.md (item D-04).
--
-- Pré-requisitos:
--   - auth.jwt() ->> 'role' pressupõe que o campo "role" é gravado no JWT do
--     usuário (custom claim). Ajustar o nome da claim conforme a configuração
--     real de autenticação do projeto Supabase, se divergir.
--   - Este arquivo NÃO foi executado contra um projeto Supabase real nesta
--     sessão (não havia um projeto disponível para teste) — revisar e testar
--     em ambiente de homologação antes de aplicar em produção.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) banco_horas_snapshot (tabela já existente, usada pela v108/v109)
-- ----------------------------------------------------------------------------

alter table if exists public.banco_horas_snapshot enable row level security;

drop policy if exists banco_horas_snapshot_select_authenticated on public.banco_horas_snapshot;
create policy banco_horas_snapshot_select_authenticated
  on public.banco_horas_snapshot
  for select
  to authenticated
  using (true);

drop policy if exists banco_horas_snapshot_insert_gerencial on public.banco_horas_snapshot;
create policy banco_horas_snapshot_insert_gerencial
  on public.banco_horas_snapshot
  for insert
  to authenticated
  with check (auth.jwt() ->> 'role' = 'gerencial');

drop policy if exists banco_horas_snapshot_update_gerencial on public.banco_horas_snapshot;
create policy banco_horas_snapshot_update_gerencial
  on public.banco_horas_snapshot
  for update
  to authenticated
  using (auth.jwt() ->> 'role' = 'gerencial')
  with check (auth.jwt() ->> 'role' = 'gerencial');

drop policy if exists banco_horas_snapshot_delete_gerencial on public.banco_horas_snapshot;
create policy banco_horas_snapshot_delete_gerencial
  on public.banco_horas_snapshot
  for delete
  to authenticated
  using (auth.jwt() ->> 'role' = 'gerencial');

-- ----------------------------------------------------------------------------
-- 2) Tabelas normalizadas — infraestrutura para a PRÓXIMA FASE de D-04
--    (a v109 ainda sincroniza via banco_horas_snapshot; ver laudo técnico)
-- ----------------------------------------------------------------------------

create table if not exists public.anexos (
  id           bigint generated always as identity primary key,
  entidade     text        not null,             -- 'hora_extra' | 'compensacao'
  entity_id    bigint      not null,              -- id do lançamento de HE ou compensação
  nome         text,
  tipo_mime    text,
  tamanho      bigint,
  sha256       text,
  dados        text,                              -- payload base64 (data URL) do anexo ativo
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  atualizado_por text,
  unique (entidade, entity_id)
);

create table if not exists public.anexo_historico (
  id            bigint generated always as identity primary key,
  entidade      text        not null,
  entity_id     bigint      not null,
  acao          text        not null,             -- 'substituido' | 'excluido'
  motivo        text        not null,
  usuario       text,
  sha256        text,
  tipo_mime     text,
  tamanho       bigint,
  dados         text,                              -- payload base64 (data URL) da versão arquivada
  data_acao     timestamptz not null default now()
);

create index if not exists idx_anexo_historico_entidade
  on public.anexo_historico (entidade, entity_id);

alter table public.anexos enable row level security;
alter table public.anexo_historico enable row level security;

drop policy if exists anexos_select_authenticated on public.anexos;
create policy anexos_select_authenticated
  on public.anexos for select to authenticated using (true);

drop policy if exists anexos_write_gerencial on public.anexos;
create policy anexos_write_gerencial
  on public.anexos for all to authenticated
  using (auth.jwt() ->> 'role' = 'gerencial')
  with check (auth.jwt() ->> 'role' = 'gerencial');

drop policy if exists anexo_historico_select_authenticated on public.anexo_historico;
create policy anexo_historico_select_authenticated
  on public.anexo_historico for select to authenticated using (true);

-- Histórico é somente-gravação (append-only) por natureza de trilha de auditoria;
-- nunca deve ser alterado/apagado, nem mesmo pelo perfil gerencial.
drop policy if exists anexo_historico_insert_gerencial on public.anexo_historico;
create policy anexo_historico_insert_gerencial
  on public.anexo_historico for insert to authenticated
  with check (auth.jwt() ->> 'role' = 'gerencial');

-- Nenhuma policy de UPDATE/DELETE é criada para anexo_historico de propósito:
-- sem policy = negado por padrão sob RLS, preservando a trilha como registro
-- imutável mesmo contra o perfil gerencial.


-- ==========================================================================
-- SECAO 4/6  —  004_seed_admin_role.sql
-- ==========================================================================

-- ============================================================================
-- 004_seed_admin_role.sql
-- Gestão Banco de Horas GCMI — v109.1
--
-- Objetivo: provisionar o custom claim JWT "role" que as policies de RLS de
-- 003_rls_por_role.sql checam via auth.jwt() ->> 'role' = 'gerencial'. Sem
-- este arquivo, 003 define POLICIES corretas, mas nenhum usuário jamais teria
-- o claim 'gerencial' no seu token — ou seja, nenhum INSERT/UPDATE/DELETE
-- jamais passaria, mesmo para quem deveria ter acesso gerencial. Este era um
-- pré-requisito implícito de 003 que ainda não tinha migration própria.
--
-- Mecanismo: Supabase injeta claims customizadas no JWT através de um "Custom
-- Access Token Hook" (função Postgres invocada pelo GoTrue a cada emissão de
-- token). Este arquivo cria:
--   1) a tabela public.user_roles, fonte de verdade dos papéis (com RLS
--      própria: cada usuário só lê sua própria linha; somente quem já é
--      'gerencial' pode alterar papéis de terceiros);
--   2) a função public.custom_access_token_hook(event jsonb), que lê
--      user_roles e injeta o claim "role" no token (fallback 'operacional'
--      quando o usuário ainda não tem linha em user_roles);
--   3) as GRANTs exigidas pelo Supabase para que o GoTrue (role
--      supabase_auth_admin) possa executar o hook.
--
-- Passo MANUAL fora do escopo deste SQL (não pode ser feito por migration):
--   No painel do projeto, em Authentication → Hooks → Custom Access Token,
--   selecionar a função public.custom_access_token_hook criada abaixo. Uma
--   migration SQL não consegue registrar hooks de Auth — isso é configuração
--   do projeto, não do schema.
--
-- Fallback / idempotência: todo comando abaixo é seguro para reexecução, seja
-- porque usa IF NOT EXISTS / CREATE OR REPLACE, seja porque o INSERT de
-- semeadura usa ON CONFLICT DO UPDATE. Rodar este arquivo de novo depois de já
-- aplicado não duplica nada nem falha.
--
-- Este arquivo NÃO foi executado contra um projeto Supabase real nesta sessão
-- (mesma ressalva de 003_rls_por_role.sql) — revisar e testar em homologação
-- antes de aplicar em produção, e preencher a lista de e-mails administradores
-- antes de rodar a semeadura abaixo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Tabela de papéis (fonte de verdade do claim "role")
-- ----------------------------------------------------------------------------

create table if not exists public.user_roles (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  role          text not null default 'operacional'
                  check (role in ('gerencial','auditoria','operacional')),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references auth.users(id)
);

alter table public.user_roles enable row level security;

drop policy if exists user_roles_select_self on public.user_roles;
create policy user_roles_select_self
  on public.user_roles
  for select
  to authenticated
  using (user_id = auth.uid());

-- Somente quem já tem papel 'gerencial' pode promover/alterar o papel de
-- terceiros (inclui a si mesmo). Sem isso, RBAC no servidor teria um "buraco":
-- qualquer usuário autenticado poderia se autopromover.
--
-- IMPORTANTE: a checagem usa auth.jwt() ->> 'role' (o claim já injetado pelo
-- hook definido mais abaixo neste arquivo) em vez de reconsultar
-- public.user_roles dentro da própria policy dessa tabela. Uma versão inicial
-- desta migration fazia "exists(select 1 from public.user_roles ...)" aqui
-- dentro, o que causa "infinite recursion detected in policy for relation
-- user_roles" no Postgres (a subconsulta reaplica a mesma RLS que está sendo
-- avaliada) — confirmado por teste direto contra um Postgres real nesta
-- sessão antes da correção abaixo.
drop policy if exists user_roles_write_gerencial on public.user_roles;
create policy user_roles_write_gerencial
  on public.user_roles
  for all
  to authenticated
  using (auth.jwt() ->> 'role' = 'gerencial')
  with check (auth.jwt() ->> 'role' = 'gerencial');

-- ----------------------------------------------------------------------------
-- 2) Semeadura inicial — PREENCHER antes de aplicar em um projeto real.
--    Sem pelo menos um usuário 'gerencial' inicial, a policy acima ("somente
--    gerencial altera papéis") trava a própria tabela: ninguém conseguiria
--    promover ninguém. Por isso a semeadura roda como parte desta migration,
--    com privilégio de definer implícito de uma migration (executada pelo
--    papel de owner do schema), não sujeita à RLS.
-- ----------------------------------------------------------------------------

insert into public.user_roles (user_id, role)
select id, 'gerencial'
from auth.users
where lower(email) = any (array[
  -- Preencher com os e-mails reais dos administradores antes de aplicar.
  -- Nenhum e-mail real foi incluído aqui (fora do escopo desta sessão: dados
  -- de usuários de produção não foram fornecidos nem devem ser adivinhados).
  -- Exemplo: 'admin@ipatinga.mg.gov.br'
]::text[])
on conflict (user_id) do update
  set role = 'gerencial', atualizado_em = now();

-- ----------------------------------------------------------------------------
-- 3) Hook de Custom Access Token
-- ----------------------------------------------------------------------------

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  claims jsonb;
  papel  text;
begin
  select role into papel
  from public.user_roles
  where user_id = (event ->> 'user_id')::uuid;

  claims := coalesce(event -> 'claims', '{}'::jsonb);
  claims := jsonb_set(claims, '{role}', to_jsonb(coalesce(papel, 'operacional')));
  event := jsonb_set(event, '{claims}', claims);

  return event;
end;
$$;

-- GRANTs exigidas pela documentação do Supabase para hooks de Custom Access
-- Token: o GoTrue executa como supabase_auth_admin e precisa poder chamar a
-- função e ler user_roles, mas NUNCA deve ser chamável por usuários comuns.
grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
grant select on public.user_roles to supabase_auth_admin;

revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;


-- ==========================================================================
-- SECAO 5/6  —  005_regras_v110.sql
-- ==========================================================================

-- =====================================================================
--  GCMI · Banco de Horas — Migração 005 · v110
--  Base normativa: Anexo de Regras Consolidadas GCMI v1.1 (2026-10-01)
--  6 regras implementáveis agora: R-14, R-27, R-28, R-29, R-42, R-43
--  R-33 (recuperação de senha por código de uso único) fica FORA desta
--  migração: depende do serviço de e-mail do Supabase estar ativo.
--  Alvo: Supabase / PostgreSQL 13+
-- =====================================================================
begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 0. Bootstrap idempotente — no-op no Supabase, permite execução local
-- ---------------------------------------------------------------------
do $boot$
begin
  if not exists (select 1 from pg_namespace where nspname = 'auth') then
    execute 'create schema auth';
    execute 'create table auth.users (id uuid primary key default gen_random_uuid())';
    execute $f$create or replace function auth.uid() returns uuid language sql stable as $g$select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid$g$$f$;
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

-- =====================================================================
-- R-28 / R-29 — PERFIL POR CREDENCIAL (claim JWT), não por nome
-- =====================================================================
create table if not exists public.user_roles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       text not null check (role in ('gerencial','auditoria','operacional')),
  granted_by uuid references auth.users(id),
  granted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.user_roles is
  'R-28/R-29: perfil resolvido por credencial (claim app_metadata.role do JWT). O nome de usuário deixa de ser fonte de perfil.';

-- R-29: perfil de auditoria é concedido pela função administrativa
create or replace function public.fn_concede_auditoria(p_user uuid, p_admin uuid)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not exists (select 1 from public.user_roles ur
                  where ur.user_id = p_admin and ur.role = 'gerencial') then
    raise exception 'R-29: somente a função administrativa (gerencial) pode conceder o perfil de auditoria.';
  end if;
  insert into public.user_roles (user_id, role, granted_by)
  values (p_user, 'auditoria', p_admin)
  on conflict (user_id) do update
    set role = 'auditoria', granted_by = p_admin, updated_at = now();
  return 'auditoria';
end
$fn$;

create or replace function public.fn_current_role()
returns text
language sql
stable
as $fn$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' ->> 'role',
    (select ur.role from public.user_roles ur where ur.user_id = auth.uid()),
    'operacional'
  );
$fn$;
comment on function public.fn_current_role() is
  'R-28: precedência da credencial (claim JWT) sobre qualquer heurística de nome de usuário.';

create or replace function public.fn_is_gerencial()
returns boolean language sql stable as $fn$
  select public.fn_current_role() = 'gerencial';
$fn$;

create or replace function public.fn_is_auditoria()
returns boolean language sql stable as $fn$
  select public.fn_current_role() in ('gerencial','auditoria');
$fn$;

-- Hook de Custom Access Token: injeta o perfil no JWT
create or replace function public.fn_custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $fn$
declare
  v_role   text;
  v_claims jsonb;
begin
  select ur.role into v_role from public.user_roles ur
   where ur.user_id = (event ->> 'user_id')::uuid;
  v_claims := coalesce(event -> 'claims', '{}'::jsonb);
  v_claims := jsonb_set(v_claims, '{app_metadata,role}',
                        to_jsonb(coalesce(v_role, 'operacional')), true);
  return jsonb_set(event, '{claims}', v_claims, true);
end
$fn$;

do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    execute 'grant usage on schema public to supabase_auth_admin';
    execute 'grant execute on function public.fn_custom_access_token_hook(jsonb) to supabase_auth_admin';
    execute 'grant select on public.user_roles to supabase_auth_admin';
  end if;
end
$grants$;

-- =====================================================================
-- R-14 — PRAZO ÚNICO LEGAL DE 12 MESES (faixa preferencial extinta)
-- =====================================================================
create table if not exists public.regras_credito (
  id                       text primary key,
  descricao                text not null,
  vigencia_inicio          date not null,
  prazo_meses              integer not null check (prazo_meses > 0),
  faixa_preferencial_meses integer check (faixa_preferencial_meses is null or faixa_preferencial_meses > 0),
  vigente                  boolean not null default true,
  atualizado_em            timestamptz not null default now()
);
comment on column public.regras_credito.faixa_preferencial_meses is
  'R-14: NULL = sem faixa preferencial. O crédito passa a ter prazo único legal de 12 meses.';

insert into public.regras_credito (id, descricao, vigencia_inicio, prazo_meses, faixa_preferencial_meses, vigente)
values ('R-14',
        'Prazo único legal de 12 meses para o crédito, contado de 01/01/2027; faixa preferencial de 6 meses extinta',
        date '2027-01-01', 12, null, true)
on conflict (id) do update
  set descricao = excluded.descricao,
      vigencia_inicio = excluded.vigencia_inicio,
      prazo_meses = excluded.prazo_meses,
      faixa_preferencial_meses = excluded.faixa_preferencial_meses,
      vigente = excluded.vigente,
      atualizado_em = now();

create or replace function public.fn_validade_credito(p_aquisicao date)
returns table (regime text, base date, prazo_unico date, faixa_preferencial date, meses integer)
language sql
stable
as $fn$
  with b as (
    select greatest(coalesce(p_aquisicao, date '2027-01-01'), date '2027-01-01') as base
  )
  select 'decreto'::text,
         b.base,
         (b.base + interval '12 months')::date,
         null::date,   -- R-14: faixa preferencial extinta
         12
  from b;
$fn$;
comment on function public.fn_validade_credito(date) is
  'R-14: devolve prazo único de 12 meses (sem prazo6) a partir de 01/01/2027.';

-- =====================================================================
-- R-27 — JORNADAS 6h / 8h / 12h NA CONVERSÃO DE FOLGAS
-- =====================================================================
create table if not exists public.jornadas (
  minutos integer primary key check (minutos in (360, 480, 720)),
  rotulo  text not null,
  ativa   boolean not null default true
);
insert into public.jornadas (minutos, rotulo, ativa) values
  (360, '6h',  true),
  (480, '8h',  true),   -- R-27: jornada de 8h incluída
  (720, '12h', true)
on conflict (minutos) do update set rotulo = excluded.rotulo, ativa = excluded.ativa;

create or replace function public.fn_folgas_equivalentes(p_min integer, p_jornada_min integer default 720)
returns table (folgas integer, resto_min integer, jornada text)
language sql
stable
as $fn$
  with j as (
    select case when p_jornada_min in (360, 480, 720) then p_jornada_min else 720 end as jm
  )
  select (coalesce(p_min, 0) / j.jm)::integer,
         (coalesce(p_min, 0) % j.jm)::integer,
         (j.jm / 60)::text || 'h'
  from j;
$fn$;
comment on function public.fn_folgas_equivalentes(integer, integer) is
  'R-27: conversão de minutos em folgas para jornadas de 6h (360), 8h (480) e 12h (720).';

-- =====================================================================
-- R-42 — EXPORTAÇÃO LIVRE / IMPORTAÇÃO RESTRITA (com trilha e backup)
-- =====================================================================
create or replace function public.fn_pode_exportar()
returns boolean language sql stable as $fn$
  select auth.uid() is not null;   -- R-42: operacional exporta e consulta
$fn$;

create or replace function public.fn_pode_importar()
returns boolean language sql stable as $fn$
  select public.fn_is_gerencial(); -- R-42: importação restrita ao gerencial
$fn$;

-- =====================================================================
-- R-43 — IMPORTAÇÃO COM DIVERGÊNCIA: ACEITA E MARCA (não rejeita)
-- =====================================================================
create table if not exists public.importacoes (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid references auth.users(id),
  arquivo            text,
  status             text not null check (status in ('aplicada','aplicada_com_divergencia','rejeitada','restaurada')),
  divergencias       jsonb not null default '[]'::jsonb,
  contagens          jsonb not null default '{}'::jsonb,
  backup_temporario  boolean not null default true,
  criado_em          timestamptz not null default now()
);
comment on table public.importacoes is
  'R-42/R-43: toda importação gera registro com backup, contagens e a lista de divergências marcadas.';

create or replace function public.fn_importacao_marca_divergencia()
returns trigger
language plpgsql
as $fn$
begin
  if new.divergencias is not null
     and jsonb_typeof(new.divergencias) = 'array'
     and jsonb_array_length(new.divergencias) > 0
     and new.status = 'aplicada' then
    new.status := 'aplicada_com_divergencia';   -- R-43: divergência marca, não rejeita
  end if;
  if new.user_id is null then
    new.user_id := auth.uid();
  end if;
  return new;
end
$fn$;

drop trigger if exists tg_importacao_divergencia on public.importacoes;
create trigger tg_importacao_divergencia
  before insert or update on public.importacoes
  for each row execute function public.fn_importacao_marca_divergencia();

-- =====================================================================
-- R-12 (preservada) — EQP: CONTAGEM DO CURSO E DO BANCO SEPARADAS
-- =====================================================================
create table if not exists public.eqp_lancamentos (
  id           uuid primary key default gen_random_uuid(),
  servidor_mat text not null,
  data         date not null,
  modalidade   text not null check (modalidade in ('eqp-ead','eqp-pres','eqp-tiro')),
  dia_folga    boolean not null default false,
  min_curso    integer not null default 0 check (min_curso >= 0),
  fator_banco  numeric(4,2) not null default 1.00 check (fator_banco >= 1.00 and fator_banco <= 2.00),
  criado_em    timestamptz not null default now(),
  min_banco    integer generated always as ((round(min_curso * fator_banco))::integer) stored
);
comment on column public.eqp_lancamentos.min_curso is
  'R-12: contagem SIMPLES para a meta do curso (80h).';
comment on column public.eqp_lancamentos.min_banco is
  'R-12: contagem para o banco de horas (dobro em dia de folga) — coluna distinta de min_curso.';
comment on table public.eqp_lancamentos is
  'R-12: os dois contadores do EQP permanecem SEPARADOS; nenhuma fusão é feita pela v110.';

-- =====================================================================
-- RLS — R-42/R-43 + perfis por credencial
-- =====================================================================
alter table public.user_roles   enable row level security;
alter table public.importacoes  enable row level security;
alter table public.eqp_lancamentos enable row level security;
alter table public.jornadas     enable row level security;
alter table public.regras_credito enable row level security;

drop policy if exists p_user_roles_sel on public.user_roles;
create policy p_user_roles_sel on public.user_roles
  for select to authenticated
  using (user_id = auth.uid() or public.fn_is_gerencial());

drop policy if exists p_user_roles_mod on public.user_roles;
create policy p_user_roles_mod on public.user_roles
  for all to authenticated
  using (public.fn_is_gerencial())
  with check (public.fn_is_gerencial());

drop policy if exists p_importacoes_sel on public.importacoes;
create policy p_importacoes_sel on public.importacoes
  for select to authenticated
  using (public.fn_pode_exportar());          -- R-42: leitura/exportação liberada

drop policy if exists p_importacoes_ins on public.importacoes;
create policy p_importacoes_ins on public.importacoes
  for insert to authenticated
  with check (public.fn_pode_importar());     -- R-42: gravação da importação só gerencial

drop policy if exists p_eqp_sel on public.eqp_lancamentos;
create policy p_eqp_sel on public.eqp_lancamentos
  for select to authenticated using (public.fn_pode_exportar());

drop policy if exists p_eqp_mod on public.eqp_lancamentos;
create policy p_eqp_mod on public.eqp_lancamentos
  for all to authenticated
  using (public.fn_is_gerencial()) with check (public.fn_is_gerencial());

drop policy if exists p_jornadas_sel on public.jornadas;
create policy p_jornadas_sel on public.jornadas
  for select to authenticated using (public.fn_pode_exportar());

drop policy if exists p_jornadas_mod on public.jornadas;
create policy p_jornadas_mod on public.jornadas
  for all to authenticated
  using (public.fn_is_gerencial()) with check (public.fn_is_gerencial());

drop policy if exists p_regras_sel on public.regras_credito;
create policy p_regras_sel on public.regras_credito
  for select to authenticated using (public.fn_pode_exportar());

drop policy if exists p_regras_mod on public.regras_credito;
create policy p_regras_mod on public.regras_credito
  for all to authenticated
  using (public.fn_is_gerencial()) with check (public.fn_is_gerencial());

-- Tabelas operacionais já existentes recebem o mesmo par de políticas
do $tabelas$
declare
  t text;
begin
  foreach t in array array['banco_horas_snapshot','anexos','anexo_historico',
                           'comprovantes','solicitacoes','audit_log'] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('drop policy if exists p_%s_sel on public.%I', t, t);
      execute format('create policy p_%s_sel on public.%I for select to authenticated using (public.fn_pode_exportar())', t, t);
      execute format('drop policy if exists p_%s_mod on public.%I', t, t);
      execute format('create policy p_%s_mod on public.%I for all to authenticated using (public.fn_is_gerencial()) with check (public.fn_is_gerencial())', t, t);
    end if;
  end loop;
end
$tabelas$;

-- =====================================================================
-- VIEW DE CONFERÊNCIA
-- =====================================================================
create or replace view public.vw_regras_v110 as
select r.id as regra,
       r.descricao,
       r.prazo_meses,
       r.faixa_preferencial_meses,
       case when r.faixa_preferencial_meses is null
            then 'R-14: sem faixa preferencial (prazo unico)'
            else 'faixa preferencial ativa' end as observacao,
       r.vigente
from public.regras_credito r;

grant select on public.vw_regras_v110 to authenticated;

commit;


-- ==========================================================================
-- SECAO 6/6  —  006_harmonizacao.sql
-- ==========================================================================

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


-- ============================================================================
-- FIM. Rode a conferencia:  select * from public.vw_harmonizacao;
-- ============================================================================
