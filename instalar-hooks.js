#!/usr/bin/env node
'use strict';
// Instala (ou remove, com --remover) os hooks do Claude Overlay nos dois perfis do Claude Code.
// Faz backup de cada settings.json em <perfil>/backups-manual/ antes de gravar.
// Uso:  node instalar-hooks.js          |  node instalar-hooks.js --remover

const fs = require('fs');
const path = require('path');
const os = require('os');

const remover = process.argv.includes('--remover');
const NODE = process.execPath;
const HOOK = path.join(__dirname, 'hook.js');
const EVENTOS = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'SubagentStart', 'SubagentStop', 'Notification', 'Stop', 'SessionEnd'];
const PERFIS = [
  { chave: 'empresa', cfg: path.join(os.homedir(), '.claude-empresa') },
  { chave: 'pessoal', cfg: path.join(os.homedir(), '.claude') },
];

function nosso(h) {
  return h && h.type === 'command' && Array.isArray(h.args) && h.args.some((a) => /claude-overlay[\\/]hook\.js$/i.test(String(a)));
}

for (const p of PERFIS) {
  const arquivo = path.join(p.cfg, 'settings.json');
  if (!fs.existsSync(arquivo)) { console.log(`[${p.chave}] sem settings.json em ${p.cfg}, pulando`); continue; }
  const texto = fs.readFileSync(arquivo, 'utf8');
  let settings;
  try { settings = JSON.parse(texto); } catch (e) { console.error(`[${p.chave}] settings.json inválido, não vou tocar: ${e.message}`); process.exitCode = 1; continue; }

  const bkDir = path.join(p.cfg, 'backups-manual');
  fs.mkdirSync(bkDir, { recursive: true });
  const bk = path.join(bkDir, `settings.json.${new Date().toISOString().replace(/[:.]/g, '-')}.bak`);
  fs.writeFileSync(bk, texto);

  const hooks = settings.hooks && typeof settings.hooks === 'object' ? settings.hooks : {};
  let adicionados = 0, removidos = 0;
  for (const ev of EVENTOS) {
    const antes = Array.isArray(hooks[ev]) ? hooks[ev] : [];
    const semNossos = antes
      .map((grupo) => Object.assign({}, grupo, { hooks: (grupo.hooks || []).filter((h) => { const n = nosso(h); if (n) removidos++; return !n; }) }))
      .filter((grupo) => grupo.hooks.length > 0);
    if (!remover) {
      semNossos.push({ hooks: [{ type: 'command', command: NODE, args: [HOOK, p.chave], async: true }] });
      adicionados++;
    }
    if (semNossos.length) hooks[ev] = semNossos; else delete hooks[ev];
  }
  if (Object.keys(hooks).length) settings.hooks = hooks; else delete settings.hooks;

  const tmp = `${arquivo}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(settings, null, 2) + '\n');
  fs.renameSync(tmp, arquivo);
  JSON.parse(fs.readFileSync(arquivo, 'utf8')); // valida
  console.log(`[${p.chave}] ${remover ? 'removidos ' + removidos : 'instalados ' + adicionados + ' eventos'} | backup: ${bk}`);
}
