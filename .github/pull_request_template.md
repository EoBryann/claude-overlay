## O que muda

<!-- O problema e como este PR resolve. Se fechar uma issue: "Fecha #123". -->

## Como testei

- [ ] `node tests/instalar.test.js` passa
- [ ] Abri a janela e conferi a mudança (se mexeu no `overlay.ps1`)
- [ ] Rodei `node tools/gerar-prints.js` (se mudou o visual)

## Checklist

- [ ] O PR aponta para a branch `develop`
- [ ] O `overlay.ps1` continua em UTF-8 **com BOM** e funciona no Windows PowerShell 5.1
- [ ] O `hook.js` continua sem escrever no stdout e sai sempre com 0
- [ ] Atualizei o `CHANGELOG.md` (seção "Não lançado")
