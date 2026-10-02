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
