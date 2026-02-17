import Foundation
import XCTest

@testable import PreviewToolLib

// MARK: - CollectorEdgeCaseTests

final class CollectorEdgeCaseTests: XCTestCase {

  private let collector = DeclarationCollector()

  // MARK: 1. Property wrappers

  func testPropertyWrappers() {
    let source = """
      struct ProfileView {
        @State var name: String
        @Binding var value: Int
        @StateObject var viewModel: MyViewModel
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("ProfileView"))
    XCTAssertTrue(decl.referencedTypes.contains("MyViewModel"))
    // State, Binding, StateObject are framework types but still referenced via IdentifierTypeSyntax
    XCTAssertTrue(decl.referencedTypes.contains("State"))
    XCTAssertTrue(decl.referencedTypes.contains("Binding"))
    XCTAssertTrue(decl.referencedTypes.contains("StateObject"))
  }

  // MARK: 2. Generic type declarations

  func testGenericTypeDeclarations() {
    let source = """
      struct Container<T: Codable> {
        let value: T
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("Container"))
    XCTAssertTrue(decl.referencedTypes.contains("Codable"))
  }

  // MARK: 3. Generic constraints with where clause

  func testGenericConstraints() {
    let source = """
      struct Foo<T> where T: MyProtocol, T: Equatable {
        let item: T
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("Foo"))
    XCTAssertTrue(decl.referencedTypes.contains("MyProtocol"))
    XCTAssertTrue(decl.referencedTypes.contains("Equatable"))
  }

  // MARK: 4. Conditional compilation

  func testConditionalCompilation() {
    let source = """
      #if DEBUG
      struct DebugHelper {}
      #endif
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    // The #if config block should be collected as a declaration
    XCTAssertGreaterThanOrEqual(result.declarations.count, 1)
    let allDeclared = Set(result.declarations.flatMap(\.declaredTypes))
    XCTAssertTrue(allDeclared.contains("DebugHelper"))
  }

  // MARK: 5. Multiple attributes

  func testMultipleAttributes() {
    let source = """
      @available(iOS 17, *)
      @MainActor
      struct ModernView {
        let label: String
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("ModernView"))
  }

  // MARK: 6. Enum with associated values

  func testEnumWithAssociatedValues() {
    let source = """
      enum Result {
        case success(MyData)
        case failure(MyError)
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("Result"))
    XCTAssertTrue(decl.referencedTypes.contains("MyData"))
    XCTAssertTrue(decl.referencedTypes.contains("MyError"))
  }

  // MARK: 7. Enum with raw type

  func testEnumWithRawType() {
    let source = """
      enum Status: String {
        case active
        case inactive
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("Status"))
    XCTAssertTrue(decl.referencedTypes.contains("String"))
  }

  // MARK: 8. Closure properties

  func testClosureProperties() {
    let source = """
      struct Handler {
        var callback: (MyInput) -> MyOutput
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("Handler"))
    XCTAssertTrue(decl.referencedTypes.contains("MyInput"))
    XCTAssertTrue(decl.referencedTypes.contains("MyOutput"))
  }

  // MARK: 9. Static members

  func testStaticMembers() {
    let source = """
      struct Config {
        static let shared = Config()
        let theme: Theme
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("Config"))
    XCTAssertTrue(decl.referencedTypes.contains("Theme"))
  }

  // MARK: 10. Computed properties with complex return types

  func testComputedPropertyWithComplexReturnType() {
    let source = """
      struct ItemList {
        var items: [CustomItem] { [] }
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("ItemList"))
    XCTAssertTrue(decl.referencedTypes.contains("CustomItem"))
  }

  // MARK: 11. Protocol with associated type

  func testProtocolWithAssociatedType() {
    let source = """
      protocol DataSource {
        associatedtype Item
        func items() -> [Item]
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("DataSource"))
    // Item is declared as an associated type within the protocol, but the visitor
    // walks children, so it may or may not be in declaredTypes depending on
    // whether associatedtype declarations trigger struct/class/enum visit.
    // The key assertion is that the protocol itself is correctly parsed.
    XCTAssertFalse(decl.hasEntryPoint)
  }

  // MARK: 12. Multiple inheritance

  func testMultipleInheritance() {
    let source = """
      class VC: UIViewController, MyDelegate, DataProvider {
        override func viewDidLoad() {}
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("VC"))
    XCTAssertTrue(decl.referencedTypes.contains("UIViewController"))
    XCTAssertTrue(decl.referencedTypes.contains("MyDelegate"))
    XCTAssertTrue(decl.referencedTypes.contains("DataProvider"))
  }

