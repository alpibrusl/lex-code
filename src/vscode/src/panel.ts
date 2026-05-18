import * as vscode from 'vscode';

type Step = { role: string; content: string };

export class LexCodePanel {
  private readonly _panel: vscode.WebviewPanel;
  private _disposables: vscode.Disposable[] = [];
  private _onDisposeCallback?: () => void;
  private _mode: string;
  private _sessionId: string | null = null;

  constructor(
    context: vscode.ExtensionContext,
    private readonly serverUrl: string,
    private readonly provider: string,
    initialMode: string,
  ) {
    this._mode = initialMode;
    this._panel = vscode.window.createWebviewPanel(
      'lexcode',
      `Lex Code [${initialMode}]`,
      vscode.ViewColumn.Beside,
      { enableScripts: true, retainContextWhenHidden: true },
    );
    this._panel.webview.html = this._getHtml();
    this._panel.webview.onDidReceiveMessage(this._onMessage.bind(this), undefined, this._disposables);
    this._panel.onDidDispose(() => {
      this._disposables.forEach(d => d.dispose());
      this._onDisposeCallback?.();
    }, null, this._disposables);
  }

  setMode(mode: string) {
    this._mode = mode;
    this._panel.title = `Lex Code [${mode}]`;
    this._panel.webview.postMessage({ type: 'modeChanged', mode });
  }

  reveal() { this._panel.reveal(); }
  onDispose(cb: () => void) { this._onDisposeCallback = cb; }
  dispose() { this._panel.dispose(); }

  private async _onMessage(msg: { type: string; text?: string; mode?: string }) {
    if (msg.type === 'send' && msg.text) {
      await this._sendTurn(msg.text);
    } else if (msg.type === 'setMode' && msg.mode) {
      this.setMode(msg.mode);
    }
  }

  private async _sendTurn(text: string) {
    this._panel.webview.postMessage({ type: 'thinking' });
    try {
      const payload: Record<string, unknown> = {
        jsonrpc: '2.0', id: 1,
        method: 'agent/run',
        params: { input: text, mode: this._mode, provider: this.provider, session_id: this._sessionId }
      };
      const resp = await fetch(`${this.serverUrl}/a2a`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const json = await resp.json() as { result?: { session_id: string; steps: Step[] }; error?: { message: string } };
      if (json.error) {
        this._panel.webview.postMessage({ type: 'error', message: json.error.message });
        return;
      }
      if (json.result) {
        this._sessionId = json.result.session_id;
        this._panel.webview.postMessage({ type: 'steps', steps: json.result.steps });
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      this._panel.webview.postMessage({ type: 'error', message: msg });
    }
  }

  private _getHtml(): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lex Code</title>
<style>
  body { font-family: var(--vscode-font-family); font-size: var(--vscode-font-size);
         background: var(--vscode-editor-background); color: var(--vscode-editor-foreground);
         margin: 0; display: flex; flex-direction: column; height: 100vh; }
  #messages { flex: 1; overflow-y: auto; padding: 12px; display: flex; flex-direction: column; gap: 8px; }
  .msg { white-space: pre-wrap; padding: 8px 12px; border-radius: 6px; max-width: 90%; }
  .msg.user   { background: var(--vscode-button-background); color: var(--vscode-button-foreground); align-self: flex-end; }
  .msg.agent  { background: var(--vscode-editorWidget-background); align-self: flex-start; }
  .msg.tool   { font-family: monospace; font-size: 0.85em; background: var(--vscode-terminal-background); align-self: flex-start; }
  .msg.error  { background: var(--vscode-inputValidation-errorBackground); }
  .thinking   { opacity: 0.6; font-style: italic; }
  #footer { display: flex; gap: 8px; padding: 8px; border-top: 1px solid var(--vscode-panel-border); }
  #input  { flex: 1; background: var(--vscode-input-background); color: var(--vscode-input-foreground);
            border: 1px solid var(--vscode-input-border); border-radius: 4px; padding: 6px 10px; }
  #send   { background: var(--vscode-button-background); color: var(--vscode-button-foreground);
            border: none; border-radius: 4px; padding: 6px 14px; cursor: pointer; }
  #mode-select { background: var(--vscode-dropdown-background); color: var(--vscode-dropdown-foreground);
                 border: 1px solid var(--vscode-dropdown-border); border-radius: 4px; padding: 4px 8px; }
</style>
</head>
<body>
<div id="messages"></div>
<div id="footer">
  <select id="mode-select">
    <option value="build">Build</option>
    <option value="plan">Plan</option>
    <option value="explore">Explore</option>
    <option value="refactor">Refactor</option>
    <option value="spec">Spec</option>
    <option value="test">Test</option>
    <option value="review">Review</option>
  </select>
  <input id="input" type="text" placeholder="Ask lex-code…" />
  <button id="send">Send</button>
</div>
<script>
  const vscode = acquireVsCodeApi();
  const messages = document.getElementById('messages');
  const input    = document.getElementById('input');
  const sendBtn  = document.getElementById('send');
  const modeSelect = document.getElementById('mode-select');

  function addMsg(cls, text) {
    const d = document.createElement('div');
    d.className = 'msg ' + cls;
    d.textContent = text;
    messages.appendChild(d);
    messages.scrollTop = messages.scrollHeight;
    return d;
  }

  let thinkingEl = null;

  window.addEventListener('message', e => {
    const m = e.data;
    if (m.type === 'thinking') {
      thinkingEl = addMsg('agent thinking', 'Thinking…');
    } else if (m.type === 'steps') {
      thinkingEl?.remove(); thinkingEl = null;
      m.steps.forEach(s => addMsg(s.role === 'user' ? 'user' : s.role === 'tool' ? 'tool' : 'agent', s.content));
    } else if (m.type === 'error') {
      thinkingEl?.remove(); thinkingEl = null;
      addMsg('error', 'Error: ' + m.message);
    } else if (m.type === 'modeChanged') {
      modeSelect.value = m.mode;
    }
  });

  sendBtn.addEventListener('click', send);
  input.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); } });
  modeSelect.addEventListener('change', () => { vscode.postMessage({ type: 'setMode', mode: modeSelect.value }); });

  function send() {
    const text = input.value.trim();
    if (!text) return;
    input.value = '';
    addMsg('user', text);
    vscode.postMessage({ type: 'send', text });
  }
</script>
</body>
</html>`;
  }
}
