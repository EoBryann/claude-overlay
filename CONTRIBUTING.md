# Contribuindo

Valeu pelo interesse! Issues e PRs são bem-vindos. Para ideias maiores, abra uma issue antes para a gente alinhar.

## Branches

| Branch | Para quê |
|---|---|
| `main` | Versão estável. É o que as pessoas clonam. Cada release vira uma tag `vX.Y.Z`. |
| `develop` | Integração do que vai entrar na próxima versão. |
| `feat/...`, `fix/...`, `docs/...` | Uma branch por mudança, saindo da `develop`. |

Fluxo:
1. Crie a branch a partir da `develop`.
2. Abra o PR para a `develop`; o CI precisa passar.
3. Na hora de lançar, a `develop` é mergeada na `main` com uma tag e uma release no GitHub.

## Rodando localmente

Não há dependências para instalar: é só Node.js e o PowerShell do Windows.

```powershell
node tests/instalar.test.js                 # testes (usa perfis falsos numa pasta temporária)
powershell -File overlay.ps1 -Diagnostico   # o que a janela enxerga agora
node tools/gerar-prints.js                  # regera os prints de docs/ com dados fictícios
```

Para testar a janela com o código da sua branch, feche o overlay aberto e abra o `Claude Overlay.cmd` do seu clone. Os hooks apontam para a pasta onde você rodou o `instalar.js`.

## Regras do código

- **`overlay.ps1` roda no Windows PowerShell 5.1**, não no PowerShell 7. Isso quer dizer:
  - sem `??`, `?.`, ternário ou `&&`;
  - o arquivo fica em UTF-8 **com BOM**, senão os acentos quebram. O CI confere as duas coisas.
- **`hook.js` roda a cada evento de todas as sessões:**
  - nunca escreve no stdout, porque vira contexto no Claude;
  - sai sempre com 0;
  - tem que terminar rápido.
  - Não adicione hooks em `PostToolUse`: é barulho demais.
- **Sem dependências npm.** O app precisa funcionar com um `git clone` e nada mais.
- **O `instalar.js` nunca pode perder hooks do usuário.** Qualquer mudança nele precisa de teste em `tests/instalar.test.js`.
- **Nada de dados reais** em prints, testes ou exemplos: use o `tools/gerar-prints.js` e nomes fictícios.
- A interface é em português. Se for traduzir, mantenha o português como padrão.

## Commits

Mensagens em português, com prefixo: `Feat:`, `Fix:`, `Docs:`, `Test:`, `CI:`, `Chore:` ou `Refactor:`. Exemplo: `Fix: toast duplicado quando o idle_prompt repete`.
