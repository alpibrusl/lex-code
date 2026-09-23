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
const clearBtn     = document.getElementById('clear-btn');
const sessionListEl = document.getElementById('session-list');
const newSessionBtn = document.getElementById('new-session-btn');

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

function startNewSession() {
  messagesEl.innerHTML = '';
  sessionId = randHex(8);
  lastSeq = 0;
  highlightActiveSession(sessionId);
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
