import "./audit" as audit

fn build_report(events :: List[Str]) -> List[Str] {
  audit.record_all(events)
}

