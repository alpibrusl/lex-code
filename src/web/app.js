const SERVER_URL = window.LEX_SERVER_URL || 'http://localhost:7700';

const messagesEl   = document.getElementById('messages');
const inputEl      = document.getElementById('input');
const sendBtn      = document.getElementById('send-btn');
const modeSelect   = document.getElementById('mode-select');
const provSelect   = document.getElementById('provider-select');
const clearBtn     = document.getElementById('clear-btn');

let sessionId = null;
let busy = false;

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
  sessionId = null;
});

modeSelect.addEventListener('change', () => setMode(modeSelect.value));

async function send() {
  if (busy) return;
  const text = inputEl.value.trim();
  if (!text) return;
  inputEl.value = '';
  addMsg('user', text);

  busy = true;
  sendBtn.disabled = true;
  const thinkEl = document.createElement('div');
  thinkEl.className = 'thinking';
  thinkEl.textContent = 'Thinking…';
  messagesEl.appendChild(thinkEl);
  messagesEl.scrollTop = messagesEl.scrollHeight;

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
    thinkEl.remove();
    if (json.error) {
      addMsg('error', 'Error: ' + json.error.message);
    } else if (json.result) {
      sessionId = json.result.session_id;
      for (const step of json.result.steps) {
        const cls = step.role === 'user' ? 'user' : step.role === 'tool' ? 'tool' : 'agent';
        addMsg(cls, step.content);
      }
    }
  } catch (err) {
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
