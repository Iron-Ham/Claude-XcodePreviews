import SwiftSyntax

// MARK: - FileAnalysis

public struct FileAnalysis {
  public let path: String
  public var declaredTypes = Set<String>()
  public var referencedTypes = Set<String>()
  public var extensions = [(type: String, conformances: [String])]()
  public var imports = Set<String>()
  public var hasEntryPoint = false
}

// MARK: - DependencyVisitor

public final class DependencyVisitor: SyntaxVisitor {

  // MARK: Public

  public var declaredTypes = Set<String>()
  public var referencedTypes = Set<String>()
  public var extensions = [(type: String, conformances: [String])]()
  public var imports = Set<String>()
  public var hasEntryPoint = false

  override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    declaredTypes.insert(node.name.text)
    collectInheritance(node.inheritanceClause)
    checkForMainAttribute(node.attributes)
    return .visitChildren
  }

  override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    declaredTypes.insert(node.name.text)
    collectInheritance(node.inheritanceClause)
    checkForMainAttribute(node.attributes)
    return .visitChildren
  }

  override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    declaredTypes.insert(node.name.text)
    collectInheritance(node.inheritanceClause)
    checkForMainAttribute(node.attributes)
    return .visitChildren
  }

  override public func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    declaredTypes.insert(node.name.text)
    collectInheritance(node.inheritanceClause)
    return .visitChildren
  }

  override public func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    declaredTypes.insert(node.name.text)
    collectInheritance(node.inheritanceClause)
    checkForMainAttribute(node.attributes)
    return .visitChildren
  }

  override public func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
    declaredTypes.insert(node.name.text)
    return .visitChildren
  }

  override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    let extendedType = node.extendedType.trimmedDescription
    referencedTypes.insert(extendedType)
    var conformances = [String]()
    if let inheritance = node.inheritanceClause {
      for item in inheritance.inheritedTypes {
        let name = item.type.trimmedDescription
        conformances.append(name)
        referencedTypes.insert(name)
      }
    }
    extensions.append((type: extendedType, conformances: conformances))
    return .visitChildren
  }

  override public func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
    let name = node.name.text
    if isPascalCase(name) {
      referencedTypes.insert(name)
    }
    return .visitChildren
  }

  override public func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    let name = node.baseName.text
    if isPascalCase(name) {
      referencedTypes.insert(name)
    }
    return .visitChildren
  }

  override public func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    let module = node.path.map(\.name.text).joined(separator: ".")
    imports.insert(module)
    return .skipChildren
  }

  /// Build analysis for a file. When `isStartFile` is true, the entry point
  /// flag is recorded but will NOT cause the file to be excluded from results.
  public func makeAnalysis(path: String, isStartFile: Bool = false) -> FileAnalysis {
    var analysis = FileAnalysis(path: path)
    analysis.declaredTypes = declaredTypes
    analysis.referencedTypes = referencedTypes.subtracting(declaredTypes)
    analysis.extensions = extensions
    analysis.imports = imports
    // Fix issue #7: never mark the start file as an entry point for exclusion
    analysis.hasEntryPoint = isStartFile ? false : hasEntryPoint
    return analysis
  }

  // MARK: Private

  private func collectInheritance(_ clause: InheritanceClauseSyntax?) {
    guard let clause else { return }
    for item in clause.inheritedTypes {
      let name = item.type.trimmedDescription
      if isPascalCase(name) {
        referencedTypes.insert(name)
      }
    }
  }

  private func checkForMainAttribute(_ attributes: AttributeListSyntax) {
    for attr in attributes {
      if let attribute = attr.as(AttributeSyntax.self) {
        let name = attribute.attributeName.trimmedDescription
        if name == "main" || name == "UIApplicationMain" || name == "NSApplicationMain" {
          hasEntryPoint = true
        }
      }
    }
  }

  private func isPascalCase(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    return first.isUppercase && first.isLetter
  }

}
