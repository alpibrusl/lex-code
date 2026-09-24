// Default to the page's own origin so the UI works on whatever host/port
// it was actually served from (a hardcoded :7700 broke every fetch when the
// server ran on any other port — the watch feed and /a2a silently 404'd/
// connection-refused). Override with window.LEX_SERVER_URL only for a
// genuinely cross-origin backend.
const SERVER_URL = window.LEX_SERVER_URL || location.origin;

const messagesEl   = document.getElementById('messages');
const inputEl      = document.getElementById('input');
const sendBtn      = document.getElementById('send-btn');
const modeSelect   = document.getElementById('mode-select');
const provSelect   = document.getElementById('provider-select');
const modelInput   = document.getElementById('model-input');
const clearBtn     = document.getElementById('clear-btn');
const sessionListEl = document.getElementById('session-list');
const newSessionBtn = document.getElementById('new-session-btn');
const tabButtons    = document.querySelectorAll('.tab-btn');
const tabPanels = {
  chat:   document.getElementById('chat-panel'),
  trail:  document.getElementById('trail-panel'),
  memory: document.getElementById('memory-panel'),
};
const trailListEl      = document.getElementById('trail-list');
const trailRefreshBtn  = document.getElementById('trail-refresh-btn');
const memoryListEl     = document.getElementById('memory-list');
const memoryRefreshBtn = document.getElementById('memory-refresh-btn');
let activeTab = 'chat';

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

// Assistant text is the one thing worth spending Markdown on — the model
// writes code fences, bold, lists; user input and raw tool output are
// shown verbatim (`textContent` is already safe against injection, and
// re-rendering a shell command's stdout as Markdown would just garble it).
function addMsg(cls, text) {
  const el = document.createElement('div');
  el.className = 'msg ' + cls;
  if (cls === 'agent' && window.renderMarkdown) {
    el.innerHTML = window.renderMarkdown(text);
  } else {
    el.textContent = text;
  }
  messagesEl.appendChild(el);
  messagesEl.scrollTop = messagesEl.scrollHeight;
  return el;
}

function setMode(m) {
  modeSelect.value = m;
  document.title = `lex-code [${m}]`;
}

// Placeholder only — shown so the field isn't a blank guessing game, not a
// claim that this exact model is pulled/available. Matches each provider's
// own hardcoded default (src/agents/*.lex, src/tools/index.lex); left blank,
// the backend uses that default itself.
const DEFAULT_MODEL_BY_PROVIDER = {
  opencode:  'kimi-k3',
  ollama:    'qwen3.8:27b-mlx',
  anthropic: 'claude-sonnet-5',
  openai:    'gpt-4o',
  mistral:   'mistral-large-latest',
  google:    'gemini-2.5-pro',
};

function updateModelPlaceholder() {
  modelInput.placeholder = DEFAULT_MODEL_BY_PROVIDER[provSelect.value] || 'default';
}

provSelect.addEventListener('change', () => {
  modelInput.value = '';
  updateModelPlaceholder();
});
updateModelPlaceholder();

function startNewSession() {
  messagesEl.innerHTML = '';
  sessionId = randHex(8);
  lastSeq = 0;
  highlightActiveSession(sessionId);
  if (activeTab === 'trail') loadTrail();
}

clearBtn.addEventListener('click', startNewSession);
newSessionBtn.addEventListener('click', startNewSession);

modeSelect.addEventListener('change', () => setMode(modeSelect.value));

// ── Session sidebar ──────────────────────────────────────────────────────────
// `GET /sessions` lists every session with at least one message, newest
// first (see persist.recent_sessions / web.lex handle_sessions) — a
// session with no messages yet isn't in it, including a brand-new one
// nobody has sent anything to.
function timeAgo(ts) {
  const s = Math.max(0, Math.floor((Date.now() - ts) / 1000));
  if (s < 60) return 'just now';
  const m = Math.floor(s / 60);
  if (m < 60) return m + 'm ago';
  const h = Math.floor(m / 60);
  if (h < 24) return h + 'h ago';
  return Math.floor(h / 24) + 'd ago';
}

function highlightActiveSession(id) {
  for (const el of sessionListEl.querySelectorAll('.session-item')) {
    el.classList.toggle('active', el.dataset.id === id);
  }
}