  // MARK: 13. Deeply nested types

  func testDeeplyNestedTypes() {
    let source = """
      struct Outer {
        struct Middle {
          struct Inner {
            let value: Int
          }
          let inner: Inner
        }
        let middle: Middle
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("Outer"))
    XCTAssertTrue(decl.declaredTypes.contains("Middle"))
    XCTAssertTrue(decl.declaredTypes.contains("Inner"))
  }

  // MARK: 14. Class with deinit

  func testClassWithDeinit() {
    let source = """
      class ResourceManager {
        var resource: MyResource?
        deinit {
          resource = nil
        }
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("ResourceManager"))
    XCTAssertTrue(decl.referencedTypes.contains("MyResource"))
  }

  // MARK: 15. Subscript declarations

  func testSubscriptDeclarations() {
    let source = """
      struct Cache {
        subscript(key: MyKey) -> MyValue? { nil }
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    let decl = result.declarations[0]
    XCTAssertTrue(decl.declaredTypes.contains("Cache"))
    XCTAssertTrue(decl.referencedTypes.contains("MyKey"))
    XCTAssertTrue(decl.referencedTypes.contains("MyValue"))
  }
}

// MARK: - ResolverEdgeCaseTests

final class ResolverEdgeCaseTests: XCTestCase {

  private var tmpDir: String!
  private var sourcesDir: String!
  private let fm = FileManager.default
  private let resolver = DeclarationResolver()

  override func setUp() {
    super.setUp()
    tmpDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("ResolverEdgeCaseTests_\(UUID().uuidString)")
    sourcesDir = (tmpDir as NSString).appendingPathComponent("Sources")
    try! fm.createDirectory(atPath: sourcesDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? fm.removeItem(atPath: tmpDir)
    super.tearDown()
  }

  // MARK: Helper

  @discardableResult
  private func writeFile(_ name: String, content: String, in dir: String? = nil) -> String {
    let directory = dir ?? sourcesDir!
    let path = (directory as NSString).appendingPathComponent(name)
    try! content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }

  // MARK: 16. Diamond dependency

  func testDiamondDependency() throws {
    let startFile = writeFile("A.swift", content: """
      struct A {
        let b: B
        let c: C
      }
      """)

    writeFile("B.swift", content: """
      struct B {
        let d: D
      }
      """)

    writeFile("C.swift", content: """
      struct C {
        let d: D
      }
      """)

    writeFile("D.swift", content: """
      struct D {
        let value: Int
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["A"]
    )

    XCTAssertTrue(result.generatedSource.contains("struct A"))
    XCTAssertTrue(result.generatedSource.contains("struct B"))
    XCTAssertTrue(result.generatedSource.contains("struct C"))
    XCTAssertTrue(result.generatedSource.contains("struct D"))
    // D should be included exactly once (the source text appears once)
    let dOccurrences = result.generatedSource.components(separatedBy: "struct D").count - 1
    XCTAssertEqual(dOccurrences, 1)
  }

  // MARK: 17. Large fan-out

