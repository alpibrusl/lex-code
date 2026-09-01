# lex-code — find functions by intent
#
# Every other navigation tool matches on names: grep, glob, sigid_lookup.
# That caps explore and plan quality on a large tree, because the thing
# you are looking for is usually described by what it does rather than by
# what it was called.
#
# This queries `.lex/index.jsonl`, built by `src/index_build.lex`. It does
# not build the index itself: building makes one HTTP call per function
# (621 on this repo), and the configuration it needs lives in env, which
# `Tool.execute`'s `[net, io, proc]` row cannot read. A missing index is
# reported with the command that creates one, rather than being silently
# treated as "no results" — the failure mode #32 was about.

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

import "../embed" as embed

fn params() -> s.ModelSchema {
  { title: "SemanticSearchArgs", description: "Find functions by what they do", fields: [s.required_str("query", []), s.optional(s.required_int("top_k", []))] }
}

fn default_k() -> Int
  examples {
    default_k() => 8
  }
{
  8
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "query") {
    None => Err(e.single("", "missing_field", "query is required")),
    Some(query) => if str.is_empty(str.trim(query)) {
      Err(e.single("", "empty_query", "query is empty"))
    } else {
      search(str.trim(query), k_of(args))
    },
  }
}

fn k_of(args :: jv.Json) -> Int {
  match util.field_int(args, "top_k") {
    None => default_k(),
    Some(k) => if k <= 0 {
      default_k()
    } else {
      k
    },
  }
}

# The index's header carries the endpoint and model that built it, and the
# query is embedded with those rather than with anything configured here.
# A cosine between vectors from two different models is a number with no
# meaning, so this is the only correct source for that choice.
fn search(query :: Str, k :: Int) -> [net, io] Result[jv.Json, e.Errors] {
  match embed.read_index() {
    (None, _) => Err(e.single("", "no_index", missing_index_msg())),
    (Some(cfg), entries) => if list.is_empty(entries) {
      Err(e.single("", "empty_index", missing_index_msg()))
    } else {
      match embed.embed_one(cfg, query) {
        Err(msg) => Err(e.single("", "embed_failed", msg)),
        Ok(qvec) => Ok(JStr(render(query, embed.top_k(embed.score_all(entries, embed.truncate(qvec, cfg.dims)), k), cfg))),
      }
    },
  }
}

fn missing_index_msg() -> Str {
  str.join(["no semantic index at ", embed.index_path(), ". Build one with:\n\n  lex run --allow-effects env,io,net,proc src/index_build.lex main\n\nIt needs a LiteLLM proxy reachable at LITELLM_BASE_URL (default ", embed.default_base_url(), ") serving an embedding model as LEX_EMBED_MODEL (default ", embed.default_model(), ")."], "")
}

# The scores are cosine similarities, and they are only meaningful next to
# each other: a top hit at 62% on a small corpus can be the right answer,
# and one at 88% can be wrong. Saying so is cheaper than having a model
# treat the number as a confidence and stop reading at the first result.
fn render(query :: Str, hits :: List[embed.Hit], cfg :: embed.Config) -> Str {
  if list.is_empty(hits) {
    str.join(["no matches for \"", query, "\""], "")
  } else {
    str.join([str.join([int.to_str(list.len(hits)), " nearest to \"", query, "\" (", cfg.model, "):"], ""), "\n\n", embed.render_hits(hits), "\n\nScores are cosine similarity, useful only relative to each other — read the top few rather than trusting the number. The index covers functions as of the last build; run src/index_build.lex after adding code."], "")
  }
}

fn tool() -> t.Tool {
  t.define("semantic_search", "Find functions by what they DO rather than by name — e.g. \"validate an A2A envelope\", \"retry a failed HTTP call\". Ranked by embedding similarity over each function's signature, effects and examples. Complements grep/glob, which only match names.", params(), execute)
}

