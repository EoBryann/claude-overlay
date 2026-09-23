<p align="center">
  <img src="docs/icone.png" width="88" alt="">
</p>

<h1 align="center">Claude Overlay</h1>

<p align="center">
  Todas as suas sessões do Claude Code numa janelinha sempre no topo do Windows.<br>
  Várias contas juntas, estado em tempo real e aviso quando alguma precisa de você.
</p>

<p align="center">
  <a href="https://github.com/EoBryann/claude-overlay/actions/workflows/ci.yml"><img src="https://github.com/EoBryann/claude-overlay/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="https://github.com/EoBryann/claude-overlay/releases/latest"><img src="https://img.shields.io/github/v/release/EoBryann/claude-overlay?label=vers%C3%A3o" alt="Versão"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6" alt="Windows 10 | 11">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/EoBryann/claude-overlay?label=licen%C3%A7a" alt="Licença MIT"></a>
</p>

<p align="center">
  <b>Português</b> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <img src="docs/janela.png" width="520" alt="Janela do Claude Overlay com sessões de dois perfis: uma pedindo permissão, uma que respondeu, três trabalhando e uma ociosa">
</p>

## Por quê

Quem abre várias sessões do Claude Code ao mesmo tempo (terminal, VS Code, Cursor, conta do trabalho e conta pessoal) acaba esquecendo uma delas parada, pedindo permissão, enquanto olha outra. O Claude Overlay junta todas numa janela pequena que fica por cima das outras e avisa quando alguma responde ou precisa de você.

## Recursos

- **Todas as sessões num lugar só:** CLI e extensões do VS Code/Cursor, agrupadas por perfil.
- **Várias contas ao mesmo tempo:** cada `CLAUDE_CONFIG_DIR` vira um grupo na mesma janela.
- **Estado em tempo real:** <img src="https://img.shields.io/badge/-trabalhando-4FA3FF" alt=""> <img src="https://img.shields.io/badge/-pede%20permiss%C3%A3o-FFB020" alt=""> <img src="https://img.shields.io/badge/-esperando%20voc%C3%AA-FFB020" alt=""> <img src="https://img.shields.io/badge/-respondeu-3DDC84" alt=""> <img src="https://img.shields.io/badge/-ociosa-7B8594" alt="">
- **Nome do chat** de cada sessão, seja o que você deu ao renomear ou o título automático, além da pasta, dos subagentes ativos e de há quanto tempo foi o último evento.
- **Notificação do Windows** quando uma sessão responde ou pede permissão.
- **Modo quadradinho:** encolhe para três contadores e a borda acende quando há algo que você não viu.
- **Privacidade:** um controle escurece e embaça a lista, para ninguém ler por cima do seu ombro.
- **Leve:** sem dependências npm, sem serviço rodando e sem chamar o binário do Claude. Os hooks rodam em modo assíncrono e não atrasam as sessões.

<table>
  <tr>
    <td align="center"><img src="docs/privacidade.png" width="380" alt="Lista escurecida e embaçada"><br><sub>Privacidade: a lista escurece e embaça</sub></td>
    <td align="center"><img src="docs/mini.png" width="88" alt="Quadradinho com os contadores"><br><sub>Modo quadradinho</sub></td>
  </tr>
</table>

## Requisitos

