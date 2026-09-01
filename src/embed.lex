# lex-code — embeddings and the semantic index
#
# #25 wants navigation by intent rather than by name. Two of its
# implementation choices are not available, and the shape here follows
# from that rather than from preference.
#
# ---- no `prov.embed` --------------------------------------------------
#
# lex-llm has no embedding API: `Provider` is { name, chat, stream } and
# nothing else. Adding one would be a lex-llm change with its own release
# coordination, so this speaks to an OpenAI-compatible `/v1/embeddings`
# endpoint directly. LiteLLM is the natural target — the README already
# makes it the recommended path for local models, precisely because it
# presents one OpenAI-shaped surface over Ollama, vLLM and the rest. So
# Ollama is reachable here, through LiteLLM, without lex-code learning a
# second wire format. Ollama's native `/api/embeddings` takes `prompt` and
# returns a bare `embedding`; the OpenAI shape takes `input` and returns
# `data[].embedding`, and supporting both would be two parsers for one
# feature.
#
# ---- no `.lex/index.db` -----------------------------------------------
#
# `Tool.execute` is fixed at `[net, io, proc]` and §1.6 makes record-field
# rows unify by equality, so no tool can widen it. No `sql` means no
# SQLite index, sqlite-vec or otherwise — the same wall that put
# verification evidence in a JSONL file in #74. It also means no `env`, so
# a query tool cannot read LITELLM_BASE_URL.
#
# That last constraint produced the better design. The index's first line
# is a header naming the endpoint and model that built it, and the query
# path reads its configuration from there. This is not a workaround: a
# query vector must come from the same model as the indexed vectors or the
# cosine between them is meaningless, so binding the model to the index is
# a correctness property that a separately-configured tool would get
# wrong.

import "std.http" as http

import "std.map" as map

import "std.bytes" as bytes

import "std.str" as str

import "std.list" as list

import "std.io" as io

import "std.math" as math

import "std.float" as float

import "std.int" as int

import "lex-schema/json_value" as jv

type Config = { base_url :: Str, model :: Str, dims :: Int }

type Entry = { sig :: Str, name :: Str, file :: Str, text :: Str, vec :: List[Float] }

fn index_path() -> Str
  examples {
    index_path() => ".lex/index.jsonl"
  }
{
  ".lex/index.jsonl"
}

# Matches LITELLM_BASE_URL's documented default in the README, so a
# project that already runs the bundled proxy needs no extra setup.
fn default_base_url() -> Str
  examples {
    default_base_url() => "http://localhost:4000"
  }
{
  "http://localhost:4000"
}

fn default_model() -> Str
  examples {
    default_model() => "nomic-embed-text"
  }
{
  "nomic-embed-text"
}

# How many leading components of each embedding to keep.
#
# This is a latency knob, and the numbers are not subtle. Reading the index
# is the dominant cost of a query — the JSON parser walks one number per
# component per entry — and on this repo's 674 functions it measures:
#
#   512 dims   932K   34s per read
#   128 dims   ~500K   ~6s
#    64 dims   336K    3s
#
# A 34-second search tool is not a search tool, so the index stores a
# prefix. That is sound rather than merely cheap for a Matryoshka-trained
# model like nomic-embed-text, which is trained so that a leading slice of
# the vector is itself a usable embedding; the prefix is renormalised
# because truncation changes the norm. Raise it for better ranking on a
# small tree, lower it on a large one.
fn default_dims() -> Int
  examples {
    default_dims() => 128
  }
{
  128
}

fn default_config() -> Config {
  { base_url: default_base_url(), model: default_model(), dims: default_dims() }
}

