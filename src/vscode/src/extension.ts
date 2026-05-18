import * as vscode from 'vscode';
import { LexCodePanel } from './panel';

let panel: LexCodePanel | undefined;

export function activate(context: vscode.ExtensionContext) {
  const cfg = () => vscode.workspace.getConfiguration('lexcode');

  const openPanel = (mode?: string) => {
    const serverUrl = cfg().get<string>('serverUrl', 'http://localhost:7700');
    const provider  = cfg().get<string>('provider',  'anthropic');
    const m         = mode ?? cfg().get<string>('defaultMode', 'build');
    if (panel) {
      panel.setMode(m);
      panel.reveal();
    } else {
      panel = new LexCodePanel(context, serverUrl, provider, m);
      panel.onDispose(() => { panel = undefined; });
    }
  };

  context.subscriptions.push(
    vscode.commands.registerCommand('lexcode.openPanel',    () => openPanel()),
    vscode.commands.registerCommand('lexcode.buildMode',    () => openPanel('build')),
    vscode.commands.registerCommand('lexcode.planMode',     () => openPanel('plan')),
    vscode.commands.registerCommand('lexcode.refactorMode', () => openPanel('refactor')),
    vscode.commands.registerCommand('lexcode.specMode',     () => openPanel('spec')),
    vscode.commands.registerCommand('lexcode.testMode',     () => openPanel('test')),
    vscode.commands.registerCommand('lexcode.reviewMode',   () => openPanel('review')),
  );
}

export function deactivate() {
  panel?.dispose();
}
