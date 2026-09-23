# Claude Overlay

Janela sempre no topo que mostra as sessões do Claude Code dos dois perfis (Empresa = `~/.claude-empresa`, Pessoal = `~/.claude`) e avisa com toast do Windows quando uma sessão responde ou pede algo.

## Como funciona

- `hook.js` roda nos hooks do Claude Code (SessionStart, UserPromptSubmit, PreToolUse, SubagentStart/Stop, Notification, Stop, SessionEnd) e grava `state/<perfil>/<session_id>.json`. Nunca escreve no stdout e roda em modo `async`, então não atrasa o Claude.
- `overlay.ps1` lê a cada 1,5 s os registros `sessions/<pid>.json` de cada perfil (sem invocar o binário `claude`), cruza com o estado dos hooks e desenha a janela. Só mostra sessões cujo processo está vivo.
- Estados: trabalhando (azul), pede permissão / esperando você (âmbar), respondeu (verde), ociosa / sem sinal (cinza).
- Cada linha mostra o nome da sessão, a pasta e, embaixo, o estado com o **nome do chat**. O nome sai do fim do transcript da sessão: o `customTitle` quando o chat foi renomeado, senão o `aiTitle` automático. Com cache por sessão, e o arquivo é aberto compartilhado para não travar o Claude. A última resposta ou ferramenta fica no tooltip da linha.

## Requisitos

- Windows 10/11 com Windows PowerShell 5.1 (WPF) e Node.js no PATH.
- Claude Code (CLI ou extensão do VS Code/Cursor) com hooks habilitados.
- Perfis: o padrão são dois `CLAUDE_CONFIG_DIR`, `~/.claude-empresa` e `~/.claude`. Para usar outros, edite a lista `$script:Perfis` no `overlay.ps1` e `PERFIS` no `instalar-hooks.js` (a `Chave` precisa ser igual nos dois). Um perfil que não existe é ignorado.

## Uso

- Abrir: dois cliques no atalho **Claude Overlay** na área de trabalho. Ele chama `abrir-oculto.vbs`, que sobe a janela sem piscar console. O `Claude Overlay.cmd` continua valendo como alternativa.
- Arraste pela barra de título; redimensione pelo canto.
- Clique numa linha destacada para marcar como vista. Duplo clique na barra de título ou o botão ▾ deixa só a barra de resumo.
- Botão □ encolhe tudo num quadradinho com os três contadores (azul trabalhando, âmbar esperando, verde respondeu). Ele é arrastável e a borda acende quando há algo não visto; um clique nele volta ao tamanho normal.
- Brilho (privacidade): o slider na barra de título ou a roda do mouse sobre a barra escurecem a lista e, abaixo da metade, também a embaçam, para ninguém ler por cima do seu ombro. No máximo tudo fica normal. A barra de título e o quadradinho continuam legíveis, para você conseguir subir o brilho de volta. A janela nunca fica transparente.
- Botão `som` silencia os toasts. `✕` fecha. Posição, tamanho, brilho, modo e preferências ficam em `overlay.pos.json`.
- Diagnóstico no terminal: `powershell -File overlay.ps1 -Diagnostico`. Testar toast: `powershell -File overlay.ps1 -TestarToast`.
- Abrir com o Windows: copie o atalho da área de trabalho para dentro da pasta `shell:startup`.
- Ícone: `claude-overlay.ico`, gerado nos tamanhos 16 a 256. Se trocar, aponte de novo em Propriedades do atalho.

## Hooks

- Instalar/reinstalar: `node instalar-hooks.js`. Remover: `node instalar-hooks.js --remover`.
- Cada execução faz backup do `settings.json` em `<perfil>/backups-manual/`.
- Sessões que já estavam abertas antes da instalação aparecem como "sem sinal ainda" até o Claude recarregar os hooks (o file watcher costuma fazer isso sozinho; se não, `/hooks` na sessão).

## Logs

`hook.log` (erros do coletor) e `overlay.log` (erros da janela), ambos nesta pasta.
