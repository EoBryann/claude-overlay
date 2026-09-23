#!/usr/bin/env node
'use strict';
// Instala (ou remove) o Claude Overlay: config.json, hooks no settings.json de cada perfil e atalhos.
// Uso:
//   node instalar.js                        cria o config.json se faltar, instala os hooks e o atalho na área de trabalho
//   node instalar.js --iniciar-com-windows  também abre o overlay ao entrar no Windows
//   node instalar.js --sem-atalho           não cria nem remove atalhos
//   node instalar.js --detectar             só mostra os perfis que encontraria, sem gravar nada
//   node instalar.js --remover              tira os hooks dos perfis do config.json e os atalhos que apontam para cá
// Cada settings.json alterado ganha backup em <perfil>/backups-manual/ antes de ser gravado.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const args = process.argv.slice(2);
const remover = args.includes('--remover');
const detectar = args.includes('--detectar');
const semAtalho = args.includes('--sem-atalho');
const comWindows = args.includes('--iniciar-com-windows');

const BASE = __dirname;
const HOME = os.homedir();
const CONFIG = path.join(BASE, 'config.json');
const NODE = process.execPath;
const HOOK = path.join(BASE, 'hook.js');
const VBS = path.join(BASE, 'abrir-oculto.vbs');
const ICO = path.join(BASE, 'claude-overlay.ico');
const EVENTOS = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'SubagentStart', 'SubagentStop', 'Notification', 'Stop', 'SessionEnd'];

// ---- perfis ----
function slug(nome) {
  // mesma regra do Id-Perfil do overlay.ps1
  const s = String(nome).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '');
  return s || 'perfil';
}
function expandir(p) {
  let s = String(p || '').trim();
  if (!s) return '';
  s = s.replace(/^~(?=$|[\\/])/, HOME).replace(/%([^%]+)%/g, (m, v) => (process.env[v] !== undefined ? process.env[v] : m));
  return path.resolve(s);
}
function encurtar(p) {
  const r = path.resolve(p);
  return r.toLowerCase().startsWith(HOME.toLowerCase() + path.sep) ? '~/' + r.slice(HOME.length + 1).replace(/\\/g, '/') : r;
}
function mesmaPasta(a, b) { return path.resolve(a).toLowerCase() === path.resolve(b).toLowerCase(); }
function ehPerfil(pasta) {
  return ['settings.json', 'sessions', 'projects'].some((f) => fs.existsSync(path.join(pasta, f)));
}
function nomeDoPerfil(pasta) {
  const leaf = path.basename(pasta);
  if (/^\.claude$/i.test(leaf)) return 'Claude';
  const m = /^\.claude[-_.](.+)$/i.exec(leaf);
  const n = (m ? m[1] : leaf.replace(/^\./, '')).replace(/[-_.]+/g, ' ');
  return n.charAt(0).toUpperCase() + n.slice(1);
}

function detectarPerfis() {
  const candidatos = [];
  if (process.env.CLAUDE_CONFIG_DIR) candidatos.push(expandir(process.env.CLAUDE_CONFIG_DIR));
  candidatos.push(path.join(HOME, '.claude'));
  try {
    for (const d of fs.readdirSync(HOME)) if (/^\.claude[-_.]./i.test(d)) candidatos.push(path.join(HOME, d));
  } catch (_) {}
  const perfis = [];
  for (const pasta of candidatos) {
    if (mesmaPasta(pasta, BASE)) continue; // a própria pasta do overlay (ex.: ~/.claude-overlay)
    if (perfis.some((p) => mesmaPasta(expandir(p.pasta), pasta))) continue;
    if (!ehPerfil(pasta)) continue;
    const nome = nomeDoPerfil(pasta);
    let id = slug(nome);
    for (let i = 2; perfis.some((p) => p.id === id); i++) id = `${slug(nome)}-${i}`;
    perfis.push({ nome, id, pasta: encurtar(pasta) });
  }
  return perfis;
}

