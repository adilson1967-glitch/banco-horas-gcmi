# Migrations — Banco de Horas GCMI

Ordem **obrigatória** (o CLI do Supabase aplica em ordem alfabética pelo prefixo numérico):

| # | Arquivo | O que faz |
|---|---------|-----------|
| 1 | `001_schema.sql` | Tabelas base (`banco_horas_snapshot`, `servidores`, `horas_extras`, `compensacoes`) + RLS **permissiva** inicial. |
| 2 | `002_integridade_indices.sql` | Índices e chaves estrangeiras (`mat → servidores`). |
| 3 | `003_rls_por_role.sql` | RLS por papel em `banco_horas_snapshot`; cria `anexos` e `anexo_historico` (tabelas que a aplicação usa de fato desde a v109.1) e mantém `anexo_historico` **append-only**. |
| 4 | `004_seed_admin_role.sql` | `user_roles` (fonte de verdade do papel), hook de Custom Access Token e semeadura do primeiro gerencial. |
| 5 | `005_regras_v110.sql` | Regras de negócio da v110: R-14, R-27, R-28, R-29, R-42, R-43 e a separação de contadores do EQP (R-12). |
| 6 | `006_harmonizacao.sql` | **Reconcilia 001–005** e fecha as falhas de segurança encontradas na comparação. |

## Por que o 006 existe

As migrations 001–004 vieram do pacote de 15/09/2026; a 005 foi escrita depois, para as regras da v110. As duas linhagens divergiram em 7 pontos, todos resolvidos pelo `006`:

1. **Caminho do claim** — 003/004 leem `auth.jwt() ->> 'role'`; a 005 lia `app_metadata.role`. Com o hook do 004 ativo, a função da 005 devolvia `NULL`. Agora o hook grava nos **dois** lugares e a leitura prioriza a raiz.
2. **Colunas de `user_roles`** — 004 criou `atualizado_em`/`atualizado_por`; 005 esperava `granted_by`/`granted_at`/`updated_at`. Como ambas usam `CREATE TABLE IF NOT EXISTS`, a que rodasse primeiro venceria e a outra quebraria. O 006 mantém **as duas famílias** de colunas.
3. **Nome do hook** — canônico passa a ser `public.custom_access_token_hook` (o nome que a documentação do Supabase espera no painel); `fn_custom_access_token_hook` fica como wrapper de compatibilidade.
4. **Recursão de policy** — o 004 documenta que consultar `user_roles` dentro de uma policy da própria tabela causa `infinite recursion detected in policy for relation user_roles`. As policies que a 005 criou faziam exatamente isso. Foram removidas; a checagem passa a usar só o claim.
5. **`anexo_historico` append-only** — o 003 cria de propósito só `SELECT` e `INSERT`, para a trilha ser imutável até contra o gerencial. O 005 aplicava `FOR ALL` nessa tabela, o que reintroduzia `UPDATE`/`DELETE`. Corrigido.
6. **RLS permissiva de 001 anulando o RBAC de 003** (falha crítica) — o 001 cria, para cada tabela, políticas `FOR ALL USING (true) WITH CHECK (true)`. Políticas permissivas somam com **OR**, então as policies restritivas do 003 **não tinham efeito**: qualquer autenticado continuava podendo escrever. O RBAC estava, na prática, desligado. O 006 remove todas as permissivas.
7. **Tabelas normalizadas sem proteção** — `servidores`, `horas_extras` e `compensacoes` ficavam com `USING (true)` para leitura **e** escrita. Agora: leitura para autenticados, escrita só para gerencial.

## Aplicar no Supabase

### Caminho A — SQL Editor (mais simples)
Cole e execute **um arquivo por vez**, na ordem 001 → 006, esperando cada um terminar.

### Caminho B — CLI (`supabase db push`)
```bash
npm i -g supabase
supabase login
supabase link --project-ref SEU-PROJECT-REF
supabase db push
```
As migrations já estão em `supabase/migrations/`, que é o diretório que o CLI lê.

## Passos manuais obrigatórios (não são SQL)

1. **Registrar o hook**: painel do projeto → **Authentication → Hooks → Custom Access Token** → selecionar `public.custom_access_token_hook`. Isso é configuração do projeto, não do schema: nenhuma migration consegue fazer.
2. **Promover o primeiro gerencial**: a lista de e-mails do `004` está **vazia de propósito**. Preencha antes de aplicar, ou rode depois:
   ```sql
   insert into public.user_roles (user_id, role, granted_by, atualizado_por)
   select id, 'gerencial', id, id from auth.users where email = 'admin@seu-dominio';
   ```

## Conferência depois de aplicar
```sql
select * from public.vw_harmonizacao;
```
`anexo_historico` deve listar **somente** `anexo_historico_select_authenticated` e `anexo_historico_insert_gerencial` — se aparecer qualquer `UPDATE`/`DELETE`, a trilha deixou de ser imutável.

## Ressalva honesta
Os arquivos 003, 004 e 006 **não foram executados contra um projeto Supabase real**. O 004 teve o bug de recursão validado contra um Postgres real; o 006 foi validado por análise sintática e por verificação de que todos os objetos que referencia existem nas migrations anteriores. Teste em **homologação** antes de produção.
