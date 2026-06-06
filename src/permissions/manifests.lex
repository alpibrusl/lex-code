# Per-mode trust manifests for lex-os integration.
#
# Each AgentMode maps to a Grant that constrains what the mode can do
# on the three trust dimensions: filesystem, network, exec.
#
# Grant levels (from lex-types):
#   filesystem: None | ReadOnly | ReadWrite | Full
#   network:    None | Loopback | Allowlist  | Full
#   exec:       None | Sandboxed             | Full
#
# Manifests are written to /tmp at call time and passed to `lex-os check`.

import "std.str" as str

import "std.int" as int

import "std.io" as io

fn manifest_json(goal :: Str, filesystem :: Str, network :: Str, exec_level :: Str, floor :: Str, wall :: Int, cmds :: Int, money :: Int, api_calls :: Int) -> Str {
  str.join([
    "{\"goal\":{\"description\":\"", goal, "\"},",
    "\"grant\":{\"filesystem\":\"", filesystem, "\",\"network\":\"", network, "\",\"exec\":\"", exec_level, "\"},",
    "\"budget\":{\"wall_clock_secs\":", int.to_str(wall), ",",
    "\"max_commands\":", int.to_str(cmds), ",",
    "\"max_money_cents\":", int.to_str(money), ",",
    "\"max_api_calls\":", int.to_str(api_calls), "},",
    "\"isolation_floor\":\"", floor, "\",\"egress\":[]}"
  ], "")
}

fn explore_manifest_json() -> Str {
  manifest_json("lex-code explore mode", "ReadOnly", "None", "None", "Namespace", 300, 200, 0, 50)
}

fn plan_manifest_json() -> Str {
  manifest_json("lex-code plan mode", "ReadOnly", "None", "None", "Namespace", 300, 200, 0, 50)
}

fn review_manifest_json() -> Str {
  manifest_json("lex-code review mode", "ReadOnly", "None", "None", "Namespace", 300, 200, 0, 50)
}

fn spec_manifest_json() -> Str {
  manifest_json("lex-code spec mode", "ReadWrite", "None", "None", "Namespace", 300, 200, 0, 50)
}

fn test_manifest_json() -> Str {
  manifest_json("lex-code test mode", "ReadWrite", "None", "Sandboxed", "Gvisor", 300, 200, 0, 50)
}

fn refactor_manifest_json() -> Str {
  manifest_json("lex-code refactor mode", "ReadWrite", "None", "Sandboxed", "Gvisor", 300, 200, 0, 50)
}

fn build_manifest_json() -> Str {
  manifest_json("lex-code build mode", "Full", "Allowlist", "Full", "MicroVm", 600, 500, 500, 100)
}

fn json_for_mode(mode :: Str) -> Str {
  if mode == "explore" {
    explore_manifest_json()
  } else {
    if mode == "plan" {
      plan_manifest_json()
    } else {
      if mode == "review" {
        review_manifest_json()
      } else {
        if mode == "spec" {
          spec_manifest_json()
        } else {
          if mode == "test" {
            test_manifest_json()
          } else {
            if mode == "refactor" {
              refactor_manifest_json()
            } else {
              build_manifest_json()
            }
          }
        }
      }
    }
  }
}

fn temp_path_for_mode(mode :: Str) -> Str {
  str.concat("/tmp/lex-code-manifest-", str.concat(mode, ".json"))
}

fn write_manifest_for_mode(mode :: Str) -> [io] Result[Str, Str] {
  let path := temp_path_for_mode(mode)
  match io.write(path, json_for_mode(mode)) {
    Ok(_) => Ok(path),
    Err(e) => Err(e),
  }
}
