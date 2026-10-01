# package_api — learn an installed package's real API without reading its source.
#
# find_packages answers "which package does this?"; it cannot answer "which
# module and which function?". The model's only route was `read`/`grep` over
# the package's src/ (lex-web alone is ~30 modules and ~100 KB of docs), which
# is what sent a planner into dozens of probe steps before it wrote anything.
#
# This is lex_stdlib's counterpart for packages. With no module it lists the
# package's modules, each with its own one-line header; with a module it
# returns `lex docs` for that file — typed signatures (effect rows included)
# and doc comments, straight from the compiler. Nothing here is hand-written,
# so it cannot drift from what `lex check` accepts.
#
# `lex docs` prints signatures its own way — `Map<Str, Str>`, the effect row
# after the return type, a trailing revision hash — none of which is Lex source.
# A planner copies what it is shown, so it wrote `Result<Invoice, Str> [sql]`
# into every plan signature. The docs are rewritten here to the syntax the
# checker accepts: `Map[Str, Str]`, `-> [sql] Result[...]`, no hash.
#
# A package declared in lex.toml but not fetched yet is installed on demand
# (`lex pkg install` in the working directory), so a planner that only has
# read/write/package_api never needs a shell to get at its dependencies.
#
# Which copy is read: ~/.lex/packages holds `<name>/` and one
# `<name>@rev-<sha>/` per fetched revision, and the plain `<name>/` copy can
# be older than the newest rev. The most recently modified of them is read,
# and its path is printed so a stale copy is visible rather than silent.

import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "PackageApiArgs", description: "Learn an installed Lex package's API: list its modules, or show one module's typed signatures and docs.", fields: [s.with_desc(s.required_str("package", []), "Package name as in lex.toml, e.g. \"lex-web\", \"lex-orm\", \"lex-schema\". It must be declared in lex.toml [dependencies]; it is installed automatically if it is not fetched yet."), s.with_desc(s.optional(s.required_str("module", [])), "Module file name without .lex, e.g. \"router_pure\". Omit to list every module in the package.")] }
}

fn script() -> Str {
  str.join(["P=${LEX_PACKAGES_DIR:-$HOME/.lex/packages}", "case \"$1\" in \"\"|*[!A-Za-z0-9_-]*) echo BAD_PACKAGE; exit 2;; esac", "find_d() { ls -dt \"$P/$1\" \"$P/$1\"@rev-* 2>/dev/null | head -1; }", "d=$(find_d \"$1\")", "if [ -z \"$d\" ] && grep -q \"^$1[[:space:]]*=\" lex.toml 2>/dev/null; then lex pkg install >/dev/null 2>&1; d=$(find_d \"$1\"); fi", "[ -n \"$d\" ] || { echo NOT_INSTALLED; exit 3; }", "if [ -z \"$2\" ]; then", "  echo \"package $1 — reading $d\"", "  echo \"import a module with: import \\\"$1/<module>\\\" as x\"", "  echo", "  for f in \"$d\"/src/*.lex; do m=$(basename \"$f\" .lex); h=$(grep -m1 '^# ' \"$f\" | cut -c3-120 | sed \"s/^$1 — //\"); echo \"  $m — $h\"; done", "  echo", "  echo \"Call package_api(package, module) for a module's typed signatures and docs.\"", "else", "  case \"$2\" in *[!A-Za-z0-9_]*) echo BAD_MODULE; exit 2;; esac", "  [ -f \"$d/src/$2.lex\" ] || { echo NO_MODULE; exit 4; }", "  echo \"types below are owned by this module: in a plan signature write them qualified by a short alias, e.g. conn.ConnDb\"", "  lex docs \"$d/src/$2.lex\" | sed -E -e 's/  [[][0-9a-f]{12}[]]$//' -e 's/->/@A@/g' -e ':a' -e 's/<([^<>]*)>/[\\1]/' -e 'ta' -e 's/^( +[A-Za-z_0-9]+[(].*[)]) @A@ (.*) [[]([a-z_, ]+)[]]$/\\1 -> [\\3] \\2/' -e 's/@A@/->/g' | head -c 14000", "fi"], "\n")
}

fn failure(code :: Int, package :: Str, module :: Str) -> Str
  examples {
    failure(3, "lex-web", "") => "package \"lex-web\" is not installed: lex.toml does not declare it, or `lex pkg install` could not fetch it. Find its dependency line with find_packages and add it to lex.toml [dependencies]; package_api installs a declared package itself, so then just call it again.",
    failure(4, "lex-web", "nope") => "package \"lex-web\" has no module \"nope\". Call package_api with just the package name to list its modules."
  }
{
  if code == 3 {
    str.join(["package \"", package, "\" is not installed: lex.toml does not declare it, or `lex pkg install` could not fetch it. Find its dependency line with find_packages and add it to lex.toml [dependencies]; package_api installs a declared package itself, so then just call it again."], "")
  } else {
    if code == 4 {
      str.join(["package \"", package, "\" has no module \"", module, "\". Call package_api with just the package name to list its modules."], "")
    } else {
      "package and module names may contain only letters, digits, - and _"
    }
  }
}

fn execute(args :: jv.Json) -> [io, net, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "package") {
    None => Err(e.single("", "missing_field", "package is required")),
    Some(package) => {
      let module := util.field_str_or(args, "module", "")
      match proc.run("sh", ["-c", script(), "sh", str.trim(package), str.trim(module)]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => if out.exit_code == 0 {
          Ok(JStr(out.stdout))
        } else {
          Err(e.single("", "package_api_failed", failure(out.exit_code, str.trim(package), str.trim(module))))
        },
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("package_api", "Learn an installed package's real API without reading its source — the counterpart of lex_stdlib for packages. package=\"lex-web\" lists its modules with a one-line purpose each; package=\"lex-web\" module=\"router_pure\" returns that module's typed signatures (effect rows included) and docs, from `lex docs`, written in the syntax Lex source and plan signatures use (`Map[Str, Str]`, `-> [sql] T`) so they can be copied as they are. Call this after find_packages (a package declared in lex.toml is installed on demand), BEFORE reading the package's src/ or probing it with a throwaway file.", params(), execute)
}

