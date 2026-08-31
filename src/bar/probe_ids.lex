# The canonical probe ids, so ./ledger and ./checks cannot drift apart.
#
# A ledger item naming a probe nobody implements would be skipped by
# bar_check in silence — the exact failure mode a checklist exists to
# prevent — so the id is a function both modules call rather than a
# string each of them spells. Pure and effect-free on purpose: the test
# suite imports this and ./ledger without dragging in ./checks's [proc].

import "std.list" as list

fn secret_scan() -> Str
  examples {
    secret_scan() => "secret_scan"
  }
{
  "secret_scan"
}

fn git_remote() -> Str
  examples {
    git_remote() => "git_remote"
  }
{
  "git_remote"
}

fn tests_present() -> Str
  examples {
    tests_present() => "tests_present"
  }
{
  "tests_present"
}

fn ci_on_pr() -> Str
  examples {
    ci_on_pr() => "ci_on_pr"
  }
{
  "ci_on_pr"
}

fn toolchain_pin() -> Str
  examples {
    toolchain_pin() => "toolchain_pin"
  }
{
  "toolchain_pin"
}

fn examples_coverage() -> Str
  examples {
    examples_coverage() => "examples_coverage"
  }
{
  "examples_coverage"
}

# In the order checks.run_all emits them.
fn all() -> List[Str]
  examples {
    all() => ["secret_scan", "git_remote", "tests_present", "ci_on_pr", "toolchain_pin", "examples_coverage"]
  }
{
  [secret_scan(), git_remote(), tests_present(), ci_on_pr(), toolchain_pin(), examples_coverage()]
}

fn count() -> Int
  examples {
    count() => 6
  }
{
  list.len(all())
}

