// Turn a write/edit event's before/after text into a rendered diff block.
//
// `write` has no "before" — it's rendered as a block of pure additions.
// `edit` gets an actual line diff, via the standard LCS-backtrack
// technique: build the table of longest-common-subsequence lengths
// between the old and new lines, then walk it backwards to recover which
// lines are shared, added, or removed. O(n*m) time and space, which is
// fine for a source file but not for something huge — MAX_DIFF_LINES
// below is the same kind of honest cap this codebase already uses
// elsewhere (bar_check's 60-pair sample, semantic_search's index cap):
// past it, this shows a plain before/after instead of freezing the tab
// on a multi-megabyte file.

const MAX_DIFF_LINES = 2000;

function splitLines(s) {
  if (s === '') return [];
  return String(s).replace(/\r\n/g, '\n').replace(/\n$/, '').split('\n');
}

// The LCS-length table for `a` (rows) against `b` (cols), 1-indexed with
// a leading zero row/column — the standard shape for backtracking.
function lcsTable(a, b) {
  const n = a.length, m = b.length;
  const table = new Array(n + 1);
  for (let i = 0; i <= n; i++) table[i] = new Array(m + 1).fill(0);
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      table[i][j] = a[i - 1] === b[j - 1]
        ? table[i - 1][j - 1] + 1
        : Math.max(table[i - 1][j], table[i][j - 1]);
    }
  }
  return table;
}

// Walk the table from (n, m) back to (0, 0): an equal cell (a match)
// moves diagonally, otherwise the direction with the larger LCS value
// wins and produces a remove (from a) or an add (from b). Built backward,
// so the result is reversed once at the end — and the tie-break (`>`, not
// `>=`) matters for exactly that reason: preferring the "add" branch on a
// plateau puts removals before additions once reversed, the ordering a
// unified diff normally reads as ("this line changed to that one"),
// instead of the arbitrary-looking add-then-remove `>=` produced.
function backtrackDiff(a, b, table) {
  const ops = [];
  let i = a.length, j = b.length;
  while (i > 0 && j > 0) {
    if (a[i - 1] === b[j - 1]) {
      ops.push({ type: 'equal', line: a[i - 1] });
      i--; j--;
    } else if (table[i - 1][j] > table[i][j - 1]) {
      ops.push({ type: 'remove', line: a[i - 1] });
      i--;
    } else {
      ops.push({ type: 'add', line: b[j - 1] });
      j--;
    }
  }
  while (i > 0) { ops.push({ type: 'remove', line: a[i - 1] }); i--; }
  while (j > 0) { ops.push({ type: 'add', line: b[j - 1] }); j--; }
  ops.reverse();
  return ops;
}

// oldStr/newStr -> [{type, line}], or null when the input is past
// MAX_DIFF_LINES (the caller falls back to a plain before/after render).
function computeLineDiff(oldStr, newStr) {
  const a = splitLines(oldStr), b = splitLines(newStr);
  if (a.length > MAX_DIFF_LINES || b.length > MAX_DIFF_LINES) return null;
  return backtrackDiff(a, b, lcsTable(a, b));
}

function langOfPath(path) {
  const m = /\.([a-zA-Z0-9]+)$/.exec(path || '');
  if (!m) return '';
  const ext = m[1].toLowerCase();
  if (ext === 'lex') return 'lex';
  if (ext === 'json') return 'json';
  return '';
}

function highlightLine(line, lang) {
  return window.lexHighlight ? window.lexHighlight(line, lang) : escapeHtml(line);
}

function renderDiffLines(ops, lang) {
  const rows = ops.map(op => {
    const marker = op.type === 'add' ? '+' : op.type === 'remove' ? '-' : ' ';
    const cls = op.type === 'add' ? 'diff-add' : op.type === 'remove' ? 'diff-remove' : 'diff-equal';
    return `<div class="${cls}"><span class="diff-marker">${marker}</span>${highlightLine(op.line, lang)}</div>`;
  });
  return rows.join('\n');
}

// The full block for one write/edit event: a header naming the file and
// what happened to it, then the diff (or, past the size cap / for a
// brand-new file, a plain block of the new content).
function renderDiffBlock(d) {
  const lang = langOfPath(d.path);
  const header = d.kind === 'write'
    ? `<span class="diff-verb">Wrote</span> ${escapeHtml(d.path)}`
    : `<span class="diff-verb">Edited</span> ${escapeHtml(d.path)}`;

  let body;
  if (d.kind === 'write') {
    const lines = splitLines(d.new).map(l => ({ type: 'add', line: l }));
    body = renderDiffLines(lines, lang);
  } else {
    const ops = computeLineDiff(d.old, d.new);
    if (ops === null) {
      body = `<div class="diff-toolarge">file too large to diff inline (${splitLines(d.new).length} lines) — showing the new content</div>`
        + renderDiffLines(splitLines(d.new).map(l => ({ type: 'add', line: l })), lang);
    } else {
      body = renderDiffLines(ops, lang);
    }
  }
  return `<div class="diff-block"><div class="diff-header">${header}</div><pre class="diff-body">${body}</pre></div>`;
}

window.renderDiffBlock = renderDiffBlock;
window.computeLineDiff = computeLineDiff;
