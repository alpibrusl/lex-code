// A minimal, single-language-aware syntax highlighter — not a port of
// highlight.js. It exists for the same reason markdown.js is hand-rolled:
// no CDN, no build step, the page has to work with zero network access.
//
// Real coverage is `.lex` — the language this whole tool writes, so it's
// what shows up in almost every diff — plus `json`, since tool args and
// API responses are the other thing that gets pasted in. Anything else
// falls back to escaped plain text: an honest "not highlighted" rather
// than a wrong guess at some other language's grammar.

const LEX_KEYWORDS = new Set([
  'fn', 'let', 'match', 'if', 'else', 'import', 'as', 'type', 'examples',
  'true', 'false', 'None', 'Some', 'Ok', 'Err', 'pub',
]);

// One token per match: [regex, cssClass]. Order matters — earlier
// patterns win, so a comment consumes the rest of its line before a
// string or keyword inside it is considered.
const LEX_TOKEN_RULES = [
  [/#[^\n]*/y, 'comment'],
  [/"(?:[^"\\]|\\.)*"/y, 'string'],
  [/\b\d+(?:\.\d+)?\b/y, 'number'],
  [/[A-Za-z_][A-Za-z0-9_]*/y, 'word'],
  [/\s+/y, null],
  [/./y, null],
];

function highlightLex(code) {
  let out = '';
  let i = 0;
  while (i < code.length) {
    let matched = false;
    for (const [re, cls] of LEX_TOKEN_RULES) {
      re.lastIndex = i;
      const m = re.exec(code);
      if (m && m.index === i && m[0].length > 0) {
        const text = m[0];
        if (cls === 'word') {
          // Most identifiers get no distinct styling — wrapping every one
          // in an unstyled span was dead weight for no visual difference.
          out += LEX_KEYWORDS.has(text)
            ? `<span class="tok-keyword">${escapeHtml(text)}</span>`
            : escapeHtml(text);
        } else if (cls) {
          out += `<span class="tok-${cls}">${escapeHtml(text)}</span>`;
        } else {
          out += escapeHtml(text);
        }
        i += text.length;
        matched = true;
        break;
      }
    }
    if (!matched) { out += escapeHtml(code[i]); i++; }
  }
  return out;
}

const JSON_TOKEN_RULES = [
  [/"(?:[^"\\]|\\.)*"\s*:/y, 'key'],
  [/"(?:[^"\\]|\\.)*"/y, 'string'],
  [/\b(?:true|false|null)\b/y, 'keyword'],
  [/-?\b\d+(?:\.\d+)?\b/y, 'number'],
  [/\s+/y, null],
  [/./y, null],
];

function highlightJson(code) {
  let out = '';
  let i = 0;
  while (i < code.length) {
    let matched = false;
    for (const [re, cls] of JSON_TOKEN_RULES) {
      re.lastIndex = i;
      const m = re.exec(code);
      if (m && m.index === i && m[0].length > 0) {
        const text = m[0];
        out += cls ? `<span class="tok-${cls}">${escapeHtml(text)}</span>` : escapeHtml(text);
        i += text.length;
        matched = true;
        break;
      }
    }
    if (!matched) { out += escapeHtml(code[i]); i++; }
  }
  return out;
}

// code -> highlighted HTML (already escaped), or plain escaped text for
// any language this module doesn't know.
function lexHighlight(code, lang) {
  const l = (lang || '').toLowerCase();
  if (l === 'lex') return highlightLex(code);
  if (l === 'json') return highlightJson(code);
  return escapeHtml(code);
}

window.lexHighlight = lexHighlight;
