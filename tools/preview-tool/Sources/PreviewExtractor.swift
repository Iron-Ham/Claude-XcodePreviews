import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - PreviewExtractorError

public enum PreviewExtractorError: Error, CustomStringConvertible {
  case fileNotFound(String)
  case noPreviewFound(String)
  case emptyPreviewBody(String)

  public var description: String {
    switch self {
    case .fileNotFound(let path):
      "File not found: \(path)"
    case .noPreviewFound(let path):
      "No #Preview macro found in \(path)"
    case .emptyPreviewBody(let path):
      "#Preview body is empty in \(path)"
    }
  }
}

// MARK: - PreviewExtractor

public struct PreviewExtractor {

  // MARK: Public

  public init() {}

  /// Extract the body of the first `#Preview { ... }` macro from a Swift file.
  /// Uses SwiftSyntax AST parsing — correctly handles string literals,
  /// comments, and nested braces (fixes issue #10).
  public func extract(from filePath: String) throws -> String {
    let source: String
    do {
      source = try String(contentsOfFile: filePath, encoding: .utf8)
    } catch {
      throw PreviewExtractorError.fileNotFound("\(filePath): \(error.localizedDescription)")
    }

    let tree = Parser.parse(source: source)
    let finder = PreviewFinder(viewMode: .sourceAccurate)
    finder.walk(tree)

    guard let body = finder.previewBody else {
      throw PreviewExtractorError.noPreviewFound(filePath)
    }

    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw PreviewExtractorError.emptyPreviewBody(filePath)
    }

    return dedent(trimmed)
  }

  /// Extract import statements from a Swift file.
  public func extractImports(from filePath: String) -> [String] {
    let source: String
    do {
      source = try String(contentsOfFile: filePath, encoding: .utf8)
    } catch {
      log(.warning, "Cannot read file for imports: \(filePath): \(error)")
      return []
    }
    let tree = Parser.parse(source: source)
    let visitor = ImportCollector(viewMode: .sourceAccurate)
    visitor.walk(tree)
    return visitor.imports.sorted()
  }

  /// Extract types referenced by a source fragment (e.g. preview body).
  /// Used to seed declaration-level BFS from `#Preview { MyView() }`.
  public func extractReferencedTypes(fromSource source: String) -> Set<String> {
    let tree = Parser.parse(source: source)
    let visitor = DependencyVisitor(viewMode: .sourceAccurate)
    visitor.walk(tree)
    return visitor.referencedTypes
  }

  // MARK: Private

  /// Remove common leading whitespace from all lines.
  private func dedent(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0) }

    let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard !nonEmptyLines.isEmpty else { return text }

    let minIndent = nonEmptyLines.map { line in
      line.prefix(while: { $0 == " " || $0 == "\t" }).count
    }.min() ?? 0

    if minIndent == 0 { return text }

    return lines.map { line in
      if line.count >= minIndent {
        return String(line.dropFirst(minIndent))
      }
      return line
    }.joined(separator: "\n")
  }
}

// MARK: - PreviewFinder

/// Walks the AST to find the first `#Preview` macro expansion and extract its
/// trailing closure body.
private final class PreviewFinder: SyntaxVisitor {
  var previewBody: String?

  override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
    guard previewBody == nil else { return .skipChildren }

    if node.macroName.text == "Preview" {
      if let closure = node.trailingClosure {
        // Extract the source text of the closure body (between { and })
        let body = closure.statements.trimmedDescription
        previewBody = body
      }
    }
    return .skipChildren
  }

  override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
    guard previewBody == nil else { return .skipChildren }

    if node.macroName.text == "Preview" {
      if let closure = node.trailingClosure {
        let body = closure.statements.trimmedDescription
        previewBody = body
      }
    }
    return .skipChildren
  }
}

// MARK: - ImportCollector

/// Collects import module names from the AST.
private final class ImportCollector: SyntaxVisitor {
  var imports = [String]()

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    let module = node.path.map(\.name.text).joined(separator: ".")
    imports.append(module)
    return .skipChildren
  }
}
