# Banco de Horas GCMI — v110

Sistema de gestão de banco de horas (horas extras, compensações, EQP, anexos com trilha de auditoria) com persistência local em IndexedDB e sincronização opcional com **Supabase**.

## Estado atual

| Item | Situação |
|---|---|
| Aplicação (`index.html`) | **v110** — 4.162.182 bytes · MD5 `ee299267c9212c3b0ecb4cf529df1b3d` |
| CSP | `script-src` travado por hash SHA-256 (sem `unsafe-inline`) |
| Migrations | `001` → `006`, em `supabase/migrations/` |
| Testado em Supabase real | **Não** — ver “Ressalvas” |
| Regras consolidadas | 52 regras do Anexo v1.1; as 6 implementáveis nesta versão estão em `005_regras_v110.sql` |

O `index.html` corresponde à **v110**. Para voltar à v109.2 (a mesma aplicação **sem** as 6 regras), basta substituir esse arquivo — o restante do repositório não muda.

## Estrutura

```
banco-horas-gcmi/
├── index.html                       aplicação v110 (arquivo único, offline)
├── public/
│   ├── index.html                   cópia publicável
│   └── supabase-config.example.js   modelo de configuração
├── backend/
│   ├── supabase-config.example.js   idem, para scripts
│   └── check-html.js                valida a sintaxe dos <script> do index.html
├── assets/
│   └── brasao-gcmi-transparente.png
├── database/
│   └── schema.sql                   espelho do 001 (referência)
├── supabase/
│   ├── migrations/001..006*.sql     ordem obrigatória
│   └── README.md                    o que cada migration faz + passo manual do hook
├── docs/
│   └── MIGRACAO_SUPABASE_GITHUB.md  Supabase + GitHub + Pages
├── package.json
├── .env.example                     sem chaves reais
└── .gitignore
```

## Começar

```bash
npm install
npm start            # serve public/ em http://localhost:3000
npm run check        # valida a sintaxe dos scripts embutidos no index.html
```

O app funciona **sem** Supabase: abre direto no navegador e persiste em IndexedDB. Para ligar a sincronização, crie `public/supabase-config.js` a partir do exemplo e aplique as migrations.

## Segurança — o que o `006_harmonizacao.sql` corrige

A comparação entre o pacote de 15/09/2026 (migrations 001–004) e as migrations de regras da v110 (005) mostrou 7 divergências. A mais grave: o `001` cria políticas de RLS **permissivas** (`USING (true) WITH CHECK (true)`), que somam com OR às políticas restritivas do `003` — ou seja, o RBAC por papel **não tinha efeito nenhum**. O `006` remove as permissivas, unifica o caminho do claim (`auth.jwt() ->> 'role'`), elimina a recursão de policy em `user_roles`, devolve a `anexo_historico` o caráter **append-only** e protege `servidores`, `horas_extras` e `compensacoes`.

Detalhamento completo: `supabase/README.md`.

## Passos manuais obrigatórios
1. **Authentication → Hooks → Custom Access Token** → `public.custom_access_token_hook`
2. Promover o primeiro usuário gerencial em `public.user_roles` (a lista de e-mails do `004` está vazia de propósito)

## Ressalvas
- Nenhuma migration foi executada contra um projeto Supabase real. O bug de recursão do `004` foi validado contra Postgres real; o `006` foi verificado por análise sintática e por checagem de que todos os objetos que referencia existem nas migrations anteriores. **Teste em homologação antes de produção.**
- A base de dados embutida no app ainda carrega inconsistências históricas conhecidas (lançamentos marcados para revisão, campos de saldo legados). Elas não impedem o uso, mas devem ser saneadas antes de tratar os relatórios como definitivos.
- `R-33` (recuperação de senha por código de uso único em e-mail) está prevista no Anexo v1.1 mas **não** foi implementada: depende do serviço de e-mail do Supabase estar ativo.
