# lex-code — building the semantic index
#
# Separate from the query path because of the effect wall. `Tool.execute`
# is `[net, io, proc]` with no `env`, so a tool cannot read
# LITELLM_BASE_URL; building needs that, and needs to be a deliberate,
# visible step anyway — it makes one HTTP call per function, 621 of them
# on this repo today. A rebuild is not something to trigger by accident
# from inside an agent turn.
#
# The corpus comes from `lex docs --output json`, which already yields
# name, signature, effects, examples and sig_id per function across the
# whole tree. Parsing .lex files here to recover the same information
# would be a second, worse parser for a shape the toolchain already
# publishes.
#
# ---- incremental --------------------------------------------------
#
# `sig_id` is the reuse key, not mtime. It is a hash of the function's own
# content, so it answers exactly "has this function changed" — where mtime
# answers "was this file touched", which is true after a comment edit and
# false after a `git checkout` that rewinds content. Everything whose
# sig_id is already indexed is carried over unembedded.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "std.map" as map

import "std.io" as io

import "std.env" as env

import "std.int" as int

import "lex-schema/json_value" as jv

import "./embed" as embed

fn config_from_env() -> [env] embed.Config {
  { base_url: env_or("LITELLM_BASE_URL", embed.default_base_url()), model: env_or("LEX_EMBED_MODEL", embed.default_model()), dims: dims_from_env() }
}

fn dims_from_env() -> [env] Int {
  match str.to_int(env_or("LEX_EMBED_DIMS", "")) {
    None => embed.default_dims(),
    Some(n) => if n <= 0 {
      embed.default_dims()
    } else {
      n
    },
  }
}

fn env_or(key :: Str, fallback :: Str) -> [env] Str {
  match env.get(key) {
    None => fallback,
    Some(v) => if str.is_empty(v) {
      fallback
    } else {
      v
    },
  }
}

# One function's worth of the corpus, before it has a vector.
type Doc = { sig :: Str, name :: Str, file :: Str, text :: Str }

fn docs_json(path :: Str) -> [proc] Result[Str, Str] {
  match proc.run("lex", ["--output", "json", "docs", path]) {
    Err(msg) => Err(msg),
    Ok(out) => if out.exit_code == 0 {
      Ok(out.stdout)
    } else {
      Err(str.trim(str.concat(out.stdout, out.stderr)))
    },
  }
}

# `lex --output json` wraps every result: the outer `ok` says the command
# ran, and the payload is under `data`. Reading the outer object as the
# result is a mistake this codebase has made before.
fn parse_docs(body :: Str) -> List[Doc] {
  match jv.parse_into_errors(body) {
    Err(_) => [],
    Ok(j) => match jv.get_field(j, "data") {
      None => [],
      Some(data) => match jv.get_field(data, "modules") {
        Some(JList(mods)) => list.fold(mods, [], fn (acc :: List[Doc], m :: jv.Json) -> List[Doc] {
          list.concat(acc, docs_of_module(m))
        }),
        _ => [],
      },
    },
  }
}

fn docs_of_module(m :: jv.Json) -> List[Doc] {
  let file := str_field(m, "file")
  match jv.get_field(m, "functions") {
    Some(JList(fns)) => list.map(fns, fn (f :: jv.Json) -> Doc {
      { sig: str_field(f, "sig_id"), name: str_field(f, "name"), file: file, text: embed.entry_text(str_field(f, "name"), str_field(f, "signature"), str_list(f, "effects"), str_list(f, "examples")) }
    }),
    _ => [],
  }
}

fn str_field(j :: jv.Json, name :: Str) -> Str {
  match jv.get_field(j, name) {
    Some(JStr(s)) => s,
    _ => "",
  }
}

fn str_list(j :: jv.Json, name :: Str) -> List[Str] {
  match jv.get_field(j, name) {
    Some(JList(items)) => list.fold(items, [], fn (acc :: List[Str], it :: jv.Json) -> List[Str] {
      match it {
        JStr(s) => list.concat(acc, [s]),
        _ => acc,
      }
    }),
    _ => [],
  }
}

# Previously-indexed vectors, keyed by sig_id.
#
# This was a `list.filter` per lookup, which made the incremental path
# QUADRATIC and, measured on this repo, slower than re-embedding all 674
# functions from scratch — the exact opposite of what incremental is for.
# 674 lookups over 674 entries, each carrying a 512-float vector, is not a
# cost the constant factor rescues.
fn vec_index(entries :: List[embed.Entry]) -> Map[Str, List[Float]] {
  map.from_list(list.map(entries, fn (e :: embed.Entry) -> (Str, List[Float]) {
    (e.sig, e.vec)
  }))
}