async function loadSessions() {
  try {
    const r = await fetch(`${SERVER_URL}/sessions`);
    const j = await r.json();
    const sessions = j.sessions || [];
    sessionListEl.innerHTML = '';
    if (sessions.length === 0) {
      const el = document.createElement('div');
      el.className = 'session-empty';
      el.textContent = 'No sessions yet';
      sessionListEl.appendChild(el);
      return;
    }
    for (const s of sessions) {
      const el = document.createElement('div');
      el.className = 'session-item';
      el.dataset.id = s.id;
      const title = document.createElement('div');
      title.className = 'session-title';
      title.textContent = s.title;
      const time = document.createElement('div');
      time.className = 'session-time';
      time.textContent = timeAgo(s.last_ts);
      el.appendChild(title);
      el.appendChild(time);
      el.addEventListener('click', () => switchToSession(s.id));
      sessionListEl.appendChild(el);
    }
    highlightActiveSession(sessionId);
  } catch (e) {
    // transient — the sidebar just stays as it was
  }
}

// Load a past session into the chat pane and keep going in it: not a
// read-only watch (that's `?watch=<id>`, a different visitor entirely) —
// this is *your own* browser resuming a conversation you already had.
// Backfilling replays its whole trail from seq 0 through the same
// `pollEvents(feedEl, true)` watch mode already uses for exactly this
// (tool feed + message bubbles from one pass), so there's one rendering
// path for "everything that happened in a session", not two.
async function switchToSession(id) {
  if (busy) return;
  sessionId = id;
  lastSeq = 0;
  messagesEl.innerHTML = '';
  const feedEl = document.createElement('div');
  feedEl.className = 'feed';
  messagesEl.appendChild(feedEl);
  // /events caps a single response at 300 rows (see web.lex's query), so
  // a session longer than that needs more than one fetch to reach the
  // end — keep polling until a round trip stops moving the cursor.
  let before;
  do {
    before = lastSeq;
    await pollEvents(feedEl, true);
  } while (lastSeq > before);
  highlightActiveSession(id);
  if (activeTab === 'trail') loadTrail();
}

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
      // A write/edit carries its own before/after in `diff` (set only on
      // the cap.invoked event — see write_edit_diff_json in web.lex) —
      // show the actual change instead of a bare "▶ write" line. A later
      // cap.failed for the same call still falls through to the plain
      // ✗ line below, so a failed write is never silently shown as if it
      // landed.
      if (ev.diff) {
        const el = document.createElement('div');
        el.className = 'ev ev-diff';
        el.innerHTML = window.renderDiffBlock(ev.diff);
        feedEl.appendChild(el);
        continue;
      }
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
        model: modelInput.value.trim(),
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
    // A brand-new session has no title (no message yet) until now, and any
    // session's "last active" time moves on every turn — refresh the list
    // rather than wait for whatever triggers the next natural reload.
    loadSessions();
  }
}

sendBtn.addEventListener('click', send);
inputEl.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
});

setMode(modeSelect.value);

// ── Tabs — Chat / Trail / Memory ─────────────────────────────────────────────
function switchTab(name) {
  activeTab = name;
  for (const btn of tabButtons) btn.classList.toggle('active', btn.dataset.tab === name);
  for (const [k, el] of Object.entries(tabPanels)) el.classList.toggle('active', k === name);
  if (name === 'trail') loadTrail();
  if (name === 'memory') loadMemory();
}

for (const btn of tabButtons) {
  btn.addEventListener('click', () => switchTab(btn.dataset.tab));
}

// ── Trail tab — every event for the selected session, every kind ────────────
// Unlike the live tool feed (which only ever shows cap.invoked/completed/
// failed), this is a full, after-the-fact view: every row the session's
// trail log holds, in order. `/events` still caps a single response at 300
// rows, so a longer session needs the same paging loop `switchToSession`
// already uses.
function trailRowDetail(ev) {
  if (ev.diff) return { html: window.renderDiffBlock(ev.diff) };
  if (ev.label) return { text: ev.label };
  if (ev.payload) {
    // `payload` is the raw trail payload as a JSON *string* (see
    // event_to_json in web.lex — it's not reliably valid JSON on its own,
    // so the server always wraps it as a string). Pretty-print it when it
    // itself parses as JSON; otherwise show it verbatim.
    try {
      return { text: JSON.stringify(JSON.parse(ev.payload), null, 2) };
    } catch (e) {
      return { text: ev.payload };
    }
  }
  return { text: '' };
}

