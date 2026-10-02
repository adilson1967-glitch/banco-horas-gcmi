# Migração para Supabase + publicação no GitHub

## 1. Banco (Supabase)
Aplique as migrations **na ordem 001 → 006** (veja `supabase/README.md`). Se preferir o CLI:
```bash
npm i -g supabase && supabase login && supabase link --project-ref SEU-REF && supabase db push
```

Depois, os dois passos manuais:
- **Authentication → Hooks → Custom Access Token** → `public.custom_access_token_hook`
- promover o primeiro usuário gerencial em `public.user_roles`

## 2. Configuração do cliente
Copie o modelo e preencha com os dados do seu projeto (`Project Settings > API`):
```bash
cp public/supabase-config.example.js public/supabase-config.js
```
```js
window.SUPABASE_CONFIG = {
  url: 'https://SEU-PROJETO.supabase.co',
  anonKey: 'SUA-ANON-KEY',      // chave PÚBLICA, protegida pelo RLS
  table: 'banco_horas_snapshot',
  mode: 'supabase',              // 'disabled' | 'supabase'
  authMode: 'supabase',          // 'local' | 'supabase'
  sync: 'auto'                   // 'manual' | 'auto'
};
```
`public/supabase-config.js` está no `.gitignore` — a chave não vai para o repositório.

**Nunca** use a chave `service_role` no navegador: ela ignora o RLS.

## 3. GitHub
```bash
git init
git add .
git commit -m "Banco de Horas GCMI v110 — migrations 001..006"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/banco-horas-gcmi.git
git push -u origin main
```

## 4. GitHub Pages
`Settings → Pages → Source: Deploy from a branch → main / (root)`.

O app é um único `index.html`; ele procura `supabase-config.js` primeiro na raiz e depois em `public/`. Como esse arquivo é ignorado pelo git, o Pages **não** o terá — e o app sobe em modo local (IndexedDB). Para habilitar o Supabase no Pages, gere o arquivo no deploy via GitHub Actions, lendo os valores de *repository secrets*:

```yaml
# .github/workflows/pages.yml (trecho)
- name: Gerar supabase-config.js
  run: |
    cat > public/supabase-config.js <<EOF
    window.SUPABASE_CONFIG={url:'${{ secrets.SUPABASE_URL }}',anonKey:'${{ secrets.SUPABASE_ANON_KEY }}',table:'banco_horas_snapshot',mode:'supabase',authMode:'supabase',sync:'auto'};
    EOF
```
A chave `anon` é pública por natureza (quem protege os dados é o RLS). Ainda assim, mantê-la em secret evita que ela se espalhe em forks.

## 5. Checklist antes de considerar pronto
- [ ] Migrations 001 → 006 aplicadas sem erro
- [ ] Hook registrado no painel
- [ ] Pelo menos um usuário com `role = 'gerencial'` em `user_roles`
- [ ] `select * from public.vw_harmonizacao` conferido
- [ ] `supabase-config.js` presente no ambiente de publicação
- [ ] Teste de escrita com usuário **operacional** (deve ser **negado** pelo RLS)
- [ ] Teste de escrita com usuário **gerencial** (deve ser **aceito**)
