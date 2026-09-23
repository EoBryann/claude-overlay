#!/usr/bin/env node
'use strict';
// Regera os prints de docs/ com sessões fictícias. Uso: node tools/gerar-prints.js
// Monta perfis falsos numa pasta temporária, abre uma cópia do overlay que renderiza a janela
// em PNG (2x) e fecha sozinha. Não lê nem mostra nenhuma sessão de verdade.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync, spawn } = require('child_process');

const REPO = path.resolve(__dirname, '..');
const OUT = path.join(REPO, 'docs');
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-overlay-prints-'));
const APP = path.join(T, 'app');
fs.mkdirSync(APP, { recursive: true });
fs.mkdirSync(OUT, { recursive: true });

// cópia do overlay com mutex próprio e um timer que salva a janela em PNG
let ps = fs.readFileSync(path.join(REPO, 'overlay.ps1'), 'utf8').replace(/^\uFEFF/, '');
ps = ps.replace("'Local\\ClaudeOverlay'", "'Local\\ClaudeOverlayPrints'");
ps = ps.replace('[void]$script:Win.ShowDialog()', () => `
$script:Snap = New-Object Windows.Threading.DispatcherTimer
$script:Snap.Interval = [TimeSpan]::FromSeconds(3)
$script:Snap.Add_Tick({
  $script:Snap.Stop()
  $el = $script:Shell
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap -ArgumentList ([int]($el.ActualWidth * 2)), ([int]($el.ActualHeight * 2)), 192, 192, ([Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($el)
  $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $fs = [IO.File]::Create($env:PRINT_OUT); $enc.Save($fs); $fs.Close()
  $script:Win.Close()
})
$script:Snap.Start()
[void]$script:Win.ShowDialog()`);
fs.writeFileSync(path.join(APP, 'overlay.ps1'), '\uFEFF' + ps);

// o overlay só mostra sessões com processo vivo: sobe processos node parados para emprestar os pids
const sessoes = [
  ['trabalho', 'api-pagamentos-3f', 'api-pagamentos', 'permission', 'Claude needs your permission to use Bash', 25, 0, { customTitle: 'pagamentos — Migrar webhooks para a fila nova' }],
  ['trabalho', 'site-institucional-a1', 'site-institucional', 'done', 'Menu corrigido: era o overflow do header em 768px.', 140, 0, { aiTitle: 'Corrigir layout do menu no mobile' }],
  ['trabalho', 'api-pagamentos-7c', 'api-pagamentos', 'working', '[sub] Bash: npm test', 3, 2, { aiTitle: 'Revisar testes de integração' }],
  ['trabalho', 'painel-admin-09', 'painel-admin', 'working', 'Edit: RelatorioController.cs', 9, 0, { aiTitle: 'Exportar relatório em CSV' }],
  ['trabalho', 'painel-admin-5e', 'painel-admin', 'idle', 'sessão iniciada (resume)', 3900, 0, { aiTitle: 'Planejar a tela de permissões' }],
  ['pessoal', 'blog-5b', 'blog', 'needs_input', 'Claude is waiting for your input', 70, 0, { aiTitle: 'Rascunho do post sobre hooks' }],
  ['pessoal', 'dotfiles-2d', 'dotfiles', 'working', 'Read: settings.json', 5, 0, { aiTitle: 'Configurar o terminal novo' }],
];
const filhos = sessoes.map(() => spawn(process.execPath, ['-e', 'setTimeout(() => {}, 120000)'], { stdio: 'ignore' }));

try {
  const agora = Date.now();
  const perfis = [
    { nome: 'Trabalho', id: 'trabalho', pasta: path.join(T, 'perfis', '.claude-trabalho') },
    { nome: 'Pessoal', id: 'pessoal', pasta: path.join(T, 'perfis', '.claude') },
  ];
  sessoes.forEach(([perfil, nome, pasta, state, detail, seg, subs, titulo], i) => {
    const cfg = perfis.find((p) => p.id === perfil).pasta;
    const sid = `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`;
    const cwd = `C:\\Users\\voce\\projetos\\${pasta}`;
    const pid = filhos[i].pid;
    const tr = path.join(cfg, 'projects', 'demo', `${sid}.jsonl`);
    fs.mkdirSync(path.dirname(tr), { recursive: true });
    fs.mkdirSync(path.join(cfg, 'sessions'), { recursive: true });
    const linhas = [];
    if (titulo.customTitle) linhas.push({ type: 'custom-title', customTitle: titulo.customTitle, sessionId: sid });
    linhas.push({ type: 'ai-title', aiTitle: titulo.aiTitle || titulo.customTitle, sessionId: sid });
    fs.writeFileSync(tr, linhas.map((l) => JSON.stringify(l)).join('\n') + '\n');
    fs.writeFileSync(path.join(cfg, 'sessions', `${pid}.json`), JSON.stringify({ pid, sessionId: sid, cwd, startedAt: agora - 7200000, name: nome, kind: 'interactive' }));
    const st = path.join(APP, 'state', perfil);
    fs.mkdirSync(st, { recursive: true });
    fs.writeFileSync(path.join(st, `${sid}.json`), JSON.stringify({ sessionId: sid, perfil, cwd, transcript: tr, state, detail, at: agora - seg * 1000, subagents: subs }));
  });
  fs.writeFileSync(path.join(APP, 'config.json'), JSON.stringify({ perfis }, null, 2));

  const prints = [
    ['janela.png', { Brilho: 1 }],
    ['privacidade.png', { Brilho: 0.08 }],
    ['mini.png', { Brilho: 1, Mini: true }],
  ];
  for (const [arquivo, pos] of prints) {
    fs.writeFileSync(path.join(APP, 'overlay.pos.json'), JSON.stringify(Object.assign({ Left: 200, Top: 120, Width: 520, Height: 410, Mudo: false, Compacto: false, Mini: false }, pos)));
    execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', path.join(APP, 'overlay.ps1')], {
      env: Object.assign({}, process.env, { PRINT_OUT: path.join(OUT, arquivo) }),
      stdio: 'inherit',
    });
    console.log(`docs/${arquivo}`);
  }
} finally {
  for (const f of filhos) { try { f.kill(); } catch (_) {} }
  fs.rmSync(T, { recursive: true, force: true });
}
