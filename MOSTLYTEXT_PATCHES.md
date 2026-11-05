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

Final source review also reproduces a partial-query cross-language case: a wide
capture can contain unqueried narrower captures of another language. Query the
monotonically expanded coverage to a fixed point before replacement so all
captures in that coverage are available. Regressions preserve all three narrow
captures and retire a renamed language when only its external tag is queried.

## Complete replacement coverage and explicit fresh parsing

Before retiring an old injection touched by a partial query, expand coverage to
its complete current extent and requery to a fixed point. A replacement can
start outside the original query window; fresh-capture expansion alone misses
it. The application regression fails for LF, CRLF and CR on the prior fork and
passes here without changing the default tree-reuse policy.

LanguageConfiguration.reusesPreviousTree is a source-compatible public Boolean,
defaulting to true. Setting it false resets parser continuation state and parses
without an old tree while retaining the previous edited tree for invalidation
comparison. The application selects false only for MarkdownInline after a valid
UTF-16 scalar corpus exposed a different child AST despite equal root AST and
included ranges. Other configurations, constructor signatures, grammar bytes,
runtime pin and BSD licence remain unchanged. This section supersedes the
prior statement that all public APIs are unchanged: this one opt-out is added.

The unchanged 2,000-edit fresh-highlight oracle passes with both corrections.
Upstream Debug/Release suites pass 36 XCTest cases and 12 Swift Testing
functions; inspected application Foundation/C fixtures pass 36 functions plus
8 XCTest cases. Release component timing remains distinct from whole-editor
responsiveness, native acceptance and the retained large-document fallback.