# Keep the first `dims` components and renormalise. A vector shorter than
# `dims` is returned as-is: the model gave what it gave, and padding it
# with zeros would quietly change every distance.
fn truncate(v :: List[Float], dims :: Int) -> List[Float]
  examples {
    truncate([3.0, 4.0, 99.0], 2) => [0.6, 0.8],
    truncate([3.0, 4.0], 5) => [3.0, 4.0],
    truncate([], 3) => [],
    truncate([1.0, 2.0], 0) => [1.0, 2.0]
  }
{
  if dims <= 0 {
    v
  } else {
    if list.len(v) <= dims {
      v
    } else {
      renormalise(take_f(v, dims))
    }
  }
}

# One pass with an index, not `list.tail` recursion. Lists here are not
# cheap to re-tail: peeling one element off a 768-component vector 128
# times made truncation quadratic, and the whole-repo build stopped
# finishing. `list.fold` walks the vector once.
fn take_f(xs :: List[Float], k :: Int) -> List[Float] {
  match list.fold(xs, ([], 0), fn (acc :: (List[Float], Int), x :: Float) -> (List[Float], Int) {
    match acc {
      (kept, i) => if i < k {
        (list.cons(x, kept), i + 1)
      } else {
        (kept, i + 1)
      },
    }
  }) {
    (kept, _) => list.reverse(kept),
  }
}

fn renormalise(v :: List[Float]) -> List[Float] {
  let n := norm(v)
  if n == 0.0 {
    v
  } else {
    list.map(v, fn (x :: Float) -> Float {
      x / n
    })
  }
}

fn embed_url(base_url :: Str) -> Str
  examples {
    embed_url("http://localhost:4000") => "http://localhost:4000/v1/embeddings",
    embed_url("http://localhost:4000/") => "http://localhost:4000/v1/embeddings"
  }
{
  str.concat(strip_slash(base_url), "/v1/embeddings")
}

fn strip_slash(s :: Str) -> Str
  examples {
    strip_slash("http://x/") => "http://x",
    strip_slash("http://x") => "http://x"
  }
{
  match str.strip_suffix(s, "/") {
    None => s,
    Some(r) => r,
  }
}

# ---- the wire ---------------------------------------------------------
fn embed_body(model :: Str, text :: Str) -> Str
  examples {
    embed_body("nomic-embed-text", "hi") => "{\"model\":\"nomic-embed-text\",\"input\":\"hi\"}"
  }
{
  jv.stringify(JObj([("model", JStr(model)), ("input", JStr(text))]))
}

# data[0].embedding, the OpenAI response shape LiteLLM emits for every
# backend it fronts.
fn parse_vec(body :: Str) -> Option[List[Float]] {
  match jv.parse_into_errors(body) {
    Err(_) => None,
    Ok(j) => match jv.get_field(j, "data") {
      Some(JList(items)) => match list.head(items) {
        None => None,
        Some(first) => match jv.get_field(first, "embedding") {
          Some(JList(nums)) => Some(list.map(nums, as_float)),
          _ => None,
        },
      },
      _ => None,
    },
  }
}

# An embedding arrives as JSON numbers, which the parser types as JInt when
# a value happens to be integral (a clean 0, or -1). Reading only JFloat
# would silently drop those components and skew every distance, so both are
# accepted.
fn as_float(j :: jv.Json) -> Float
  examples {
    as_float(JFloat(1.5)) => 1.5,
    as_float(JInt(2)) => 2.0,
    as_float(JStr("x")) => 0.0
  }
{
  match j {
    JFloat(f) => f,
    JInt(n) => int.to_float(n),
    _ => 0.0,
  }
}

fn embed_one(cfg :: Config, text :: Str) -> [net] Result[List[Float], Str] {
  let hdrs := map.set(map.new(), "content-type", "application/json")
  let req := { method: "POST", url: embed_url(cfg.base_url), headers: hdrs, body: Some(bytes.from_str(embed_body(cfg.model, text))), timeout_ms: Some(60000) }
  match http.send(req) {
    Err(_) => Err(str.join(["could not reach the embeddings endpoint at ", embed_url(cfg.base_url), " — is the LiteLLM proxy running?"], "")),
    Ok(r) => if r.status >= 400 {
      Err(str.join(["embeddings endpoint returned HTTP ", int.to_str(r.status), " — is \"", cfg.model, "\" in the proxy's model list?"], ""))
    } else {
      match body_str(r.body) {
        Err(m) => Err(m),
        Ok(text) => match parse_vec(text) {
          None => Err("embeddings response had no data[0].embedding"),
          Some(v) => Ok(v),
        },
      }
    },
  }
}

