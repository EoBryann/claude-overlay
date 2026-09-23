#!/usr/bin/env node
'use strict';
// Testes do instalador e do coletor de hooks. Uso: node tests/instalar.test.js
// Tudo roda numa cópia do app numa pasta temporária, com perfis falsos:
// nenhum settings.json de verdade é tocado e nenhum atalho é criado.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const REPO = path.resolve(__dirname, '..');
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-overlay-teste-'));
const APP = path.join(T, 'app');
const A = path.join(T, 'perfis', '.claude-a');
const B = path.join(T, 'perfis', '.claude-b');

let falhas = 0;
function ok(cond, msg) { console.log(`${cond ? 'ok   ' : 'FALHA'} ${msg}`); if (!cond) falhas++; }
function instalar(...args) { return execFileSync(process.execPath, [path.join(APP, 'instalar.js'), '--sem-atalho', ...args], { cwd: APP, encoding: 'utf8', stdio: 'pipe' }); }
function instalarFalha(...args) { try { instalar(...args); return ''; } catch (e) { return String(e.stderr); } }
function hook(perfil, evento) { execFileSync(process.execPath, [path.join(APP, 'hook.js'), perfil], { input: JSON.stringify(evento) }); }
function settings(p) { return JSON.parse(fs.readFileSync(path.join(p, 'settings.json'), 'utf8')); }
function resumo(s) {
  return Object.fromEntries(Object.entries(s.hooks || {}).map(([ev, grupos]) =>
    [ev, grupos.flatMap((g) => g.hooks).map((h) => (h.args ? `overlay:${h.args[1]}` : h.command)).join(',')]));
}
function config(obj) { fs.writeFileSync(path.join(APP, 'config.json'), typeof obj === 'string' ? obj : JSON.stringify(obj)); }