function lerConfig() {
  if (!fs.existsSync(CONFIG)) return null;
  let cfg;
  try { cfg = JSON.parse(fs.readFileSync(CONFIG, 'utf8').replace(/^﻿/, '')); } catch (e) {
    console.error(`config.json inválido (${e.message}). Corrija ou apague o arquivo para gerar de novo.`);
    process.exit(1);
  }
  const perfis = (Array.isArray(cfg.perfis) ? cfg.perfis : [])
    .filter((p) => p && p.pasta)
    .map((p) => {
      const nome = p.nome || path.basename(expandir(p.pasta));
      return { nome, id: String(p.id || slug(nome)).toLowerCase(), pasta: p.pasta };
    });
  if (!perfis.length) { console.error('config.json não tem nenhum perfil em "perfis".'); process.exit(1); }
  const ids = new Set();
  for (const p of perfis) {
    if (ids.has(p.id)) { console.error(`config.json: o id "${p.id}" aparece em mais de um perfil; cada perfil precisa de um id próprio.`); process.exit(1); }
    ids.add(p.id);
  }
  return perfis;
}

// ---- hooks ----
function nosso(h) {
  // hook deste overlay, instalado desta pasta ou de outra cópia (reconhece pela vizinhança do hook.js)
  if (!h || h.type !== 'command' || !Array.isArray(h.args) || !h.args.length) return false;
  const a = String(h.args[0]);
  if (path.basename(a).toLowerCase() !== 'hook.js') return false;
  return mesmaPasta(a, HOOK) || fs.existsSync(path.join(path.dirname(a), 'overlay.ps1')) || /claude-overlay[\\/]hook\.js$/i.test(a);
}