fn existing(prev :: Map[Str, List[Float]], sig :: Str) -> Option[List[Float]] {
  if str.is_empty(sig) {
    None
  } else {
    map.get(prev, sig)
  }
}

# Build (or refresh) the index for `path`.
#
# A single embedding failure aborts rather than being skipped. A partial
# index is worse than none: the query still answers, ranks over whatever
# happened to succeed, and gives no sign that half the corpus is missing —
# so a function that exists reads as a function that does not.
fn build(path :: Str) -> [env, net, io, proc] Result[Int, Str] {
  let cfg := config_from_env()
  match docs_json(path) {
    Err(msg) => Err(str.concat("could not run `lex docs`: ", msg)),
    Ok(body) => {
      let docs := parse_docs(body)
      if list.is_empty(docs) {
        Err(str.concat("no functions found under ", path))
      } else {
        match reuse_or_embed(cfg, docs) {
          Err(msg) => Err(msg),
          Ok(entries) => embed.write_index(cfg, entries),
        }
      }
    },
  }
}

fn reuse_or_embed(cfg :: embed.Config, docs :: List[Doc]) -> [io, net] Result[List[embed.Entry], Str] {
  match embed.read_index() {
    (prev_cfg, prev) => {
      let usable := if reusable(cfg, prev_cfg) {
        vec_index(prev)
      } else {
        map.new()
      }
      match fold_docs(cfg, docs, usable, []) {
        Err(m) => Err(m),
        Ok(rev) => Ok(list.reverse(rev)),
      }
    },
  }
}

# Vectors are only comparable within one model. If the configured model or
# endpoint differs from the one that built the existing index, every entry
# in it is dead weight — reusing them would mix two vector spaces in one
# ranking, which produces plausible-looking nonsense rather than an error.
fn reusable(cfg :: embed.Config, prev :: Option[embed.Config]) -> Bool
  examples {
    reusable({ base_url: "u", model: "m", dims: 64 }, Some({ base_url: "u", model: "m", dims: 64 })) => true,
    reusable({ base_url: "u", model: "m", dims: 64 }, Some({ base_url: "u", model: "other", dims: 64 })) => false,
    reusable({ base_url: "u", model: "m", dims: 64 }, Some({ base_url: "elsewhere", model: "m", dims: 64 })) => false,
    reusable({ base_url: "u", model: "m", dims: 64 }, Some({ base_url: "u", model: "m", dims: 128 })) => false,
    reusable({ base_url: "u", model: "m", dims: 64 }, None) => false
  }
{
  match prev {
    None => false,
    Some(p) => if p.model == cfg.model {
      if p.base_url == cfg.base_url {
        p.dims == cfg.dims
      } else {
        false
      }
    } else {
      false
    },
  }
}

# Accumulates reversed: `list.concat(acc, [e])` copies the whole list on
# every append, which is the second half of the quadratic blowup above.
# The caller reverses once.
fn fold_docs(cfg :: embed.Config, docs :: List[Doc], usable :: Map[Str, List[Float]], acc :: List[embed.Entry]) -> [io, net] Result[List[embed.Entry], Str] {
  match list.head(docs) {
    None => Ok(acc),
    Some(d) => match entry_for(cfg, d, usable) {
      Err(msg) => Err(msg),
      Ok(e) => fold_docs(cfg, list.tail(docs), usable, list.cons(e, acc)),
    },
  }
}

fn entry_for(cfg :: embed.Config, d :: Doc, usable :: Map[Str, List[Float]]) -> [net] Result[embed.Entry, Str] {
  match existing(usable, d.sig) {
    Some(v) => Ok({ sig: d.sig, name: d.name, file: d.file, text: d.text, vec: v }),
    None => match embed.embed_one(cfg, d.text) {
      Err(msg) => Err(str.join(["embedding \"", d.name, "\" failed: ", msg], "")),
      Ok(v) => Ok({ sig: d.sig, name: d.name, file: d.file, text: d.text, vec: embed.truncate(v, cfg.dims) }),
    },
  }
}

# Entry point for `lex run src/index_build.lex main`.
fn main() -> [env, net, io, proc] Unit {
  let path := env_or("LEX_INDEX_PATH", "src/")
  let __start := io.print(str.join(["[index] embedding ", path, " via ", embed.embed_url(config_from_env().base_url), " (", config_from_env().model, " @ ", int.to_str(config_from_env().dims), "d)"], ""))
  match build(path) {
    Err(msg) => io.print(str.concat("[index] failed: ", msg)),
    Ok(n) => io.print(str.join(["[index] wrote ", int.to_str(n), " entries to ", embed.index_path()], "")),
  }
}

