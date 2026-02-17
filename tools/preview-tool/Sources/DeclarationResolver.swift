import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - DeclarationInfo

public struct DeclarationInfo {
  public let source: String
  public let declaredTypes: Set<String>
  public let referencedTypes: Set<String>
  public let extendedType: String?
  public let hasEntryPoint: Bool
  public let filePath: String

  public var isExtension: Bool { extendedType != nil }
}

// MARK: - DeclarationResolverResult

public struct DeclarationResolverResult {
  public let generatedSource: String
  public let imports: Set<String>
  public let contributingFiles: [String]
  public let totalDeclarations: Int
  public let resolvedDeclarations: Int
}

// MARK: - DeclarationCollector

public struct DeclarationCollector {

  public struct FileResult {
    public let declarations: [DeclarationInfo]
    public let imports: Set<String>
  }

  public init() {}

  public func collect(filePath: String) -> FileResult? {
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
      return nil
    }
    return collect(source: source, filePath: filePath)
  }

  public func collect(source: String, filePath: String) -> FileResult {
    let tree = Parser.parse(source: source)
    var declarations = [DeclarationInfo]()
    var imports = Set<String>()

    for item in tree.statements {
      let syntax = item.item

      // Collect imports separately
      if let importDecl = syntax.as(ImportDeclSyntax.self) {
        let module = importDecl.path.map(\.name.text).joined(separator: ".")
        imports.insert(module)
        continue
      }

      // Skip #Preview macros (handles both decl and expr parsing variants)
      if let macroDecl = syntax.as(MacroExpansionDeclSyntax.self),
        macroDecl.macroName.text == "Preview"
      {
        continue
      }
      if syntax.as(MacroExpansionExprSyntax.self)?.macroName.text == "Preview" {
        continue
      }

      // Analyze this declaration
      let visitor = DependencyVisitor(viewMode: .sourceAccurate)
      visitor.walk(syntax)

      let extendedType = syntax.as(ExtensionDeclSyntax.self)
        .map { $0.extendedType.trimmedDescription }

      let info = DeclarationInfo(
        source: item.trimmedDescription,
        declaredTypes: visitor.declaredTypes,
        referencedTypes: visitor.referencedTypes.subtracting(visitor.declaredTypes),
        extendedType: extendedType,
        hasEntryPoint: visitor.hasEntryPoint,
        filePath: filePath
      )
      declarations.append(info)
    }

    return FileResult(declarations: declarations, imports: imports)
  }
}

// MARK: - DeclarationResolverError

public enum DeclarationResolverError: Error, CustomStringConvertible {
  case startFileUnreadable(path: String)

  public var description: String {
    switch self {
    case .startFileUnreadable(let path):
      "Cannot read start file: \(path)"
    }
  }
}

// MARK: - DeclarationResolver

public struct DeclarationResolver {

  public init() {}