function aplicarHooks(p) {
  const pasta = expandir(p.pasta);
  const rot = `[${p.nome}]`;
  if (!fs.existsSync(pasta)) { console.log(`${rot} a pasta ${pasta} não existe, pulando`); return; }
  const arquivo = path.join(pasta, 'settings.json');
  let texto = '';
  let settings = {};
  if (fs.existsSync(arquivo)) {
    texto = fs.readFileSync(arquivo, 'utf8');
    try { settings = texto.trim() ? JSON.parse(texto.replace(/^﻿/, '')) : {}; } catch (e) {
      console.error(`${rot} settings.json inválido, não vou mexer: ${e.message}`);
      process.exitCode = 1;
      return;
    }
  } else if (remover) {
    console.log(`${rot} sem settings.json, nada para remover`);
    return;
  }

  const hooks = settings.hooks && typeof settings.hooks === 'object' ? settings.hooks : {};
  let removidos = 0;
  for (const ev of EVENTOS) {
    const antes = Array.isArray(hooks[ev]) ? hooks[ev] : [];
    const semNossos = antes
      .map((grupo) => Object.assign({}, grupo, { hooks: (grupo.hooks || []).filter((h) => { const n = nosso(h); if (n) removidos++; return !n; }) }))
      .filter((grupo) => grupo.hooks.length > 0);
    if (!remover) semNossos.push({ hooks: [{ type: 'command', command: NODE, args: [HOOK, p.id], async: true }] });
    if (semNossos.length) hooks[ev] = semNossos; else delete hooks[ev];
  }
  if (remover && !removidos) { console.log(`${rot} nenhum hook do overlay encontrado`); return; }
  if (Object.keys(hooks).length) settings.hooks = hooks; else delete settings.hooks;

  let bk = '(settings.json novo, sem backup)';
  if (texto) {
    const bkDir = path.join(pasta, 'backups-manual');
    fs.mkdirSync(bkDir, { recursive: true });
    bk = path.join(bkDir, `settings.json.${new Date().toISOString().replace(/[:.]/g, '-')}.bak`);
    fs.writeFileSync(bk, texto);
  }
  const tmp = `${arquivo}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(settings, null, 2) + '\n');
  fs.renameSync(tmp, arquivo);
  JSON.parse(fs.readFileSync(arquivo, 'utf8')); // valida o que ficou gravado
  console.log(`${rot} ${remover ? `${removidos} hooks removidos` : `hooks instalados em ${EVENTOS.length} eventos (id "${p.id}")`} | backup: ${bk}`);
}

// ---- atalhos (via WScript.Shell, pelo PowerShell) ----
function ps(script) {
  return execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script], { encoding: 'utf8' }).trim();
}
function q(s) { return "'" + String(s).replace(/'/g, "''") + "'"; }
function atalhos() {
  const pastas = [['Desktop', 'área de trabalho']];
  if (comWindows || remover) pastas.push(['Startup', 'inicialização do Windows']);
  for (const [pasta, rotulo] of pastas) {
    const script = [
      `$l = Join-Path ([Environment]::GetFolderPath('${pasta}')) 'Claude Overlay.lnk'`,
      '$sh = New-Object -ComObject WScript.Shell',
      remover
        ? `if ((Test-Path -LiteralPath $l) -and ($sh.CreateShortcut($l).Arguments -like ('*' + ${q(VBS)} + '*'))) { Remove-Item -LiteralPath $l; 'removido' } else { 'nada' }`
        : `if (Test-Path -LiteralPath $l) { 'existe' } else { $s = $sh.CreateShortcut($l); $s.TargetPath = (Join-Path $env:WINDIR 'System32\\wscript.exe'); $s.Arguments = '//nologo "' + ${q(VBS)} + '"'; $s.WorkingDirectory = ${q(BASE)}; $s.IconLocation = ${q(ICO)} + ',0'; $s.Description = 'Claude Overlay'; $s.Save(); 'criado' }`,
    ].join('; ');
    try {
      const r = ps(script);
      const msg = { criado: 'atalho criado', existe: 'já existe um atalho "Claude Overlay", mantive o atual', removido: 'atalho removido', nada: 'nenhum atalho deste overlay' }[r] || r;
      console.log(`[atalho] ${rotulo}: ${msg}`);
    } catch (e) {
      console.error(`[atalho] ${rotulo}: falhou (${e.message.split('\n')[0]})`);
    }
  }
}

// ---- principal ----
if (process.platform !== 'win32') { console.error('O Claude Overlay só roda no Windows.'); process.exit(1); }

if (detectar) {
  const perfis = detectarPerfis();
  console.log(perfis.length ? JSON.stringify({ perfis }, null, 2) : 'Nenhuma pasta de perfil do Claude Code encontrada.');
  process.exit(0);
}

let perfis = lerConfig();
if (!perfis) {
  if (remover) { console.error('Sem config.json: não sei de quais perfis remover. Crie o config.json ou rode sem --remover.'); process.exit(1); }
  perfis = detectarPerfis();
  if (!perfis.length) {
    perfis = [{ nome: 'Claude', id: 'claude', pasta: '~/.claude' }];
    console.log('Não encontrei nenhum perfil do Claude Code; vou usar ~/.claude. Abra o Claude Code uma vez e rode de novo se precisar.');
  }
  fs.writeFileSync(CONFIG, JSON.stringify({ perfis }, null, 2) + '\n');
  console.log(`config.json criado com ${perfis.length} perfil(is): ${perfis.map((p) => `${p.nome} (${p.pasta})`).join(', ')}`);
  console.log('Para mudar nomes ou incluir outra pasta, edite o config.json e rode este instalador de novo.');
}

for (const p of perfis) aplicarHooks(p);
if (!semAtalho) atalhos();

if (!remover) {
  console.log('\nPronto. Abra pelo atalho "Claude Overlay" na área de trabalho (ou pelo "Claude Overlay.cmd").');
  console.log('Sessões que já estavam abertas aparecem como "sem sinal" até o próximo evento; se demorar, rode /hooks nelas.');
} else {
  console.log('\nHooks removidos. O config.json e a pasta state/ ficaram; apague a pasta do overlay para limpar tudo.');
}
