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
