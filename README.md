# Claude Overlay

Janela pequena, sempre no topo, que mostra todas as sessões abertas do [Claude Code](https://code.claude.com) no Windows: CLI e extensão do VS Code/Cursor, de uma ou mais contas ao mesmo tempo. Quando uma sessão responde ou pede permissão, ela avisa com uma notificação do Windows.

Cada linha traz o nome da sessão, a pasta, o número de subagentes, há quanto tempo foi o último evento e, embaixo, o estado com o nome do chat:

- **trabalhando** (azul)
- **pede permissão** / **esperando você** (âmbar)
- **respondeu** (verde)
- **ociosa** / **sem sinal** (cinza)

## Requisitos

- Windows 10 ou 11 com o Windows PowerShell 5.1, que já vem no sistema.
- [Node.js](https://nodejs.org) 18 ou mais novo.
- Claude Code recente, com suporte a hooks na forma `command` + `args` (testado na 2.1.280).

## Instalação

```powershell
git clone https://github.com/EoBryann/claude-overlay.git
cd claude-overlay
node instalar.js
```

O instalador:

1. Procura as pastas de configuração do Claude Code: `~/.claude`, `~/.claude-*` e a do `CLAUDE_CONFIG_DIR`, se estiver definida. Depois grava o que encontrou no `config.json`.
2. Adiciona os hooks do overlay no `settings.json` de cada perfil, com backup em `<perfil>/backups-manual/`. Os hooks que você já tinha continuam lá.
3. Cria o atalho **Claude Overlay** na área de trabalho. Com `--iniciar-com-windows`, cria também o atalho para abrir no logon.

Depois é só abrir pelo atalho. As sessões que já estavam abertas aparecem como "sem sinal" até o próximo evento. Se não mudarem sozinhas, rode `/hooks` nelas.

Os hooks apontam para a pasta onde você clonou. Se mover a pasta, rode `node instalar.js` de novo.

## Configuração

Tudo fica no `config.json`, que é criado na primeira instalação e não vai para o git. Veja o [config.exemplo.json](config.exemplo.json):

```json
{
  "perfis": [
    { "nome": "Trabalho", "id": "trabalho", "pasta": "~/.claude-trabalho" },
    { "nome": "Pessoal",  "id": "pessoal",  "pasta": "~/.claude" }
  ]
}
```

- `pasta` é o `CLAUDE_CONFIG_DIR` do perfil. Aceita `~` e variáveis como `%USERPROFILE%`.
- `nome` é o que aparece no cabeçalho do grupo.
- `id` identifica o perfil no hook e na pasta `state/`. Se ficar em branco, sai do `nome`.
- A ordem da lista é a ordem dos grupos na janela.

Depois de mudar os perfis, rode `node instalar.js` de novo para instalar os hooks nos novos. A janela relê o `config.json` sozinha.

Quem usa só uma conta não precisa de nada disso: sem `config.json`, o overlay mostra o perfil padrão (`CLAUDE_CONFIG_DIR` ou `~/.claude`).

As preferências da janela ficam no `overlay.pos.json` e são salvas automaticamente: posição, tamanho, modo, som e brilho.

## Uso

- Arraste pela barra de título e redimensione pelo canto.
- Clique numa linha destacada para marcar como vista. Passe o mouse para ver a pasta completa e a última resposta ou ferramenta.
- Duplo clique na barra, ou o botão ▾, deixa só a barra de resumo.
- O botão □ encolhe tudo num quadradinho com três contadores: azul (trabalhando), âmbar (esperando) e verde (respondeu).
  - A borda acende quando há algo que você ainda não viu.
  - Arraste para mover; um clique volta ao tamanho normal.
- **Brilho** (privacidade): o slider, ou a roda do mouse sobre a barra, escurece a lista. Abaixo da metade também embaça, para ninguém ler por cima do seu ombro. A barra e o quadradinho continuam legíveis.
- `som` silencia as notificações e `✕` fecha.

## Desinstalar

```powershell
node instalar.js --remover
```

Isso tira os hooks de todos os perfis do `config.json` e remove os atalhos que apontam para esta pasta. Depois é só apagar a pasta.

## Como funciona

- **`hook.js`** roda nos eventos `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `SubagentStart`/`SubagentStop`, `Notification`, `Stop` e `SessionEnd`. Ele grava `state/<perfil>/<session_id>.json`.
  - Roda com `async: true` e nunca escreve no stdout, então não atrasa nem interfere no Claude.
  - Estados com mais de 3 dias são apagados sozinhos.
- **`overlay.ps1`** (WPF) desenha a janela a cada 1,5 s. Para isso, lê os registros `sessions/<pid>.json` que o próprio Claude Code mantém em cada perfil, sem chamar o binário `claude`, e cruza com o estado gravado pelos hooks. Só mostra sessões cujo processo está vivo.
- **O nome do chat** sai do fim do transcript da sessão: o `customTitle`, quando o chat foi renomeado, ou senão o `aiTitle` automático. O arquivo é aberto em modo compartilhado, para não travar o Claude.
- **As notificações** usam o toast nativo do Windows (WinRT). Se ele não estiver disponível, toca um som.

## Solução de problemas

- `powershell -File overlay.ps1 -Diagnostico` lista no terminal as sessões que a janela enxerga.
- `powershell -File overlay.ps1 -TestarToast` dispara uma notificação de teste.
- `node instalar.js --detectar` mostra quais perfis o instalador encontraria, sem gravar nada.
- `overlay.log` (janela) e `hook.log` (hooks) ficam nesta pasta.
- Só abre uma janela por vez. Se o atalho não fizer nada, a janela provavelmente já está aberta em outro monitor.

## Licença

[MIT](LICENSE)
