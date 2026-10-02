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