async function loadTrail() {
  trailListEl.innerHTML = '';
  let after = 0;
  let rows = [];
  for (;;) {
    let j;
    try {
      const r = await fetch(`${SERVER_URL}/events?session=${sessionId}&after=${after}`);
      j = await r.json();
    } catch (e) {
      break; // transient — show what we already have
    }
    rows = rows.concat(j.events || []);
    const next = typeof j.last === 'number' ? j.last : after;
    if (next <= after) break;
    after = next;
  }
  if (rows.length === 0) {
    const el = document.createElement('div');
    el.className = 'trail-empty';
    el.textContent = 'No trail events for this session yet';
    trailListEl.appendChild(el);
    return;
  }
  for (const ev of rows) {
    const row = document.createElement('div');
    row.className = 'trail-row';
    const seq = document.createElement('span');
    seq.className = 'trail-seq';
    seq.textContent = '#' + ev.seq;
    const ts = document.createElement('span');
    ts.className = 'trail-ts';
    ts.textContent = ev.ts ? new Date(ev.ts).toLocaleTimeString() : '';
    const kind = document.createElement('span');
    kind.className = 'trail-kind';
    kind.textContent = ev.kind || '?';
    const detail = document.createElement('span');
    detail.className = 'trail-detail';
    const d = trailRowDetail(ev);
    if (d.html) { detail.innerHTML = d.html; } else { detail.textContent = d.text; }
    row.appendChild(seq);
    row.appendChild(ts);
    row.appendChild(kind);
    row.appendChild(detail);
    trailListEl.appendChild(row);
  }
}

trailRefreshBtn.addEventListener('click', loadTrail);

// ── Memory tab — everything in .lex/project_memory.db ────────────────────────
// Project-scoped, not session-scoped: the same list regardless of which
// session is selected in the sidebar (see GET /memory / project_memory.lex).
const MEMORY_KIND_ORDER = ['convention', 'tech_stack', 'known_issue', 'recent_change'];
const MEMORY_KIND_LABEL = {
  convention: 'Conventions',
  tech_stack: 'Tech stack',
  known_issue: 'Known issues',
  recent_change: 'Recent changes',
};

async function loadMemory() {
  memoryListEl.innerHTML = '';
  let entries = [];
  try {
    const r = await fetch(`${SERVER_URL}/memory`);
    const j = await r.json();
    entries = j.entries || [];
  } catch (e) {
    // transient — leave the panel empty rather than throw
  }
  if (entries.length === 0) {
    const el = document.createElement('div');
    el.className = 'memory-empty';
    el.textContent = 'No project memory stored yet';
    memoryListEl.appendChild(el);
    return;
  }
  const byKind = new Map();
  for (const e of entries) {
    if (!byKind.has(e.kind)) byKind.set(e.kind, []);
    byKind.get(e.kind).push(e);
  }
  const kinds = [...byKind.keys()].sort((a, b) => {
    const ai = MEMORY_KIND_ORDER.indexOf(a);
    const bi = MEMORY_KIND_ORDER.indexOf(b);
    if (ai === -1 && bi === -1) return a.localeCompare(b);
    if (ai === -1) return 1;
    if (bi === -1) return -1;
    return ai - bi;
  });
  for (const kind of kinds) {
    const header = document.createElement('div');
    header.className = 'memory-group-header';
    header.textContent = MEMORY_KIND_LABEL[kind] || kind;
    memoryListEl.appendChild(header);
    for (const e of byKind.get(kind)) {
      const el = document.createElement('div');
      el.className = 'memory-entry';
      if (e.key) {
        const key = document.createElement('div');
        key.className = 'memory-entry-key';
        key.textContent = e.key;
        el.appendChild(key);
      }
      const content = document.createElement('div');
      content.className = 'memory-entry-content';
      content.textContent = e.content;
      el.appendChild(content);
      const metaParts = [e.ts, e.importance].filter(Boolean);
      if (metaParts.length > 0) {
        const meta = document.createElement('div');
        meta.className = 'memory-entry-meta';
        meta.textContent = metaParts.join(' · ');
        el.appendChild(meta);
      }
      memoryListEl.appendChild(el);
    }
  }
}

memoryRefreshBtn.addEventListener('click', loadMemory);

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
  // A watch link is a link to ONE session, not an invitation to browse
  // every other conversation on this server — the sidebar (and its
  // /sessions fetch) stays off entirely for a watcher.
  document.getElementById('sidebar').style.display = 'none';
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
if (_watch) {
  startWatch(_watch);
} else {
  loadSessions();
}
