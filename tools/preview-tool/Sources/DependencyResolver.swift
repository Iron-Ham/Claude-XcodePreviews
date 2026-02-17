import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - ResolverResult

public struct ResolverResult {
  public let resolvedFiles: [String]
  public let excludedEntryPoints: [String]
  public let totalScanned: Int
}

// MARK: - DependencyResolverError

public enum DependencyResolverError: Error, CustomStringConvertible {
  case noFilesFound(directory: String)
  case startFileUnreadable(path: String)

  public var description: String {
    switch self {
    case .noFilesFound(let dir):
      "No Swift files found in \(dir)"
    case .startFileUnreadable(let path):
      "Cannot read start file: \(path)"
    }
  }
}

// MARK: - DependencyResolver

public struct DependencyResolver {

  // MARK: Public

  public init() {}

  public func resolve(startFile: String, sourcesDir: String) throws -> ResolverResult {
    let allFiles = findSwiftFiles(in: sourcesDir)
    let startAbs = (startFile as NSString).standardizingPath

    // Parse all files
    var analyses = [String: FileAnalysis]()
    for file in allFiles {
      let abs = (file as NSString).standardizingPath
      if let analysis = analyzeFile(path: abs, isStartFile: abs == startAbs) {
        analyses[abs] = analysis
      } else {
        log(.warning, "Could not read: \(abs)")
      }
    }

    // Also parse the start file if not under sourcesDir
    if analyses[startAbs] == nil {
      if let analysis = analyzeFile(path: startAbs, isStartFile: true) {
        analyses[startAbs] = analysis
      } else {
        throw DependencyResolverError.startFileUnreadable(path: startAbs)
      }
    }

    // Build lookup maps
    var symbolToFiles = [String: [String]]()
    var extensionFiles = [String: [String]]()

    for (path, analysis) in analyses {
      for type in analysis.declaredTypes {
        symbolToFiles[type, default: []].append(path)
      }
      for ext in analysis.extensions {
        extensionFiles[ext.type, default: []].append(path)
      }
    }

    // BFS from start file
    var resolved = Set<String>()
    var queue: [String] = [startAbs]
    var queueIndex = 0
    var excludedEntryPoints = [String]()

    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      guard !resolved.contains(current) else { continue }
      resolved.insert(current)

      guard let analysis = analyses[current] else { continue }

      for ref in analysis.referencedTypes {
        guard !frameworkTypes.contains(ref) else { continue }

        if let files = symbolToFiles[ref] {
          for file in files where !resolved.contains(file) {
            queue.append(file)
          }
        }
        if let files = extensionFiles[ref] {
          for file in files where !resolved.contains(file) {
            queue.append(file)
          }
        }
      }

      for declared in analysis.declaredTypes {
        if let files = extensionFiles[declared] {
          for file in files where !resolved.contains(file) {
            queue.append(file)
          }
        }
      }
    }

    // Remove entry point files (start file is never excluded — see makeAnalysis)
    var finalFiles = [String]()
    for path in resolved {
      if let analysis = analyses[path], analysis.hasEntryPoint {
        excludedEntryPoints.append((path as NSString).lastPathComponent)
      } else {
        finalFiles.append(path)
      }
    }
    finalFiles.sort()

    return ResolverResult(
      resolvedFiles: finalFiles,
      excludedEntryPoints: excludedEntryPoints,
      totalScanned: analyses.count
    )
  }

  // MARK: Private

  private func analyzeFile(path: String, isStartFile: Bool = false) -> FileAnalysis? {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
      return nil
    }
    let tree = Parser.parse(source: source)
    let visitor = DependencyVisitor(viewMode: .sourceAccurate)
    visitor.walk(tree)
    return visitor.makeAnalysis(path: path, isStartFile: isStartFile)
  }

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