try {
  fs.mkdirSync(APP, { recursive: true });
  for (const f of ['hook.js', 'instalar.js', 'overlay.ps1', 'abrir-oculto.vbs', 'claude-overlay.ico']) fs.copyFileSync(path.join(REPO, f), path.join(APP, f));
  fs.mkdirSync(A, { recursive: true });
  fs.mkdirSync(path.join(B, 'projects'), { recursive: true });
  fs.writeFileSync(path.join(A, 'settings.json'), JSON.stringify({
    model: 'opus',
    hooks: {
      Stop: [{ hooks: [{ type: 'command', command: 'echo meu-hook' }] }],
      PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'echo outro' }] }],
    },
  }, null, 2));

  console.log('# instalar');
  config({ perfis: [{ nome: 'Conta Á', pasta: A }, { nome: 'B', id: 'bee', pasta: B }, { nome: 'Sumiu', pasta: '~/nao-existe-claude-overlay' }] });
  const saida = instalar();
  instalar(); // de novo: não pode duplicar
  let a = settings(A), b = settings(B);
  ok(a.model === 'opus', 'mantém as outras chaves do settings.json');
  ok(resumo(a).Stop === 'echo meu-hook,overlay:conta-a', 'mantém o hook do usuário e põe um só do overlay (id sem acento)');
  ok(resumo(a).PreToolUse === 'echo outro,overlay:conta-a' && a.hooks.PreToolUse[0].matcher === 'Bash', 'mantém o matcher do usuário');
  ok(Object.keys(b.hooks).length === 8 && resumo(b).Stop === 'overlay:bee', 'cria o settings.json que faltava, com os 8 eventos e o id do config');
  const h = a.hooks.Stop[1].hooks[0];
  ok(h.args[0] === path.join(APP, 'hook.js') && h.async === true && h.command === process.execPath, 'hook aponta para a pasta do app, com node absoluto e async');
  ok(/Sumiu.*não existe/.test(saida), 'avisa e pula perfil cuja pasta não existe');

  console.log('# remover');
  instalar('--remover');
  a = settings(A); b = settings(B);
  ok(JSON.stringify(resumo(a)) === JSON.stringify({ Stop: 'echo meu-hook', PreToolUse: 'echo outro' }), 'só os hooks do usuário sobram');
  ok(!b.hooks, 'perfil B fica sem hooks');
  ok(fs.readdirSync(path.join(A, 'backups-manual')).length === 3, 'um backup por gravação');

  console.log('# config inválido');
  config('{ "perfis": [ { "nome": "x", "pasta": "C:\\sem-escape" } ] }');
  ok(/config\.json inválido/.test(instalarFalha()), 'JSON quebrado: mensagem clara');
  config({ perfis: [{ nome: 'x', id: 'dup', pasta: A }, { nome: 'y', id: 'dup', pasta: B }] });
  ok(/aparece em mais de um perfil/.test(instalarFalha()), 'id repetido: mensagem clara');
  config({ perfis: [] });
  ok(/nenhum perfil/.test(instalarFalha()), 'lista vazia: mensagem clara');
  fs.unlinkSync(path.join(APP, 'config.json'));

  console.log('# hook.js');
  const st = (perfil, sid) => JSON.parse(fs.readFileSync(path.join(APP, 'state', perfil, `${sid}.json`), 'utf8'));
  hook('Conta Á', { session_id: 's1', hook_event_name: 'SessionStart', source: 'startup', cwd: 'C:\\x' });
  ok(st('conta-a', 's1').state === 'idle', 'SessionStart: ociosa, na pasta state/<id sem acento>');
  hook('conta-a', { session_id: 's1', hook_event_name: 'UserPromptSubmit', prompt: 'faz   isso\n  aqui' });
  ok(st('conta-a', 's1').state === 'working' && st('conta-a', 's1').detail === 'faz isso aqui', 'UserPromptSubmit: trabalhando, com o prompt resumido');
  hook('conta-a', { session_id: 's1', hook_event_name: 'SubagentStart', agent_type: 'Explore' });
  ok(st('conta-a', 's1').subagents === 1, 'SubagentStart conta subagente');
  hook('conta-a', { session_id: 's1', hook_event_name: 'Notification', notification_type: 'permission_prompt', message: 'pode rodar?' });
  ok(st('conta-a', 's1').state === 'permission', 'Notification permission_prompt: pede permissão');
  hook('conta-a', { session_id: 's1', hook_event_name: 'Stop', last_assistant_message: 'pronto' });
  const feito = st('conta-a', 's1');
  ok(feito.state === 'done' && feito.subagents === 0, 'Stop: respondeu e zera subagentes');
  hook('conta-a', { session_id: 's1', hook_event_name: 'Notification', notification_type: 'idle_prompt', message: 'esperando' });
  ok(st('conta-a', 's1').state === 'done' && st('conta-a', 's1').at === feito.at, 'idle_prompt repetido não muda estado nem horário (sem toast duplicado)');
  hook('conta-a', { session_id: 's1', hook_event_name: 'SessionEnd', reason: 'exit' });
  ok(st('conta-a', 's1').state === 'ended', 'SessionEnd: encerrada');
  const out = execFileSync(process.execPath, [path.join(APP, 'hook.js'), 'x'], { input: 'isto não é json', encoding: 'utf8' });
  ok(out === '', 'entrada inválida: sai sem escrever no stdout');

  if (process.platform === 'win32') {
    console.log('# overlay.ps1');
    const nomes = ['Pessoal Ç', 'Conta Á', 'Trabalho — Cliente X', '  ', 'São_Paulo-2'];
    const fNomes = path.join(T, 'nomes.json');
    fs.writeFileSync(fNomes, JSON.stringify(nomes));
    const script = [
      '$src = [IO.File]::ReadAllText(' + JSON.stringify(path.join(APP, 'overlay.ps1')).replace(/"/g, "'") + ')',
      "$i = $src.IndexOf('function Id-Perfil'); $f = $src.IndexOf('function Atualizar-Perfis')",
      'Invoke-Expression $src.Substring($i, $f - $i)',
      '$n = [IO.File]::ReadAllText(' + JSON.stringify(fNomes).replace(/"/g, "'") + ', [Text.Encoding]::UTF8) | ConvertFrom-Json',
      "($n | ForEach-Object { Id-Perfil $_ }) -join '|'",
    ].join('; ');
    const doPs = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' }).trim();
    const slug = (s) => String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'perfil';
    ok(doPs === nomes.map(slug).join('|'), `overlay.ps1 e instalar.js geram o mesmo id (${doPs})`);
    const diag = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(APP, 'overlay.ps1'), '-Diagnostico'], { encoding: 'utf8', stdio: 'pipe' });
    ok(/Perfil|Nenhuma sess/.test(diag), 'overlay.ps1 -Diagnostico roda e lista as sessões');
  }
} finally {
  fs.rmSync(T, { recursive: true, force: true });
}

console.log(falhas ? `\n${falhas} teste(s) falharam` : '\ntodos os testes passaram');
process.exit(falhas ? 1 : 0);
