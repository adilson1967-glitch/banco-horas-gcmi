# Implantação — Banco de Horas GCMI v110

Guia passo a passo, na ordem em que deve ser executado. Nada aqui exige conhecimento de programação além de copiar e colar.

**Tempo estimado:** 25 a 40 minutos.

---

## Parte 0 — O que você vai precisar

- Uma conta no **GitHub** (gratuita).
- Uma conta no **Supabase** (gratuita).
- O arquivo `banco-horas-gcmi_v110_supabase.zip`, que contém tudo.
- Opcional: **Node.js 18+** instalado, apenas se quiser rodar o app localmente antes de publicar.

**Aviso sobre o login:** a autenticação foi deliberadamente deixada para depois. Enquanto ela não estiver pronta, o sistema funciona **100% local** (IndexedDB no navegador) e **não** conversa com o Supabase. Isso é intencional e seguro — veja a Parte 3.

---

## Parte 1 — GitHub (guardar e versionar o projeto)

### 1.1 Descompactar

Extraia o zip. Você terá uma pasta `banco-horas-gcmi/` com 21 arquivos.

### 1.2 Criar o repositório

1. Entre em https://github.com/new
2. **Repository name:** `banco-horas-gcmi`
3. **Visibility:** `Private` (recomendado — o sistema é interno)
4. **Não** marque "Add a README file", "Add .gitignore" nem "Choose a license": você já tem esses arquivos.
5. Clique em **Create repository**.

### 1.3 Enviar os arquivos

**Opção A — pela interface web (sem instalar nada):**

1. Na página do repositório recém-criado, clique em **uploading an existing file**.
2. Arraste **todo o conteúdo** de dentro da pasta `banco-horas-gcmi/` (não a pasta em si — os arquivos e subpastas).
3. Em "Commit changes", escreva `Banco de Horas GCMI v110 — migrations 001..006`.
4. Clique em **Commit changes**.

> A interface web não preserva pastas vazias, mas todas as suas pastas têm arquivos. Se alguma subpasta não subir, crie-a manualmente com **Add file → Create new file** e digite o caminho (ex.: `supabase/migrations/README.md`).

**Opção B — pelo Git (recomendado, preserva tudo):**

Abra o terminal na pasta que contém `banco-horas-gcmi/` e rode:

```bash
cd banco-horas-gcmi
git init
git add .
git commit -m "Banco de Horas GCMI v110 — migrations 001..006"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/banco-horas-gcmi.git
git push -u origin main
```

Troque `SEU-USUARIO` pelo seu usuário do GitHub. Se pedir senha, use um **Personal Access Token** (GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token, escopo `repo`).

### 1.4 Confirmar que nada sensível subiu

No repositório, confirme que **não existem** estes arquivos (o `.gitignore` os bloqueia de propósito):

- `public/supabase-config.js`
- `backend/supabase-config.js`
- `.env`

Se algum aparecer, remova: **Settings → não**, o correto é abrir o arquivo → **Delete file** → commit. Depois **revogue a chave no Supabase** (Project Settings → API → Rotate).

---

## Parte 2 — Supabase (criar o banco)

### 2.1 Criar o projeto

1. Entre em https://supabase.com/dashboard e clique em **New project**.
2. **Name:** `banco-horas-gcmi`
3. **Database Password:** clique em **Generate a password** e **guarde** esse valor em local seguro. Ele não será usado pelo app, mas é a senha do banco.
4. **Region:** escolha a mais próxima do Brasil (ex.: `South America (São Paulo)`).
5. **Pricing Plan:** Free.
6. Clique em **Create new project** e aguarde 1 a 3 minutos (a tela mostra "Setting up project...").

### 2.2 Rodar o SQL

1. No menu lateral esquerdo, clique em **SQL Editor**.
2. Clique em **New query**.
3. Abra o arquivo **`supabase_setup.sql`** (está na raiz do projeto), selecione **todo** o conteúdo (Ctrl+A), copie (Ctrl+C).
4. Cole no editor (Ctrl+V).
5. Clique em **Run** (ou Ctrl+Enter).
6. Aguarde. O resultado esperado é **"Success. No rows returned"**.