  public func resolve(
    startFile: String,
    sourcesDir: String,
    previewReferencedTypes: Set<String>
  ) throws -> DeclarationResolverResult {
    let startAbs = (startFile as NSString).standardizingPath
    let allFiles = findSwiftFiles(in: sourcesDir)
    let collector = DeclarationCollector()

    // Parse all files into declarations
    var allDeclarations = [DeclarationInfo]()
    var allImports = Set<String>()
    var fileImports = [String: Set<String>]()

    for file in allFiles {
      let abs = (file as NSString).standardizingPath
      guard let result = collector.collect(filePath: abs) else {
        log(.warning, "Could not read: \(abs)")
        continue
      }
      allDeclarations.append(contentsOf: result.declarations)
      allImports.formUnion(result.imports)
      fileImports[abs] = result.imports
    }

    // Also parse start file if not under sourcesDir
    if !allDeclarations.contains(where: { $0.filePath == startAbs }) {
      guard let result = collector.collect(filePath: startAbs) else {
        throw DeclarationResolverError.startFileUnreadable(path: startAbs)
      }
      allDeclarations.append(contentsOf: result.declarations)
      allImports.formUnion(result.imports)
      fileImports[startAbs] = result.imports
    }

    // Build lookup maps: type name → declaration indices
    var typeToIndices = [String: [Int]]()
    var extensionIndices = [String: [Int]]()

    for (index, decl) in allDeclarations.enumerated() {
      for type in decl.declaredTypes {
        typeToIndices[type, default: []].append(index)
      }
      if let extType = decl.extendedType {
        extensionIndices[extType, default: []].append(index)
      }
    }

    // Seed BFS
    var resolved = Set<Int>()
    var queue = [Int]()

    // (a) All start-file declarations (minus @main)
    for (index, decl) in allDeclarations.enumerated() {
      if decl.filePath == startAbs, !decl.hasEntryPoint {
        queue.append(index)
      }
    }

    // (b) Types referenced by preview body
    for type in previewReferencedTypes {
      guard !frameworkTypes.contains(type) else { continue }
      if let indices = typeToIndices[type] {
        queue.append(contentsOf: indices)
      }
      if let indices = extensionIndices[type] {
        queue.append(contentsOf: indices)
      }
    }

    // BFS (index-based to avoid O(n) removeFirst)
    var queueIndex = 0
    while queueIndex < queue.count {
      let index = queue[queueIndex]
      queueIndex += 1
      guard !resolved.contains(index) else { continue }

      let decl = allDeclarations[index]

      // Skip @main declarations
      if decl.hasEntryPoint { continue }

      resolved.insert(index)

      // Follow referenced types → type declarations + extensions
      for ref in decl.referencedTypes {
        guard !frameworkTypes.contains(ref) else { continue }

        if let indices = typeToIndices[ref] {
          for i in indices where !resolved.contains(i) {
            queue.append(i)
          }
        }
        if let indices = extensionIndices[ref] {
          for i in indices where !resolved.contains(i) {
            queue.append(i)
          }
        }
      }

      // Also include extensions of any type declared in this declaration
      for declared in decl.declaredTypes {
        if let indices = extensionIndices[declared] {
          for i in indices where !resolved.contains(i) {
            queue.append(i)
          }
        }
      }
    }

    // Safety net: include non-type declarations (top-level funcs/vars) from contributing files
    let filesBeforeSafetyNet = Set(resolved.map { allDeclarations[$0].filePath })

    for (index, decl) in allDeclarations.enumerated() {
      if !resolved.contains(index),
        !decl.hasEntryPoint,
        decl.declaredTypes.isEmpty,
        !decl.isExtension,
        filesBeforeSafetyNet.contains(decl.filePath)
      {
        resolved.insert(index)
      }
    }

    // Collect imports from final contributing files (after safety net)
    var contributingFiles = Set<String>()
    var resolvedImports = Set<String>()
    for index in resolved {
      let filePath = allDeclarations[index].filePath
      contributingFiles.insert(filePath)
      if let imports = fileImports[filePath] {
        resolvedImports.formUnion(imports)
      }
    }

    // Generate merged source
    var output = "// Auto-generated by DeclarationResolver\n"
    output += "// Resolved \(resolved.count) declarations from \(contributingFiles.count) files\n\n"

    // Sorted imports
    let sortedImports = resolvedImports.sorted()
    for imp in sortedImports {
      output += "import \(imp)\n"
    }
    if !sortedImports.isEmpty {
      output += "\n"
    }

    // Declaration source text in stable order (by original index)
    let sortedIndices = resolved.sorted()
    for index in sortedIndices {
      output += allDeclarations[index].source
      output += "\n\n"
    }

    return DeclarationResolverResult(
      generatedSource: output,
      imports: resolvedImports,
      contributingFiles: contributingFiles.sorted(),
      totalDeclarations: allDeclarations.count,
      resolvedDeclarations: resolved.count
    )
  }

  // MARK: Private

  private func findSwiftFiles(in directory: String) -> [String] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(atPath: directory) else {
      log(.warning, "Cannot enumerate directory: \(directory)")
      return []
    }
    var files = [String]()
    while let rel = enumerator.nextObject() as? String {
      if rel.hasSuffix(".swift") {
        let abs = (directory as NSString).appendingPathComponent(rel)
        files.append(abs)
      }
    }
    return files
  }
}
