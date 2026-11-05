import Foundation
import Testing
import SwiftTreeSitter
@testable import SwiftTreeSitterLayer

@Suite(.serialized)
struct IncludedRangeReplacementTests {
	private struct Edit {
		let range: NSRange
		let replacement: String
	}

	private func point(_ location: Int, in text: String) -> Point {
		let prefix = Array(text.utf16.prefix(location))
		let row = prefix.filter { $0 == 10 }.count
		let start = prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0
		return Point(row: row, column: (location - start) * 2)
	}

	private func layer(_ text: String) throws -> LanguageLayer {
		let configuration = LanguageLayer.Configuration(languageProvider: { _ in
			LanguageLayerTests.swiftConfig
		})
		let layer = try LanguageLayer(
			languageConfig: LanguageLayerTests.selfInjectingSwiftConfig,
			configuration: configuration
		)
		_ = layer.replaceContent(with: text)
		return layer
	}

	private func assertFreshEquivalent(_ initial: String, edits: [Edit], wholeDocument: Bool = true) throws {
		var text = initial
		let edited = try layer(text)
		var invalidated = IndexSet()
		for edit in edits {
			let oldStart = point(edit.range.location, in: text)
			let oldEnd = point(edit.range.upperBound, in: text)
			text = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
			let newEnd = edit.range.location + edit.replacement.utf16.count
			invalidated.shift(startingAt: edit.range.upperBound, by: edit.replacement.utf16.count - edit.range.length)
			let changed = edited.didChangeContent(.init(string: text), using: InputEdit(
				startByte: edit.range.location * 2,
				oldEndByte: edit.range.upperBound * 2,
				newEndByte: newEnd * 2,
				startPoint: oldStart,
				oldEndPoint: oldEnd,
				newEndPoint: point(newEnd, in: text)
			), resolveSublayers: false)
			invalidated.formUnion(changed)
		}
		let entireDocument = IndexSet(integersIn: 0..<text.utf16.count)
		_ = try edited.resolveSublayers(with: .init(string: text), in: wholeDocument ? entireDocument : invalidated)
		let fresh = try layer(text)
		#expect(edited.snapshot()?.rootSnapshot.tree.rootNode?.sExpressionString == fresh.snapshot()?.rootSnapshot.tree.rootNode?.sExpressionString, "Root tree must match before testing injection ownership")
		let editedTree = try #require(edited.snapshot()?.sublayerSnapshots.first?.rootSnapshot.tree)
		let freshTree = try #require(fresh.snapshot()?.sublayerSnapshots.first?.rootSnapshot.tree)
		#expect(editedTree.includedRanges == freshTree.includedRanges)
		#expect(editedTree.rootNode?.sExpressionString == freshTree.rootNode?.sExpressionString)
		let range = NSRange(location: 0, length: text.utf16.count)
		let actual = try edited.highlights(in: range, provider: text.predicateTextProvider)
		let expected = try fresh.highlights(in: range, provider: text.predicateTextProvider)
		#expect(actual == expected)
	}

	@Test func partialQueriesRetainUnqueriedNeighbors() throws {
		let text = (0..<100).map { "let value\($0) = \"var n = 1\"\n" }.joined()
		try assertFreshEquivalent(text, edits: [Edit(range: NSRange(location: 900, length: 600), replacement: "")], wholeDocument: false)
	}

	@Test func vanishedInjectionRetiresRestrictedLayer() throws {
		let before = "let value = \"var n = 1\"\n"
		let after = "let value = 1\n"
		let edited = try layer(before)
		_ = edited.replaceContent(with: after, transformer: { point($0, in: after) })
		let fresh = try layer(after)
		#expect(edited.snapshot()?.sublayerSnapshots.isEmpty == true)
		#expect(edited.snapshot()?.rootSnapshot.tree.rootNode?.sExpressionString == fresh.snapshot()?.rootSnapshot.tree.rootNode?.sExpressionString)
	}

	@Test func emptyDocumentRetiresAllRestrictedLayers() throws {
		let before = "let value = \"var n = 1\"\n"
		let edited = try layer(before)
		_ = edited.didChangeContent(.init(string: ""), using: InputEdit(
			startByte: 0, oldEndByte: before.utf16.count * 2, newEndByte: 0,
			startPoint: .zero, oldEndPoint: point(before.utf16.count, in: before), newEndPoint: .zero
		), resolveSublayers: false)
		_ = try edited.resolveSublayers(with: .init(string: ""), in: IndexSet())
		#expect(edited.snapshot()?.sublayerSnapshots.isEmpty == true)
	}

