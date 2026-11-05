# MostlyText maintained patch

Base: ChimeHQ/SwiftTreeSitter cbe31cb3601aa29c1f64b6e4328733511126d6d5.
The original BSD-3-Clause licence and all original credits remain unchanged.

Inline injection reconciliation now discards collapsed ranges, replaces old
ranges overlapping fresh captures and retires captures within the queried
coverage even when there is no replacement. It retains unqueried neighbors,
invalidates removed extents and retires an empty restricted language layer
instead of resetting its C parser to whole-document input. A sorted sweep
replaces the previous old-ranges-by-new-ranges filter. Public APIs are unchanged.

Upstream tests plus strict regressions cover replacement/deletion, combined
edits, partial queries, empty layer retirement and neighboring/duplicate ranges.
A separate application corpus exercises seven edit shapes, both full and changed-
range resolution and LF/CRLF/CR with Unicode. Baseline failures are preserved
in MostlyText's dependency evidence packet. Full editor responsiveness, Neon
sublayer/styling invalidation and the Markdown grammar's incremental-reuse
limits remain separate issues; the large-document fallback is not raised here.

This is an owner-maintained fork. No upstream submission or acceptance is claimed.