fn body_str(b :: Bytes) -> Result[Str, Str] {
  match bytes.to_str(b) {
    Err(_) => Err("embeddings response body was not valid UTF-8"),
    Ok(s) => Ok(s),
  }
}

# ---- similarity -------------------------------------------------------
fn dot(a :: List[Float], b :: List[Float]) -> Float
  examples {
    dot([1.0, 2.0], [3.0, 4.0]) => 11.0,
    dot([], []) => 0.0,
    dot([1.0], [1.0, 9.0]) => 1.0
  }
{
  match (list.head(a), list.head(b)) {
    (Some(x), Some(y)) => x * y + dot(list.tail(a), list.tail(b)),
    _ => 0.0,
  }
}

fn norm(a :: List[Float]) -> Float
  examples {
    norm([3.0, 4.0]) => 5.0,
    norm([]) => 0.0
  }
{
  math.sqrt(dot(a, a))
}

# Zero-length vectors score 0 rather than dividing by zero. That happens
# when a component list came back empty or unparsable, and a NaN there
# would propagate silently through the ranking.
fn cosine(a :: List[Float], b :: List[Float]) -> Float
  examples {
    cosine([1.0, 0.0], [1.0, 0.0]) => 1.0,
    cosine([1.0, 0.0], [0.0, 1.0]) => 0.0,
    cosine([], [1.0]) => 0.0,
    cosine([1.0], []) => 0.0
  }
{
  let na := norm(a)
  let nb := norm(b)
  if na == 0.0 {
    0.0
  } else {
    if nb == 0.0 {
      0.0
    } else {
      dot(a, b) / (na * nb)
    }
  }
}

# ---- what gets embedded -----------------------------------------------
# `lex docs --output json` gives name, signature, effects and examples per
# function; there is no per-function doc comment in that schema, so the
# text is those four. Examples matter more than they look: they are the
# only part that says what the function does with real values, which is
# what a query like "validate an A2A envelope" is trying to match.
fn entry_text(name :: Str, signature :: Str, effects :: List[Str], examples :: List[Str]) -> Str
  examples {
    entry_text("path", "() -> Str", [], ["path() => \".lex\""]) => "path :: () -> Str\npath() => \".lex\"",
    entry_text("run", "(Str) -> Unit", ["io"], []) => "run :: (Str) -> Unit ![io]"
  }
{
  let head := if list.is_empty(effects) {
    str.join([name, " :: ", signature], "")
  } else {
    str.join([name, " :: ", signature, " ![", str.join(effects, ", "), "]"], "")
  }
  if list.is_empty(examples) {
    head
  } else {
    str.join([head, "\n", str.join(examples, "\n")], "")
  }
}

# ---- the index file ---------------------------------------------------
fn encode_header(cfg :: Config) -> Str
  examples {
    encode_header({ base_url: "http://x", model: "m", dims: 64 }) => "{\"kind\":\"header\",\"base_url\":\"http://x\",\"model\":\"m\",\"dims\":64}"
  }
{
  jv.stringify(JObj([("kind", JStr("header")), ("base_url", JStr(cfg.base_url)), ("model", JStr(cfg.model)), ("dims", JInt(cfg.dims))]))
}

fn decode_header(line :: Str) -> Option[Config] {
  match jv.parse_into_errors(str.trim(line)) {
    Err(_) => None,
    Ok(j) => match jv.get_field(j, "kind") {
      Some(JStr("header")) => Some({ base_url: str_field(j, "base_url"), model: str_field(j, "model"), dims: int_field(j, "dims") }),
      _ => None,
    },
  }
}

