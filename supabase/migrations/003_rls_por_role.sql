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