> Se preferir rodar separadamente, use os arquivos de `supabase/migrations/` **um por vez**, nesta ordem exata: `001_schema.sql` → `002_integridade_indices.sql` → `003_rls_por_role.sql` → `004_seed_admin_role.sql` → `005_regras_v110.sql` → `006_harmonizacao.sql`. Cada um deve terminar com "Success" antes de passar ao próximo.

### 2.3 Conferir se o banco está correto

No **SQL Editor**, rode:

```sql
select * from public.vw_harmonizacao;
```

Você deve ver 7 linhas. As duas mais importantes:

| item | valor esperado |
|---|---|
| `anexo_historico` | apenas `anexo_historico_insert_gerencial:a` e `anexo_historico_select_authenticated:r` |
| `hook` | `public.custom_access_token_hook` |

Se em `anexo_historico` aparecer qualquer `UPDATE` ou `DELETE`, **pare** e me avise: a trilha de auditoria perdeu a imutabilidade.

### 2.4 Pegar as chaves de API

1. Menu lateral → **Project Settings** (engrenagem) → **API**.
2. Anote dois valores:
   - **Project URL** — algo como `https://abcdefghijklmnop.supabase.co`
   - **anon / public** (em "Project API keys") — uma string longa começando com `eyJ...`

> **NUNCA** copie a chave **`service_role`**. Ela ignora todas as regras de segurança. A chave `anon` é pública por projeto e é a única que pode ir para o navegador.

### 2.5 Passos manuais que nenhuma migration faz

Estes dois ficam pendentes **até você finalizar o login** (Parte 6). Se quiser adiantá-los agora:

**a) Registrar o hook de token:** menu lateral → **Authentication** → **Hooks** → **Custom Access Token** → selecionar `public.custom_access_token_hook` → **Save**.

**b) Promover o primeiro gerencial:** no SQL Editor, com o e-mail do administrador:

```sql
insert into public.user_roles (user_id, role, granted_by, atualizado_por)
select id, 'gerencial', id, id from auth.users where email = 'admin@seu-dominio.com';
```

> A lista de e-mails do `004_seed_admin_role.sql` está **vazia de propósito** — nenhum dado de produção foi presumido.

---

## Parte 3 — Ligar o app ao Supabase

**Nesta etapa, deixe desligado.** Como o login ainda não está pronto, o app deve rodar em modo local.

O `index.html` já vem configurado assim (valores padrão embutidos no próprio arquivo):

```js
window.SUPABASE_CONFIG = {
  url: '', anonKey: '',
  table: 'banco_horas_snapshot',
  mode: 'disabled',      // <- sem conversa com o Supabase
  authMode: 'local'      // <- sessão local protegida
};
```

Ou seja: **não crie o arquivo de configuração agora**. O app abre, funciona e grava no navegador.

### Por que não ligar antes do login

Todas as políticas de RLS do banco são destinadas ao papel `authenticated`. Sem login, o app se conectaria como `anon` e **toda** gravação seria negada pelo próprio banco — o que é o comportamento correto. Não desative o RLS para "fazer funcionar": isso abriria o banco para qualquer pessoa com a chave `anon`.

### Como ligar depois (quando o login estiver pronto)

Crie o arquivo `public/supabase-config.js` a partir do modelo:

```bash
cp public/supabase-config.example.js public/supabase-config.js
```

E preencha:

```js
window.SUPABASE_CONFIG = {
  url: 'https://SEU-PROJETO.supabase.co',   // Project URL (2.4)
  anonKey: 'SUA-ANON-KEY',                  // chave anon (2.4)
  table: 'banco_horas_snapshot',
  mode: 'supabase',
  authMode: 'supabase',
  sync: 'auto'
};
```

Esse arquivo está no `.gitignore` e **não** deve ser comitado.

---

## Parte 4 — Publicar o sistema

### Opção A — GitHub Pages (gratuito, mais simples)

1. No repositório: **Settings** → **Pages**.
2. **Source:** `Deploy from a branch`.
3. **Branch:** `main` · **pasta:** `/ (root)` → **Save**.
4. Aguarde 1 a 2 minutos. A URL aparece no topo: `https://SEU-USUARIO.github.io/banco-horas-gcmi/`.

