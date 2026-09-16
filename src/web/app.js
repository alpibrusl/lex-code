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

async function pollEvents(feedEl) {
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