- Windows 10 ou 11 com o Windows PowerShell 5.1, que já vem no sistema.
- [Node.js](https://nodejs.org) 20 ou mais novo.
- Claude Code recente, com suporte a hooks na forma `command` + `args` (testado na 2.1.280).

## Instalação

```powershell
git clone https://github.com/EoBryann/claude-overlay.git
cd claude-overlay
node instalar.js
```

Depois é só abrir pelo atalho **Claude Overlay** que aparece na área de trabalho.

O instalador:
1. Encontra as pastas de configuração do Claude Code: `~/.claude`, `~/.claude-*` e a do `CLAUDE_CONFIG_DIR`. Depois grava o que encontrou no `config.json`.
2. Adiciona os hooks do overlay no `settings.json` de cada perfil, com backup em `<perfil>/backups-manual/`. Os hooks que você já tinha continuam lá.
3. Cria o atalho na área de trabalho. Com `--iniciar-com-windows`, cria também o atalho para abrir no logon.

> [!NOTE]
> As sessões que já estavam abertas aparecem como "sem sinal" até o próximo evento. Se não mudarem sozinhas, rode `/hooks` nelas.
> Os hooks apontam para a pasta onde você clonou: se mover a pasta, rode `node instalar.js` de novo.

Para atualizar: `git pull` na pasta, feche a janela e abra de novo.

## Configuração

Tudo fica no `config.json`. Ele é criado na primeira instalação, não vai para o git e segue o formato do [config.exemplo.json](config.exemplo.json):

```json
{
  "perfis": [
    { "nome": "Trabalho", "id": "trabalho", "pasta": "~/.claude-trabalho" },
    { "nome": "Pessoal",  "id": "pessoal",  "pasta": "~/.claude" }
  ]
}
```

| Campo | O que é |
|---|---|
| `pasta` | O `CLAUDE_CONFIG_DIR` do perfil. Aceita `~` e variáveis como `%USERPROFILE%`. |
| `nome` | O que aparece no cabeçalho do grupo. |
| `id` | Identifica o perfil no hook e na pasta `state/`. Se ficar em branco, sai do `nome`. |

- A ordem da lista é a ordem dos grupos na janela.
- Depois de incluir um perfil, rode `node instalar.js` de novo para instalar os hooks nele. A janela relê o `config.json` sozinha.
- Quem usa só uma conta não precisa de config: sem ele, o overlay mostra o perfil padrão (`CLAUDE_CONFIG_DIR` ou `~/.claude`).

As preferências da janela ficam no `overlay.pos.json` e são salvas sozinhas: posição, tamanho, modo, som e brilho.

## Uso

| Ação | Como |
|---|---|
| Mover / redimensionar | Arraste pela barra de título / pelo canto inferior direito |
| Marcar como vista | Clique na linha destacada |
| Ver a pasta completa e a última resposta | Passe o mouse sobre a linha |
| Só a barra de resumo | Duplo clique na barra ou botão **▾** |
| Quadradinho | Botão **□**; arraste para mover, clique para voltar |
| Privacidade | Slider na barra ou roda do mouse sobre ela |
| Silenciar notificações | Botão **som** |

## Desinstalar

```powershell
node instalar.js --remover
```

Remove os hooks de todos os perfis do `config.json` e os atalhos que apontam para esta pasta. Depois é só apagar a pasta.

## Como funciona

```text
 Claude Code (cada sessão)                      Claude Overlay
 ─────────────────────────                      ──────────────
 hooks ──► hook.js ──► state/<perfil>/<sessão>.json ──┐
                                                      ├──► overlay.ps1 (WPF, a cada 1,5 s)
 sessions/<pid>.json  (mantido pelo Claude Code) ─────┤
 projects/…/<sessão>.jsonl  (nome do chat) ───────────┘
```

- **`hook.js`** roda nos eventos `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `SubagentStart`/`SubagentStop`, `Notification`, `Stop` e `SessionEnd`, e grava o estado de cada sessão.
  - Não escreve no stdout e roda com `async: true`.
  - Estados com mais de 3 dias são apagados sozinhos.
- **`overlay.ps1`** cruza esse estado com os registros `sessions/<pid>.json` que o próprio Claude Code mantém. Só mostra sessões cujo processo está vivo.
- **O nome do chat** sai do fim do transcript: o `customTitle` ou o `aiTitle`. O arquivo é aberto em modo compartilhado, para não travar o Claude.
- **As notificações** usam o toast nativo do Windows. Se ele não estiver disponível, toca um som.

## Solução de problemas

| Sintoma | O que fazer |
|---|---|
| O atalho não abre nada | Só abre uma janela por vez; ela pode estar em outro monitor. Veja o `overlay.log`. |
| Sessão aparece "sem sinal" | Os hooks ainda não rodaram nela. Mande uma mensagem ou rode `/hooks`. |
| Sessão não aparece | `powershell -File overlay.ps1 -Diagnostico` mostra o que a janela enxerga. Confira se o perfil está no `config.json`. |
| Perfil errado no config | `node instalar.js --detectar` mostra o que seria detectado, sem gravar nada. |
| Sem notificação | `powershell -File overlay.ps1 -TestarToast` e confira as notificações do Windows para o PowerShell. |

Os erros ficam no `overlay.log` (janela) e no `hook.log` (hooks), na pasta do overlay.

## Contribuindo

PRs são bem-vindos! Veja o [CONTRIBUTING.md](CONTRIBUTING.md) para o fluxo de branches (`develop` → `main`), os testes e as regras do código. As mudanças de cada versão ficam no [CHANGELOG.md](CHANGELOG.md).

## Licença

[MIT](LICENSE) © Bryan Porto

<sub>Projeto independente da comunidade, sem vínculo com a Anthropic. "Claude" e "Claude Code" são marcas da Anthropic.</sub>