  func testLargeFanOut() throws {
    var startSource = "struct Start {\n"
    for i in 1...10 {
      startSource += "  let dep\(i): Dep\(i)\n"
    }
    startSource += "}\n"

    let startFile = writeFile("Start.swift", content: startSource)

    for i in 1...10 {
      writeFile("Dep\(i).swift", content: """
        struct Dep\(i) {
          let value: Int
        }
        """)
    }

    writeFile("Orphan.swift", content: """
      struct Orphan {
        let data: String
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Start"]
    )

    XCTAssertTrue(result.generatedSource.contains("struct Start"))
    for i in 1...10 {
      XCTAssertTrue(result.generatedSource.contains("struct Dep\(i)"), "Dep\(i) should be resolved")
    }
    XCTAssertFalse(result.generatedSource.contains("Orphan"))
  }

  // MARK: 18. Deep chain

  func testDeepChain() throws {
    let startFile = writeFile("A.swift", content: """
      struct A {
        let next: B
      }
      """)

    writeFile("B.swift", content: """
      struct B {
        let next: C
      }
      """)

    writeFile("C.swift", content: """
      struct C {
        let next: D
      }
      """)

    writeFile("D.swift", content: """
      struct D {
        let next: E
      }
      """)

    writeFile("E.swift", content: """
      struct E {
        let next: F
      }
      """)

    writeFile("F.swift", content: """
      struct F {
        let value: Int
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["A"]
    )

    for name in ["A", "B", "C", "D", "E", "F"] {
      XCTAssertTrue(result.generatedSource.contains("struct \(name)"), "\(name) should be resolved in deep chain")
    }
  }

  // MARK: 19. File with only extensions

  func testFileWithOnlyExtensions() throws {
    let startFile = writeFile("Start.swift", content: """
      struct MyModel {
        let name: String
      }
      """)

    writeFile("Extensions.swift", content: """
      extension MyModel {
        func display() -> String { name }
      }

      extension MyModel {
        var uppercased: String { name.uppercased() }
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["MyModel"]
    )

    XCTAssertTrue(result.generatedSource.contains("struct MyModel"))
    XCTAssertTrue(result.generatedSource.contains("extension MyModel"))
    XCTAssertTrue(result.generatedSource.contains("display"))
    XCTAssertTrue(result.generatedSource.contains("uppercased"))
  }

  // MARK: 20. Mixed @main and useful types

  func testMixedMainAndUsefulTypes() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Viewer {
        let helper: AppHelper
      }
      """)

    writeFile("AppEntry.swift", content: """
      @main
      struct MyApp {
        var body: some Scene { WindowGroup { Text("hi") } }
      }

      struct AppHelper {
        let value: Int
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Viewer"]
    )

    XCTAssertTrue(result.generatedSource.contains("Viewer"))
    XCTAssertTrue(result.generatedSource.contains("AppHelper"))
    XCTAssertFalse(result.generatedSource.contains("MyApp"))
  }

  // MARK: 21. Type used only in extension conformance

  func testTypeUsedOnlyInExtensionConformance() throws {
    let startFile = writeFile("Start.swift", content: """
      struct MyType {
        let value: Int
      }
      """)

    writeFile("Conformance.swift", content: """
      extension MyType: SomeProtocol {
        func doSomething() {}
      }
      """)

    writeFile("SomeProtocol.swift", content: """
      protocol SomeProtocol {
        func doSomething()
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["MyType"]
    )

    XCTAssertTrue(result.generatedSource.contains("struct MyType"))
    // The extension of MyType is pulled in, which references SomeProtocol
    XCTAssertTrue(result.generatedSource.contains("extension MyType: SomeProtocol"))
    XCTAssertTrue(result.generatedSource.contains("protocol SomeProtocol"))
  }

  // MARK: 22. Empty sources directory

  func testEmptySourcesDirectory() throws {
    let emptyDir = (tmpDir as NSString).appendingPathComponent("EmptySources")
    try fm.createDirectory(atPath: emptyDir, withIntermediateDirectories: true)

    let externalDir = (tmpDir as NSString).appendingPathComponent("External")
    try fm.createDirectory(atPath: externalDir, withIntermediateDirectories: true)

    let startFile = writeFile("Start.swift", content: """
      struct OnlyMe {
        let value: Int
      }
      """, in: externalDir)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: emptyDir,
      previewReferencedTypes: ["OnlyMe"]
    )

    XCTAssertTrue(result.generatedSource.contains("OnlyMe"))
    XCTAssertEqual(result.resolvedDeclarations, 1)
  }

  // MARK: 23. Start file unreadable

  func testStartFileUnreadable() {
    let nonexistent = (tmpDir as NSString).appendingPathComponent("doesnotexist.swift")

    XCTAssertThrowsError(
      try resolver.resolve(
        startFile: nonexistent,
        sourcesDir: sourcesDir,
        previewReferencedTypes: []
      )
    ) { error in
      guard let resolverError = error as? DeclarationResolverError else {
        XCTFail("Expected DeclarationResolverError but got \(type(of: error))")
        return
      }
      if case .startFileUnreadable(let path) = resolverError {
        XCTAssertTrue(path.contains("doesnotexist.swift"))
      } else {
        XCTFail("Expected startFileUnreadable error")
      }
    }
  }

  // MARK: 24. Very large file with many declarations

  func testVeryLargeFileWithManyDeclarations() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Start {
        let needed: Type1
      }
      """)

    var largeFileContent = ""
    for i in 1...50 {
      largeFileContent += """
        struct Type\(i) {
          let value: Int
        }

        """
    }
    writeFile("LargeFile.swift", content: largeFileContent)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Start"]
    )

    XCTAssertTrue(result.generatedSource.contains("struct Start"))
    XCTAssertTrue(result.generatedSource.contains("struct Type1"))
    // Only Type1 should be resolved, not all 50
    XCTAssertFalse(result.generatedSource.contains("struct Type50"))
    XCTAssertEqual(result.totalDeclarations, 51) // 1 (Start) + 50 (Types)
    // Start + Type1 = 2 resolved
    XCTAssertEqual(result.resolvedDeclarations, 2)
  }

  // MARK: 25. Same type name in different files

  func testSameTypeNameDifferentFiles() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Start {
        let config: Config
      }
      """)

