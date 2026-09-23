// A small, deliberately incomplete Markdown renderer.
//
// lex-code's own web UI has no build step and no external script — the
// whole point is that it works with `ollama` and no network at all, the
// same offline story the tool sells for local models. Pulling in a full
// Markdown library (or a CDN script) would be the first thing on the page
// that needs the internet. What an LLM actually writes is a narrow slice
// of Markdown — fenced code blocks, inline code, bold/italic, lists,
// links, headings — so that slice is what this covers. It is NOT a
// CommonMark implementation; unusual input degrades to plain text rather
// than mis-rendering.
//
// Escaped first, rendered second: every code span and every block of
// plain text goes through escapeHtml before any markup is added, so the
// model's own output can never inject HTML into the page.

function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// Bold/italic/inline-code/links within one line. Applied after the line's
// own text has already been escaped, so patterns match literal
// `**`/`` ` ``/`[`, never something reconstructed from injected HTML.
function renderInline(escaped) {
  return escaped
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em>$1</em>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
}

// A fenced block's language tag, lowercased, or '' when there is none —
// `renderCode` (diff.js) reads this to pick a highlighter.
function fenceLang(line) {
  const m = /^```\s*([a-zA-Z0-9_+-]*)\s*$/.exec(line.trim());
  return m ? m[1].toLowerCase() : '';
}

function isFence(line) {
  return /^```/.test(line.trim());
}

// One Markdown source string -> one HTML string. Block-level: split into
// lines, walk them, treat a paragraph/list/fence as a unit.
function renderMarkdown(src) {
  const lines = String(src).replace(/\r\n/g, '\n').split('\n');
  const out = [];
  let i = 0;
  let inList = false;

  function closeList() {
    if (inList) { out.push('</ul>'); inList = false; }
  }

  while (i < lines.length) {
    const line = lines[i];

    if (isFence(line)) {
      const lang = fenceLang(line);
      const body = [];
      i++;
      while (i < lines.length && !isFence(lines[i])) { body.push(lines[i]); i++; }
      i++; // consume the closing fence
      closeList();
      out.push(renderCodeBlock(body.join('\n'), lang));
      continue;
    }

    const heading = /^(#{1,6})\s+(.*)$/.exec(line);
    if (heading) {
      closeList();
      const level = heading[1].length;
      out.push(`<h${level}>${renderInline(escapeHtml(heading[2]))}</h${level}>`);
      i++;
      continue;
    }

    const item = /^\s*[-*]\s+(.*)$/.exec(line);
    if (item) {
      if (!inList) { out.push('<ul>'); inList = true; }
      out.push(`<li>${renderInline(escapeHtml(item[1]))}</li>`);
      i++;
      continue;
    }

    closeList();
    if (line.trim() === '') { i++; continue; }
    out.push(`<p>${renderInline(escapeHtml(line))}</p>`);
    i++;
  }
  closeList();
  return out.join('\n');
}

// Split from renderMarkdown so diff.js's own renderer (a Written/Edited
// block, not a fenced fragment of chat text) can call the same
// escape+highlight path for one file's content.
function renderCodeBlock(code, lang) {
  const highlighted = window.lexHighlight ? window.lexHighlight(code, lang) : escapeHtml(code);
  const langAttr = lang ? ` data-lang="${escapeHtml(lang)}"` : '';
  return `<pre class="code-block"${langAttr}><code>${highlighted}</code></pre>`;
}

window.renderMarkdown = renderMarkdown;
window.escapeHtml = escapeHtml;