Como `public/supabase-config.js` não está no repositório, o Pages sobe em **modo local** — exatamente o que se quer nesta fase.

### Opção B — Vercel (se quiser domínio próprio)

1. Entre em https://vercel.com e faça login com o GitHub.
2. **Add New → Project** → importe o repositório `banco-horas-gcmi`.
3. **Framework Preset:** `Other`. **Root Directory:** deixe em branco.
4. **Build Command** e **Output Directory:** deixe em branco (é site estático).
5. **Deploy**.

### Opção C — só local (sem publicar)

```bash
npm install
npm start
```

Abre em `http://localhost:3000`.

---

## Parte 5 — Testes de fumaça (fazer antes de liberar para uso)

Rode nesta ordem e só considere pronto se todos passarem.

| # | Teste | Como fazer | Resultado esperado |
|---|---|---|---|
| 1 | O app abre | Abrir a URL publicada | Tela de login/perfil aparece, sem tela branca |
| 2 | Console limpo | F12 → aba **Console** | **Nenhum** erro de `Content-Security-Policy` |
| 3 | Versão correta | F12 → Console → digitar `APP_VERSION` | `'v110'` |
| 4 | Dados carregados | Ver a lista de servidores | Servidores listados, sem erro |
| 5 | Gravar hora extra | Lançar uma HE de teste e salvar | Registro aparece na lista e sobrevive ao F5 |
| 6 | Anexo | Anexar um PDF pequeno numa HE | Anexo aceito; `.exe` ou arquivo >10 MB **recusado** |
| 7 | Auditoria | Abrir a trilha de auditoria | Evento registrado com data e usuário |
| 8 | Exportar | Exportar backup (JSON/CSV) | Arquivo baixado e abre corretamente |
| 9 | Banco vivo | No Supabase: `select count(*) from public.banco_horas_snapshot;` | Sem erro (pode retornar 0) |
| 10 | RLS ativo | No Supabase, SQL Editor: `select * from public.anexo_historico;` | Retorna sem erro |

> O teste 6 é o mais importante para a operação: confirma que a whitelist de tipos e o limite de 10 MB estão ativos.

---

## Parte 6 — O que fica para depois (login)

Quando for finalizar a autenticação, estes são os pontos — nenhum deles bloqueia a subida:

1. **Registrar o hook** (2.5a) — obrigatório para o papel do usuário chegar ao token.
2. **Promover o primeiro gerencial** (2.5b) — sem isso, ninguém consegue escrever.
3. **Criar o `supabase-config.js`** com `authMode:'supabase'` e `mode:'supabase'` (Parte 3).
4. **Testar os dois papéis** com usuários reais:
   - usuário **operacional** tentando gravar → deve ser **negado** pelo RLS
   - usuário **gerencial** gravando → deve ser **aceito**
5. **R‑33** (recuperação de senha por código de uso único em e-mail) — previsto no Anexo de Regras v1.1, **não implementado**: depende do serviço de e-mail do Supabase estar ativo (Authentication → Email).

---

## Ressalvas honestas

- As migrations **não foram executadas contra um projeto Supabase real**. Foram executadas com sucesso, sem erros, em **PostgreSQL 15 local** — as seis, em ordem, mais uma segunda passada do `006` para confirmar que é idempotente.
- O teste **funcional** de RLS (operacional negado / gerencial aceito) ainda **não foi feito**: em PostgreSQL puro a role `authenticated` não tem `USAGE` no schema `auth`, o que impede a policy de ser avaliada. No Supabase esse `USAGE` existe. Faça o teste com dois usuários reais antes de considerar o RBAC validado.
- A base de dados embutida no app carrega **inconsistências históricas conhecidas** (lançamentos marcados para revisão, campos de saldo legados). Não impedem o uso, mas os relatórios não devem ser tratados como definitivos antes do saneamento.
- O bug de recursão de policy documentado no `004` foi validado contra PostgreSQL real por quem escreveu aquela migration; a correção aplicada pelo `006` segue a mesma abordagem (ler o papel só do JWT, nunca da tabela).