    writeFile("ConfigA.swift", content: """
      struct Config {
        let name: String
      }
      """)

    writeFile("ConfigB.swift", content: """
      struct Config {
        let value: Int
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Start"]
    )

    XCTAssertTrue(result.generatedSource.contains("struct Start"))
    // Both Config declarations should be included since both map to the same type name
    let configCount = result.generatedSource.components(separatedBy: "struct Config").count - 1
    XCTAssertEqual(configCount, 2)
  }
}

// MARK: - DependencyResolverTests (file-level)

final class DependencyResolverEdgeCaseTests: XCTestCase {

  private var tmpDir: String!
  private var sourcesDir: String!
  private let fm = FileManager.default
  private let resolver = DependencyResolver()

  override func setUp() {
    super.setUp()
    tmpDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("DependencyResolverEdgeCaseTests_\(UUID().uuidString)")
    sourcesDir = (tmpDir as NSString).appendingPathComponent("Sources")
    try! fm.createDirectory(atPath: sourcesDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? fm.removeItem(atPath: tmpDir)
    super.tearDown()
  }

  // MARK: Helper

  @discardableResult
  private func writeFile(_ name: String, content: String, in dir: String? = nil) -> String {
    let directory = dir ?? sourcesDir!
    let path = (directory as NSString).appendingPathComponent(name)
    try! content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }

  // MARK: 26. Simple file-level resolution

  func testSimpleFileLevelResolution() throws {
    let startFile = writeFile("Start.swift", content: """
      struct StartView {
        let model: DataModel
      }
      """)

    let modelFile = writeFile("DataModel.swift", content: """
      struct DataModel {
        let name: String
      }
      """)

    writeFile("Unrelated.swift", content: """
      struct Unrelated {
        let value: Int
      }
      """)

    let result = try resolver.resolve(startFile: startFile, sourcesDir: sourcesDir)

    XCTAssertTrue(result.resolvedFiles.contains(startFile))
    XCTAssertTrue(result.resolvedFiles.contains(modelFile))
    // Unrelated should not be included
    let unrelatedPath = (sourcesDir as NSString).appendingPathComponent("Unrelated.swift")
    XCTAssertFalse(result.resolvedFiles.contains(unrelatedPath))
  }

  // MARK: 27. Transitive file resolution

  func testTransitiveFileResolution() throws {
    let startFile = writeFile("A.swift", content: """
      struct A {
        let b: B
      }
      """)

    let bFile = writeFile("B.swift", content: """
      struct B {
        let c: C
      }
      """)

    let cFile = writeFile("C.swift", content: """
      struct C {
        let value: Int
      }
      """)

    let result = try resolver.resolve(startFile: startFile, sourcesDir: sourcesDir)

    XCTAssertTrue(result.resolvedFiles.contains(startFile))
    XCTAssertTrue(result.resolvedFiles.contains(bFile))
    XCTAssertTrue(result.resolvedFiles.contains(cFile))
  }

  // MARK: 28. File-level includes whole file (no declaration precision)

  func testFileLevelIncludesWholeFile() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Start {
        let needed: NeededModel
      }
      """)

    let modelsFile = writeFile("Models.swift", content: """
      struct NeededModel {
        let value: Int
      }

      struct UnneededModel {
        let other: String
      }
      """)

    let result = try resolver.resolve(startFile: startFile, sourcesDir: sourcesDir)