fn encode_entry(e :: Entry) -> Str {
  jv.stringify(JObj([("sig", JStr(e.sig)), ("name", JStr(e.name)), ("file", JStr(e.file)), ("text", JStr(e.text)), ("vec", JList(list.map(e.vec, fn (f :: Float) -> jv.Json {
    JFloat(f)
  })))]))
}

fn decode_entry(line :: Str) -> Option[Entry] {
  match jv.parse_into_errors(str.trim(line)) {
    Err(_) => None,
    Ok(j) => match jv.get_field(j, "sig") {
      Some(JStr(sig)) => Some({ sig: sig, name: str_field(j, "name"), file: str_field(j, "file"), text: str_field(j, "text"), vec: vec_field(j) }),
      _ => None,
    },
  }
}

fn str_field(j :: jv.Json, name :: Str) -> Str {
  match jv.get_field(j, name) {
    Some(JStr(s)) => s,
    _ => "",
  }
}

fn int_field(j :: jv.Json, name :: Str) -> Int {
  match jv.get_field(j, name) {
    Some(JInt(n)) => n,
    _ => 0,
  }
}

fn vec_field(j :: jv.Json) -> List[Float] {
  match jv.get_field(j, "vec") {
    Some(JList(nums)) => list.map(nums, as_float),
    _ => [],
  }
}

fn render_index(cfg :: Config, entries :: List[Entry]) -> Str {
  str.join([encode_header(cfg), "\n", str.join(list.map(entries, encode_entry), "\n"), "\n"], "")
}

fn write_index(cfg :: Config, entries :: List[Entry]) -> [io] Result[Int, Str] {
  match io.write(index_path(), render_index(cfg, entries)) {
    Err(msg) => Err(msg),
    Ok(_) => Ok(list.len(entries)),
  }
}

fn read_index() -> [io] (Option[Config], List[Entry]) {
  match io.read(index_path()) {
    Err(_) => (None, []),
    Ok(content) => {
      let lines := str.split(content, "\n")
      let cfg := match list.head(lines) {
        None => None,
        Some(first) => decode_header(first),
      }
      (cfg, list.fold(lines, [], fn (acc :: List[Entry], line :: Str) -> List[Entry] {
        match decode_entry(line) {
          None => acc,
          Some(e) => list.concat(acc, [e]),
        }
      }))
    },
  }
}

# ---- ranking ----------------------------------------------------------
type Hit = { score :: Float, entry :: Entry }

fn score_all(entries :: List[Entry], q :: List[Float]) -> List[Hit] {
  list.map(entries, fn (e :: Entry) -> Hit {
    { score: cosine(q, e.vec), entry: e }
  })
}

fn top_k(hits :: List[Hit], k :: Int) -> List[Hit] {
  take(list.sort_by(hits, fn (h :: Hit) -> Float {
    0.0 - h.score
  }), k)
}

fn take(xs :: List[Hit], k :: Int) -> List[Hit] {
  if k <= 0 {
    []
  } else {
    match list.head(xs) {
      None => [],
      Some(h) => list.concat([h], take(list.tail(xs), k - 1)),
    }
  }
}

fn render_hits(hits :: List[Hit]) -> Str {
  str.join(list.map(hits, fn (h :: Hit) -> Str {
    str.join([score_str(h.score), "  ", h.entry.file, "  ", h.entry.text], "")
  }), "\n\n")
}

# Two decimals, without a float formatter that would print 0.8123456789.
fn score_str(f :: Float) -> Str {
  str.join(["[", int.to_str(round_pct(f)), "%]"], "")
}

fn round_pct(f :: Float) -> Int
  examples {
    round_pct(1.0) => 100,
    round_pct(0.0) => 0,
    round_pct(0.815) => 81
  }
{
  float_to_int(f * 100.0)
}

fn float_to_int(f :: Float) -> Int {
  float.to_int(f)
}