	@Test func partialQueryKeepsNarrowCapturesInsideAnotherLanguagesWideCapture() throws {
		let queryText = """
((array_literal) @injection.content (#set! injection.language "wide"))
((line_str_text) @injection.content (#set! injection.language "narrow"))
"""
		let base = LanguageLayerTests.swiftConfig
		let query = try Query(language: base.language, data: Data(queryText.utf8))
		var queries = base.queries
		queries[.injections] = query
		let outer = LanguageConfiguration(base.language, name: "outer", queries: queries)
		let configuration = LanguageLayer.Configuration(languageProvider: { name in
			LanguageConfiguration(base.language, name: name, queries: base.queries)
		})
		let source = #"let values = ["var one = 1", "var two = 2", "var three = 3"]"#
		let edited = try LanguageLayer(languageConfig: outer, configuration: configuration)
		_ = edited.replaceContent(with: source)
		let before = try #require(edited.snapshot()?.sublayerSnapshots.first {
			$0.rootSnapshot.data.name == "narrow"
		}?.rootSnapshot.tree.includedRanges)
		#expect(before.count == 3)
		let window = (source as NSString).range(of: "one")
		_ = try edited.resolveSublayers(with: .init(string: source), in: window)
		let after = try #require(edited.snapshot()?.sublayerSnapshots.first {
			$0.rootSnapshot.data.name == "narrow"
		}?.rootSnapshot.tree.includedRanges)
		#expect(after == before)
	}

	@Test func languageTagChangeRetiresBodyOutsideTheRequestedWindow() throws {
		let base = LanguageLayerTests.swiftConfig
		let query = try Query(language: base.language, data: Data("""
(function_declaration name: (simple_identifier) @injection.language body: (function_body) @injection.content)
""".utf8))
		var queries = base.queries
		queries[.injections] = query
		let outer = LanguageConfiguration(base.language, name: "outer", queries: queries)
		let configuration = LanguageLayer.Configuration(languageProvider: { name in
			LanguageConfiguration(base.language, name: name, queries: base.queries)
		})
		let before = "func old() { let n = 1 }"
		let after = "func new() { let n = 1 }"
		let layer = try LanguageLayer(languageConfig: outer, configuration: configuration)
		_ = layer.replaceContent(with: before)
		#expect(layer.snapshot()?.sublayerSnapshots.map { $0.rootSnapshot.data.name } == ["old"])
		let range = (before as NSString).range(of: "old")
		_ = layer.didChangeContent(.init(string: after), using: InputEdit(
			startByte: range.location * 2, oldEndByte: range.upperBound * 2, newEndByte: range.upperBound * 2,
			startPoint: point(range.location, in: before), oldEndPoint: point(range.upperBound, in: before),
			newEndPoint: point(range.upperBound, in: after)
		), resolveSublayers: false)
		_ = try layer.resolveSublayers(with: .init(string: after), in: range)
		#expect(layer.snapshot()?.sublayerSnapshots.map { $0.rootSnapshot.data.name } == ["new"])
	}

	@Test func rangeReplacementPreservesNeighborsAndInvalidatesRemovedExtent() {
		func range(_ lower: UInt32, _ upper: UInt32) -> TSRange {
			TSRange(points: Point(row: 0, column: Int(lower))..<Point(row: 0, column: Int(upper)), bytes: lower..<upper)
		}
		let result = LanguageLayer.replacingIncludedRanges(
			[range(20, 30), range(10, 10), range(10, 20), range(0, 10)],
			with: [range(14, 18), range(12, 14), range(14, 18)],
			in: IndexSet(integersIn: 6..<9)
		)
		#expect(result.ranges == [range(0, 10), range(12, 14), range(14, 18), range(20, 30)])
		#expect(result.invalidation == IndexSet(integersIn: 5..<10))
		let retired = LanguageLayer.replacingIncludedRanges([range(10, 20)], with: [], in: IndexSet(integersIn: 5..<10))
		#expect(retired.ranges.isEmpty)
		#expect(retired.invalidation == IndexSet(integersIn: 5..<10))
	}

	@Test func replacementAcrossInjectionsMatchesFreshParse() throws {
		let text = (0..<100).map { "let value\($0) = \"var n = 1\"\n" }.joined()
		let range = NSRange(location: text.utf16.count / 2, length: 600)
		try assertFreshEquivalent(text, edits: [Edit(
			range: range, replacement: (text as NSString).substring(with: range) + "y"
		)])
	}

	@Test func deletionAcrossInjectionsMatchesFreshParse() throws {
		let text = (0..<100).map { "let value\($0) = \"var n = 1\"\n" }.joined()
		try assertFreshEquivalent(text, edits: [Edit(range: NSRange(location: 900, length: 600), replacement: "")])
	}

	@Test func typingThenDeletionMatchesFreshParse() throws {
		let text = (0..<100).map { "let value\($0) = \"var n = 1\"\n" }.joined()
		try assertFreshEquivalent(text, edits: [
			Edit(range: NSRange(location: text.utf16.count / 2, length: 0), replacement: "x"),
			Edit(range: NSRange(location: 300, length: 600), replacement: ""),
		])
	}
}
