# Changelog

Todas as mudanças relevantes ficam aqui. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e as versões seguem o [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [1.0.0] - 2026-09-23

Primeira versão pública.

### Recursos
- Janela sempre no topo com as sessões abertas do Claude Code (CLI e extensões do VS Code/Cursor) de um ou mais perfis (`CLAUDE_CONFIG_DIR`), agrupadas por perfil.
- Estados por sessão: trabalhando, pede permissão, esperando você, respondeu, ociosa e sem sinal.
- Cada sessão mostra o nome do chat (o título renomeado ou o automático), a pasta, os subagentes e há quanto tempo foi o último evento.
- Notificação do Windows quando uma sessão responde ou pede algo, com botão para silenciar.
- Modo só-barra, modo quadradinho com contadores e borda que acende, e escurecedor de privacidade.
- `instalar.js`:
  - detecta os perfis e gera o `config.json`;
  - instala e remove os hooks sem mexer nos hooks do usuário, com backup do `settings.json`;
  - cria o atalho na área de trabalho e, opcionalmente, na inicialização do Windows.
- Testes do instalador e do coletor de hooks, rodando no GitHub Actions.

[Não lançado]: https://github.com/EoBryann/claude-overlay/compare/v1.0.0...develop
[1.0.0]: https://github.com/EoBryann/claude-overlay/releases/tag/v1.0.0