    // File-level resolver includes the whole file, so both models are in the resolved files
    XCTAssertTrue(result.resolvedFiles.contains(startFile))
    XCTAssertTrue(result.resolvedFiles.contains(modelsFile))
    // Both NeededModel AND UnneededModel are in the same file, so both are included
    XCTAssertEqual(result.resolvedFiles.count, 2)
  }

  // MARK: 29. Circular file references

  func testCircularFileReferences() throws {
    let fileA = writeFile("NodeA.swift", content: """
      struct NodeA {
        var neighbor: NodeB?
      }
      """)

    let fileB = writeFile("NodeB.swift", content: """
      struct NodeB {
        var neighbor: NodeA?
      }
      """)

    let result = try resolver.resolve(startFile: fileA, sourcesDir: sourcesDir)

    XCTAssertTrue(result.resolvedFiles.contains(fileA))
    XCTAssertTrue(result.resolvedFiles.contains(fileB))
    // Should not hang or crash
  }

  // MARK: 30. Extension files included

  func testExtensionFilesIncluded() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Person {
        let name: String
      }
      """)

    let extFile = writeFile("PersonExt.swift", content: """
      extension Person {
        var greeting: String { "Hello, \\(name)!" }
      }
      """)

    let result = try resolver.resolve(startFile: startFile, sourcesDir: sourcesDir)

    XCTAssertTrue(result.resolvedFiles.contains(startFile))
    XCTAssertTrue(result.resolvedFiles.contains(extFile))
  }

  // MARK: 31. @main file excluded

  func testMainFileExcluded() throws {
    let startFile = writeFile("Start.swift", content: """
      struct UsefulModel {
        let helper: AppHelper
      }
      """)

    writeFile("AppEntry.swift", content: """
      @main
      struct MyApp {
        var body: some Scene { WindowGroup { Text("hi") } }
      }

      struct AppHelper {
        let value: Int
      }
      """)

    let result = try resolver.resolve(startFile: startFile, sourcesDir: sourcesDir)

    // The start file should be included
    XCTAssertTrue(result.resolvedFiles.contains(startFile))
    // The @main file is pulled in because it also declares AppHelper,
    // but it has an @main entry point, so it should be excluded from resolvedFiles
    // and listed in excludedEntryPoints
    let appEntryPath = (sourcesDir as NSString).appendingPathComponent("AppEntry.swift")
    XCTAssertFalse(result.resolvedFiles.contains(appEntryPath))
    XCTAssertTrue(result.excludedEntryPoints.contains("AppEntry.swift"))
  }

  // MARK: 32. Framework types not followed

  func testFrameworkTypesNotFollowed() throws {
    let startFile = writeFile("Start.swift", content: """
      struct MyWidget {
        let text: String
        let color: Color
        let items: [Int]
      }
      """)

    writeFile("StringHelper.swift", content: """
      struct StringHelper {
        func help() {}
      }
      """)

    writeFile("ColorHelper.swift", content: """
      struct ColorHelper {
        func adjust() {}
      }
      """)

    let result = try resolver.resolve(startFile: startFile, sourcesDir: sourcesDir)

    XCTAssertTrue(result.resolvedFiles.contains(startFile))
    // String, Color, Int are framework types, so their files should not be pulled in
    let stringHelperPath = (sourcesDir as NSString).appendingPathComponent("StringHelper.swift")
    let colorHelperPath = (sourcesDir as NSString).appendingPathComponent("ColorHelper.swift")
    XCTAssertFalse(result.resolvedFiles.contains(stringHelperPath))
    XCTAssertFalse(result.resolvedFiles.contains(colorHelperPath))
    XCTAssertEqual(result.resolvedFiles.count, 1)
  }

  // MARK: 33. Empty sources directory

  func testEmptySourcesDirectory() throws {
    let emptyDir = (tmpDir as NSString).appendingPathComponent("EmptySources")
    try fm.createDirectory(atPath: emptyDir, withIntermediateDirectories: true)

    let externalDir = (tmpDir as NSString).appendingPathComponent("External")
    try fm.createDirectory(atPath: externalDir, withIntermediateDirectories: true)

    let startFile = writeFile("Start.swift", content: """
      struct OnlyMe {
        let value: Int
      }
      """, in: externalDir)

    let result = try resolver.resolve(startFile: startFile, sourcesDir: emptyDir)

    XCTAssertTrue(result.resolvedFiles.contains(startFile))
    XCTAssertEqual(result.resolvedFiles.count, 1)
  }

  // MARK: 34. Start file unreadable

  func testStartFileUnreadable() {
    let nonexistent = (tmpDir as NSString).appendingPathComponent("doesnotexist.swift")

    XCTAssertThrowsError(
      try resolver.resolve(startFile: nonexistent, sourcesDir: sourcesDir)
    ) { error in
      guard let resolverError = error as? DependencyResolverError else {
        XCTFail("Expected DependencyResolverError but got \(type(of: error))")
        return
      }
      if case .startFileUnreadable(let path) = resolverError {
        XCTAssertTrue(path.contains("doesnotexist.swift"))
      } else {
        XCTFail("Expected startFileUnreadable error")
      }
    }
  }
}
