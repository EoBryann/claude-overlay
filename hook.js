#!/usr/bin/env node
'use strict';
// Claude Overlay - coletor de eventos dos hooks do Claude Code.
// Uso (instalado pelo instalar.js no settings.json de cada perfil, forma exec):  node hook.js <id-do-perfil>
// Le o JSON do evento no stdin e grava <pasta do overlay>/state/<perfil>/<session_id>.json
// Nunca escreve no stdout (stdout de hook vira contexto/mensagem no Claude) e sempre sai com 0.

const fs = require('fs');
const path = require('path');

const perfil = String(process.argv[2] || 'desconhecido').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'desconhecido';
const base = __dirname;
const dir = path.join(base, 'state', perfil);
const logPath = path.join(base, 'hook.log');

function log(msg) {
  try { fs.appendFileSync(logPath, `${new Date().toISOString()} [${perfil}] ${msg}\n`); } catch (_) {}
}
function snippet(s, n) {
  if (s === undefined || s === null) return '';
  return String(s).replace(/\s+/g, ' ').trim().slice(0, n);
}
function readState(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return {}; }
}
function writeState(file, obj) {
  fs.mkdirSync(dir, { recursive: true });
  const dados = JSON.stringify(obj);
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, dados);
  // No Windows o rename falha com EPERM quando outro processo esta com o destino aberto
  // (outro hook da mesma sessao, a janela lendo, ou o antivirus). Tenta de novo em vez de perder o evento.
  for (let i = 0; i < 6; i++) {
    try { fs.renameSync(tmp, file); return; } catch (e) {
      if (e.code !== 'EPERM' && e.code !== 'EACCES' && e.code !== 'EBUSY') { try { fs.unlinkSync(tmp); } catch (_) {} throw e; }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 20 * (i + 1)); // pausa curta sem async
    }
  }
  // Ultimo recurso: grava por cima (nao atomico, mas melhor que descartar o estado)
  try { fs.writeFileSync(file, dados); } finally { try { fs.unlinkSync(tmp); } catch (_) {} }
}
function prune() {
  // apaga estados com mais de 3 dias (sessoes mortas ha muito tempo)
  try {
    const limite = Date.now() - 3 * 24 * 3600 * 1000;
    for (const f of fs.readdirSync(dir)) {
      const full = path.join(dir, f);
      // .tmp orfao de processo morto: apaga depois de 1 min
      if (f.endsWith('.tmp')) {
        try { if (fs.statSync(full).mtimeMs < Date.now() - 60000) fs.unlinkSync(full); } catch (_) {}
        continue;
      }
      if (!f.endsWith('.json')) continue;
      try { if (fs.statSync(full).mtimeMs < limite) fs.unlinkSync(full); } catch (_) {}
    }
  } catch (_) {}
}
function resumoTool(p) {
  const t = p.tool_name || 'ferramenta';
  const i = p.tool_input || {};
  let alvo = '';
  if (i.command) alvo = i.command;
  else if (i.file_path) alvo = path.basename(String(i.file_path));
  else if (i.pattern) alvo = i.pattern;
  else if (i.description) alvo = i.description;
  else if (i.url) alvo = i.url;
  else if (i.skill) alvo = i.skill;
  else if (i.prompt) alvo = i.prompt;
  const pref = p.agent_id ? '[sub] ' : '';
  return snippet(pref + t + (alvo ? ': ' + alvo : ''), 140);
}

function handle(p) {
  const sid = p.session_id;
  if (!sid) return;
  const ev = p.hook_event_name || '';
  const file = path.join(dir, `${sid}.json`);
  const prev = readState(file);
  const now = Date.now();
  const st = Object.assign({}, prev, {
    sessionId: sid,
    perfil,
    cwd: p.cwd || prev.cwd || '',
    transcript: p.transcript_path || prev.transcript || '',
    event: ev,
    at: now,
    subagents: prev.subagents || 0,
  });

  switch (ev) {
    case 'SessionStart':
      if (p.source === 'compact') { st.at = prev.at || now; break; } // compactar nao muda o estado
      st.state = 'idle'; st.detail = `sessão iniciada (${p.source || 'startup'})`; st.subagents = 0;
      break;
    case 'UserPromptSubmit':
      st.state = 'working'; st.prompt = snippet(p.prompt, 160); st.detail = st.prompt || 'trabalhando';
      st.subagents = 0; st.promptAt = now;
      break;
    case 'PreToolUse':
      st.state = 'working'; st.detail = resumoTool(p); st.tool = p.tool_name || '';
      break;
    case 'SubagentStart':
      st.subagents = (prev.subagents || 0) + 1; st.state = 'working'; st.lastAgent = p.agent_type || '';
      st.detail = `subagente ${p.agent_type || ''} iniciado`.trim();
      break;
    case 'SubagentStop':
      st.subagents = Math.max(0, (prev.subagents || 0) - 1);
      st.state = prev.state || 'working'; st.detail = prev.detail || '';
      break;
    case 'Notification': {
      const t = p.notification_type || '';
      if (t === 'permission_prompt') {
        st.state = 'permission'; st.detail = snippet(p.message, 160) || 'pede permissão';
      } else if (t === 'idle_prompt') {
        // ja respondeu (ou ja esta marcado como esperando): nao mexe no estado nem no horario,
        // senao cada repeticao do idle_prompt viraria um toast novo
        if (prev.state === 'done' || prev.state === 'needs_input') { st.state = prev.state; st.detail = prev.detail; st.at = prev.at || now; }
        else { st.state = 'needs_input'; st.detail = snippet(p.message, 160) || 'esperando você'; }
      } else if (t === 'agent_needs_input' || t.startsWith('elicitation')) {
        st.state = 'needs_input'; st.detail = snippet(p.message, 160) || 'esperando você';
      } else if (t === 'agent_completed') {
        st.state = 'done'; st.detail = snippet(p.message, 200) || 'terminou';
      } else {
        st.state = prev.state; st.detail = prev.detail; st.at = prev.at || now; // auth_success, quota_* etc.
      }
      break;
    }
    case 'Stop':
      st.state = 'done'; st.detail = snippet(p.last_assistant_message, 200) || 'respondeu';
      st.subagents = 0; st.doneAt = now;
      break;
    case 'SessionEnd':
      st.state = 'ended'; st.detail = `sessão encerrada (${p.reason || ''})`;
      break;
    default:
      st.state = prev.state; st.detail = prev.detail; st.at = prev.at || now;
  }
  writeState(file, st);
  if (Math.random() < 0.05) prune();
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  try { handle(JSON.parse(raw)); } catch (e) { log('erro: ' + ((e && e.stack) || e)); }
  process.exit(0);
});
process.stdin.on('error', () => process.exit(0));
setTimeout(() => process.exit(0), 4000).unref();
