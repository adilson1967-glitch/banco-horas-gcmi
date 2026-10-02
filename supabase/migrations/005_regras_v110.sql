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
