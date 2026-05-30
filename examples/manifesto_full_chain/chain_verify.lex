# lex-code — manifesto demo: hash chain tamper-evidence (§VIII)
#
# Manifesto §VIII:
#   "Every agent action is recorded in an append-only event log with a
#    sequential hash chain. Deletion or mutation of any entry breaks
#    the chain — verify_chain surfaces the violation as a structured
#    error, not a missing log line."
#
# This script demonstrates:
#   1. An honest 3-event trail passes verify_chain -> Ok(3)
#   2. Deleting the middle event (seq=1) breaks the chain ->
#      Err("chain broken: expected seq 1, found seq 2")
#
# Per-event content hashes (is_valid) would NOT catch the deletion —
# the remaining two events are individually valid. Only the sequential
# chain detects the gap.
#
#   lex run examples/manifesto_full_chain/chain_verify.lex main \
#       --allow-effects sql,fs_write,time,io

import "lex-trail/log" as log

import "std.sql" as sql

import "std.io" as io

import "std.str" as str

import "std.int" as int

fn main() -> [sql, fs_write, time, io] Unit {
  match log.open_memory() {
    Err(e) => {
      let __e := io.print(str.concat("FATAL: open_memory failed: ", e))
      ()
    },
    Ok(trail) => {
      let __a1 := log.append(trail, "llm.step",   None, "{\"step\":1,\"tokens_in\":10,\"tokens_out\":8}")
      let __a2 := log.append(trail, "cap.invoked", None, "{\"step\":2,\"capability\":\"search\"}")
      let __a3 := log.append(trail, "llm.step",   None, "{\"step\":3,\"tokens_in\":8,\"tokens_out\":15}")

      let __h1 := io.print("==> verify_chain on honest 3-event log:")
      match log.verify_chain(trail) {
        Ok(n)  => {
          let __p := io.print(str.concat("    Ok(", str.concat(int.to_str(n), ") — chain intact, all 3 events verified")))
          ()
        },
        Err(e) => {
          let __p := io.print(str.concat("    UNEXPECTED Err: ", e))
          ()
        },
      }

      # Surgically delete the middle event. Content hashes of the
      # remaining events are still valid — only the chain catches this.
      let __del := sql.exec(trail.db, "DELETE FROM events WHERE seq = 1", [])
      let __h2  := io.print("")
      let __h3  := io.print("==> deleted seq=1 (middle event) — verify_chain after deletion:")
      match log.verify_chain(trail) {
        Ok(n) => {
          let __p := io.print(str.concat("    FAIL: verify_chain returned Ok(", str.concat(int.to_str(n), ") — deletion not detected")))
          ()
        },
        Err(e) => {
          let __p := io.print(str.concat("    Err: ", e))
          let __q := io.print("    VALIDATED: deletion detected via seq gap — hash chain works")
          ()
        },
      }
      ()
    },
  }
}
