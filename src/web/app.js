const SERVER_URL = window.LEX_SERVER_URL || 'http://localhost:7700';

const messagesEl   = document.getElementById('messages');
const inputEl      = document.getElementById('input');
const sendBtn      = document.getElementById('send-btn');
const modeSelect   = document.getElementById('mode-select');
const provSelect   = document.getElementById('provider-select');
const clearBtn     = document.getElementById('clear-btn');

// A client-chosen session id lets us tail the run's trail live: the server
// persists this turn's events to .lex/sessions/<id>.db, and GET /events
// streams them back tool-by-tool while /a2a is still running.
function randHex(n) {
  const a = new Uint8Array(n);
  crypto.getRandomValues(a);
  return [...a].map(b => b.toString(16).padStart(2, '0')).join('');
}

let sessionId = randHex(8);
let busy = false;
let lastSeq = 0;   // trail cursor (monotonic rowid); persists across turns

function addMsg(cls, text) {
  const el = document.createElement('div');
  el.className = 'msg ' + cls;
  el.textContent = text;
  messagesEl.appendChild(el);
  messagesEl.scrollTop = messagesEl.scrollHeight;
  return el;
}

function setMode(m) {
  modeSelect.value = m;
  document.title = `lex-code [${m}]`;
}

clearBtn.addEventListener('click', () => {
  messagesEl.innerHTML = '';
  sessionId = randHex(8);
  lastSeq = 0;
});

modeSelect.addEventListener('change', () => setMode(modeSelect.value));

// Map a trail event to a one-line live-feed label, or null to ignore it.
function eventLine(ev) {
  if (ev.kind === 'cap.invoked')   return '▶ ' + (ev.label || 'tool');
  if (ev.kind === 'cap.completed') return '✓ ' + (ev.label || 'tool');
  if (ev.kind === 'cap.failed')    return '✗ ' + (ev.label || 'tool');
  return null;
}

// Poll new trail events. Always renders the tool feed into `feedEl`; when
// `withMessages` is set (watch mode), also renders user/assistant message
// events as chat bubbles — in a normal turn the messages come from the
// /a2a result instead, so they'd double up.
async function pollEvents(feedEl, withMessages) {
  try {
    const r = await fetch(`${SERVER_URL}/events?session=${sessionId}&after=${lastSeq}`);
    const j = await r.json();
    if (typeof j.last === 'number' && j.last > lastSeq) lastSeq = j.last;
    for (const ev of (j.events || [])) {
      const line = eventLine(ev);
      if (line) {
        const el = document.createElement('div');
        el.className = 'ev ' + ev.kind.replace(/\./g, '-');
        el.textContent = line;
        feedEl.appendChild(el);
      } else if (withMessages && ev.kind && ev.kind.endsWith('_message') && ev.label) {
        addMsg(ev.kind.indexOf('user') >= 0 ? 'user' : 'agent', ev.label);
      }
    }
    messagesEl.scrollTop = messagesEl.scrollHeight;
  } catch (e) {
    // transient (e.g. the writer briefly holds the db) — retry next tick
  }
}

async function send() {
  if (busy) return;
  const text = inputEl.value.trim();
  if (!text) return;
  inputEl.value = '';
  addMsg('user', text);

  busy = true;
  sendBtn.disabled = true;

  const feedEl = document.createElement('div');
  feedEl.className = 'feed';
  messagesEl.appendChild(feedEl);

  const thinkEl = document.createElement('div');
  thinkEl.className = 'thinking';
  thinkEl.textContent = 'Working…';
  messagesEl.appendChild(thinkEl);
  messagesEl.scrollTop = messagesEl.scrollHeight;

  // Live-tail the trail while the turn runs.
  const timer = setInterval(() => pollEvents(feedEl), 400);

  try {
    const payload = {
      jsonrpc: '2.0', id: Date.now(),
      method: 'agent/run',
      params: {
        input: text,
        mode: modeSelect.value,
        provider: provSelect.value,
        session_id: sessionId
      }
    };
    const resp = await fetch(`${SERVER_URL}/a2a`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const json = await resp.json();
    await pollEvents(feedEl);   // final catch-up so nothing is missed
    clearInterval(timer);
    thinkEl.remove();
    if (json.error) {
      addMsg('error', 'Error: ' + json.error.message);
    } else if (json.result) {
      sessionId = json.result.session_id || sessionId;
      for (const step of json.result.steps) {
        const cls = step.role === 'user' ? 'user' : step.role === 'tool' ? 'tool' : 'agent';
        addMsg(cls, step.content);
      }
    }
  } catch (err) {
    clearInterval(timer);
    thinkEl.remove();
    addMsg('error', 'Network error: ' + err.message);
  } finally {
    busy = false;
    sendBtn.disabled = false;
    inputEl.focus();
  }
}

sendBtn.addEventListener('click', send);
inputEl.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
});

setMode(modeSelect.value);

// ── Watch mode ──────────────────────────────────────────────────────────────
// `?watch=<session-id>` (or `#watch=<id>`) attaches read-only to a session
// someone else is driving — e.g. a run Claude is handling — and live-tails its
// trail: the tool feed plus the conversation, no input of its own.
function watchSessionId() {
  const q = new URLSearchParams(location.search).get('watch');
  if (q) return q;
  const m = location.hash.match(/watch=([0-9a-f]+)/);
  return m ? m[1] : null;
}

function startWatch(sid) {
  sessionId = sid;
  lastSeq = 0;
  // read-only: no sending
  inputEl.disabled = true;
  inputEl.placeholder = 'watching a live session — read only';
  sendBtn.disabled = true;
  const banner = document.createElement('div');
  banner.className = 'watch-banner';
  banner.textContent = '👁 Watching session ' + sid + ' — live';
  document.getElementById('app').insertBefore(banner, messagesEl);
  const feedEl = document.createElement('div');
  feedEl.className = 'feed';
  messagesEl.appendChild(feedEl);
  setInterval(() => pollEvents(feedEl, true), 1000);
  pollEvents(feedEl, true);
}

const _watch = watchSessionId();
if (_watch) startWatch(_watch);
