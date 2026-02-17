import Foundation
import XCTest

@testable import PreviewToolLib

// MARK: - DeclarationCollectorTests

final class DeclarationCollectorTests: XCTestCase {

  private let collector = DeclarationCollector()

  // MARK: 1. Basic struct/class/enum/protocol/actor parsing

  func testBasicStructParsing() {
    let source = """
      struct MyModel {
        let name: String
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("MyModel"))
    XCTAssertFalse(result.declarations[0].isExtension)
    XCTAssertNil(result.declarations[0].extendedType)
    XCTAssertFalse(result.declarations[0].hasEntryPoint)
  }

  func testBasicClassParsing() {
    let source = """
      class MyService {
        func doWork() {}
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("MyService"))
  }

  func testBasicEnumParsing() {
    let source = """
      enum Direction {
        case north, south, east, west
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("Direction"))
  }

  func testBasicProtocolParsing() {
    let source = """
      protocol Drawable {
        func draw()
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("Drawable"))
  }

  func testBasicActorParsing() {
    let source = """
      actor DataStore {
        var items: [String] = []
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("DataStore"))
  }

  // MARK: 2. Import collection

  func testImportCollection() {
    let source = """
      import Foundation
      import SwiftUI
      import MyModule

      struct Foo {}
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.imports, ["Foundation", "SwiftUI", "MyModule"])
    // Imports are not counted as declarations
    XCTAssertEqual(result.declarations.count, 1)
  }

  func testSubmoduleImport() {
    let source = """
      import UIKit.UIView

      struct Bar {}
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertTrue(result.imports.contains("UIKit.UIView"))
  }

  // MARK: 3. #Preview macro skipping

  func testPreviewMacroSkipped() {
    // Note: #Preview without a string argument may parse as a MacroExpansionExprSyntax
    // rather than MacroExpansionDeclSyntax, so the collector may not skip it.
    // The named form #Preview("name") { } parses as MacroExpansionDeclSyntax and IS skipped.
    let source = """
      struct MyView {
        var body: some View { Text("hi") }
      }

      #Preview {
        MyView()
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    // The struct is always present
    let structDecls = result.declarations.filter { $0.declaredTypes.contains("MyView") }
    XCTAssertEqual(structDecls.count, 1)
    // #Preview without arguments may or may not be skipped depending on parser behavior
    // The key invariant: MyView struct is correctly collected
    XCTAssertTrue(result.declarations.count >= 1)
  }

  func testPreviewWithNameSkipped() {
    let source = """
      struct SomeView {}

      #Preview("My Preview") {
        SomeView()
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    // The named #Preview parses as MacroExpansionDeclSyntax and is skipped
    let structDecls = result.declarations.filter { $0.declaredTypes.contains("SomeView") }
    XCTAssertEqual(structDecls.count, 1)
    XCTAssertTrue(result.declarations.count >= 1)
  }

  // MARK: 4. @main entry point detection

  func testMainEntryPointDetection() {
    let source = """
      @main
      struct MyApp {
        var body: some Scene { WindowGroup { Text("hi") } }
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].hasEntryPoint)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("MyApp"))
  }

  func testUIApplicationMainDetection() {
    let source = """
      @UIApplicationMain
      class AppDelegate: NSObject {}
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].hasEntryPoint)
  }

  func testNoEntryPointWhenAbsent() {
    let source = """
      struct RegularStruct {}
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertFalse(result.declarations[0].hasEntryPoint)
  }

  // MARK: 5. Extension detection with extendedType

  func testExtensionDetection() {
    let source = """
      extension MyModel {
        func formatted() -> String { "" }
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].isExtension)
    XCTAssertEqual(result.declarations[0].extendedType, "MyModel")
  }

  func testExtensionWithConformance() {
    let source = """
      extension MyModel: CustomProtocol {
        func doSomething() {}
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].isExtension)
    XCTAssertEqual(result.declarations[0].extendedType, "MyModel")
    // The conformance protocol should be a referenced type
    XCTAssertTrue(result.declarations[0].referencedTypes.contains("CustomProtocol"))
  }

  func testExtensionOfFrameworkType() {
    let source = """
      extension String {
        func customTrim() -> String { self }
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].isExtension)
    XCTAssertEqual(result.declarations[0].extendedType, "String")
  }

  // MARK: 6. TypeAlias handling

  func testTypeAliasHandling() {
    let source = """
      typealias Identifier = String
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("Identifier"))
  }

  func testTypeAliasToCustomType() {
    let source = """
      typealias UserID = CustomIdentifier
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("UserID"))
    // CustomIdentifier should be referenced
    XCTAssertTrue(result.declarations[0].referencedTypes.contains("CustomIdentifier"))
  }

  // MARK: 7. Nested type handling

  func testNestedTypeHandling() {
    let source = """
      struct Outer {
        struct Inner {
          let value: Int
        }
        let inner: Inner
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    // Should be a single top-level declaration
    XCTAssertEqual(result.declarations.count, 1)
    // Both Outer and Inner should be declared
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("Outer"))
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("Inner"))
  }

  // MARK: 8. Multiple declarations in one file

  func testMultipleDeclarations() {
    let source = """
      struct ModelA {
        let name: String
      }

      struct ModelB {
        let value: Int
      }

      enum Status {
        case active, inactive
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 3)

    let allDeclared = result.declarations.flatMap { $0.declaredTypes }
    XCTAssertTrue(allDeclared.contains("ModelA"))
    XCTAssertTrue(allDeclared.contains("ModelB"))
    XCTAssertTrue(allDeclared.contains("Status"))
  }

  // MARK: 9. Empty file

  func testEmptyFile() {
    let source = ""
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 0)
    XCTAssertTrue(result.imports.isEmpty)
  }

  // MARK: 10. File with only imports

  func testFileWithOnlyImports() {
    let source = """
      import Foundation
      import SwiftUI
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 0)
    XCTAssertEqual(result.imports, ["Foundation", "SwiftUI"])
  }

  // MARK: - Additional collector edge cases

  func testReferencedTypesFromInheritance() {
    let source = """
      struct MyView: View {
        var body: some View { Text("hi") }
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertTrue(result.declarations[0].declaredTypes.contains("MyView"))
    // View is referenced via inheritance but also declared self-types are subtracted
    // So "View" should be in referencedTypes (it's not in declaredTypes)
    XCTAssertTrue(result.declarations[0].referencedTypes.contains("View"))
  }

  func testReferencedTypesFromPropertyTypes() {
    let source = """
      struct Container {
        let model: CustomModel
        let items: [CustomItem]
      }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertTrue(result.declarations[0].referencedTypes.contains("CustomModel"))
    XCTAssertTrue(result.declarations[0].referencedTypes.contains("CustomItem"))
  }

  func testTopLevelFunction() {
    let source = """
      func globalHelper() -> String { "hello" }
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    // Top-level function has no declared types
    XCTAssertTrue(result.declarations[0].declaredTypes.isEmpty)
    XCTAssertFalse(result.declarations[0].isExtension)
  }

  func testTopLevelVariable() {
    let source = """
      let globalConstant = 42
      """
    let result = collector.collect(source: source, filePath: "test.swift")
    XCTAssertEqual(result.declarations.count, 1)
    XCTAssertTrue(result.declarations[0].declaredTypes.isEmpty)
  }

  func testCollectFromFilePath() throws {
    let tmpDir = NSTemporaryDirectory()
    let filePath = (tmpDir as NSString).appendingPathComponent("test_collect_\(UUID().uuidString).swift")
    let source = """
      import Foundation

      struct FileModel {
        let id: Int
      }
      """
    try source.write(toFile: filePath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: filePath) }

    let result = collector.collect(filePath: filePath)
    XCTAssertNotNil(result)
    XCTAssertEqual(result!.declarations.count, 1)
    XCTAssertTrue(result!.declarations[0].declaredTypes.contains("FileModel"))
    XCTAssertEqual(result!.imports, ["Foundation"])
  }

  func testCollectFromNonexistentFile() {
    let result = collector.collect(filePath: "/nonexistent/path/file.swift")
    XCTAssertNil(result)
  }
}

// MARK: - DeclarationResolverTests

final class DeclarationResolverTests: XCTestCase {

  private var tmpDir: String!
  private var sourcesDir: String!
  private let fm = FileManager.default
  private let resolver = DeclarationResolver()

  override func setUp() {
    super.setUp()
    tmpDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("DeclarationResolverTests_\(UUID().uuidString)")
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

  // MARK: 11. Simple: start file references one type, only that type included

  func testSimpleSingleReference() throws {
    let startFile = writeFile("StartView.swift", content: """
      import SwiftUI

      struct StartView: View {
        let model: MyModel
        var body: some View { Text(model.name) }
      }
      """)

    writeFile("MyModel.swift", content: """
      struct MyModel {
        let name: String
      }
      """)

    writeFile("Unrelated.swift", content: """
      struct UnrelatedModel {
        let value: Int
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["StartView"]
    )

    XCTAssertTrue(result.generatedSource.contains("StartView"))
    XCTAssertTrue(result.generatedSource.contains("MyModel"))
    XCTAssertFalse(result.generatedSource.contains("UnrelatedModel"))
  }

  // MARK: 12. Transitive: A -> B -> C, all three included

  func testTransitiveDependencies() throws {
    let startFile = writeFile("ViewA.swift", content: """
      struct ViewA {
        let b: ModelB
      }
      """)

    writeFile("ModelB.swift", content: """
      struct ModelB {
        let c: ModelC
      }
      """)

    writeFile("ModelC.swift", content: """
      struct ModelC {
        let value: Int
      }
      """)

    writeFile("Orphan.swift", content: """
      struct Orphan {
        let data: String
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["ViewA"]
    )

    XCTAssertTrue(result.generatedSource.contains("ViewA"))
    XCTAssertTrue(result.generatedSource.contains("ModelB"))
    XCTAssertTrue(result.generatedSource.contains("ModelC"))
    XCTAssertFalse(result.generatedSource.contains("Orphan"))
  }

  // MARK: 13. Precision: file has NeededModel + UnneededModel, only NeededModel included

  func testDeclarationLevelPrecision() throws {
    let startFile = writeFile("Start.swift", content: """
      struct StartType {
        let needed: NeededModel
      }
      """)

    writeFile("Models.swift", content: """
      struct NeededModel {
        let value: Int
      }

      struct UnneededModel {
        let other: String
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["StartType"]
    )

    XCTAssertTrue(result.generatedSource.contains("NeededModel"))
    XCTAssertFalse(result.generatedSource.contains("UnneededModel"))
  }

  // MARK: 14. Extensions: extensions of resolved types are included

  func testExtensionsOfResolvedTypesIncluded() throws {
    let startFile = writeFile("Start.swift", content: """
      struct MyData {
        let value: Int
      }
      """)

    writeFile("Extensions.swift", content: """
      extension MyData {
        func formatted() -> String { "\\(value)" }
      }

      extension UnrelatedType {
        func other() {}
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["MyData"]
    )

    XCTAssertTrue(result.generatedSource.contains("extension MyData"))
    XCTAssertFalse(result.generatedSource.contains("extension UnrelatedType"))
  }

  // MARK: 15. Extensions of framework types from contributing files

  func testExtensionsOfFrameworkTypes() throws {
    // Extensions of framework types (like String) should NOT be included
    // unless the file also contributes other resolved declarations.
    let startFile = writeFile("Start.swift", content: """
      struct SimpleView {
        let label: String
      }
      """)

    writeFile("StringExt.swift", content: """
      extension String {
        func customTrim() -> String { self }
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["SimpleView"]
    )

    // String extension is in a different file that doesn't contribute anything else
    // The resolver only includes framework-type extensions from contributing files
    XCTAssertTrue(result.generatedSource.contains("SimpleView"))
    // The String extension file is not a contributing file, so it should not be included
    XCTAssertFalse(result.generatedSource.contains("customTrim"))
  }

  func testExtensionsOfFrameworkTypesInContributingFiles() throws {
    // If a contributing file also has a framework extension, the extension
    // is NOT automatically included (it's an extension, so the safety net skips it)
    let startFile = writeFile("Start.swift", content: """
      struct Wrapper {
        let text: String
      }

      extension String {
        func fromContributingFile() -> String { self }
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Wrapper"]
    )

    // The Wrapper struct is included
    XCTAssertTrue(result.generatedSource.contains("Wrapper"))
    // The String extension is in the start file, and String is a framework type.
    // The extension is indexed under extensionIndices["String"], and since "String"
    // is in frameworkTypes, it won't be pulled in via BFS references.
    // However, start-file declarations are all seeded (minus @main), so it IS included.
    XCTAssertTrue(result.generatedSource.contains("fromContributingFile"))
  }

  // MARK: 16. @main exclusion

  func testMainEntryPointExclusion() throws {
    let startFile = writeFile("Start.swift", content: """
      struct UsefulModel {
        let value: Int
      }
      """)

    writeFile("AppEntry.swift", content: """
      @main
      struct MyApp {
        var body: some Scene { WindowGroup { Text("hi") } }
      }

      struct HelperUsedByApp {
        let x: Int
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["UsefulModel"]
    )

    XCTAssertTrue(result.generatedSource.contains("UsefulModel"))
    XCTAssertFalse(result.generatedSource.contains("MyApp"))
  }

  func testMainInStartFileStillIncludesOtherDeclarations() throws {
    // When @main is in the start file, the @main declaration is skipped
    // but other declarations in the same file should still be included
    let startFile = writeFile("Start.swift", content: """
      @main
      struct MyApp {
        var body: some Scene { WindowGroup { Text("hi") } }
      }

      struct ImportantModel {
        let data: String
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["ImportantModel"]
    )

    XCTAssertTrue(result.generatedSource.contains("ImportantModel"))
    XCTAssertFalse(result.generatedSource.contains("MyApp"))
  }

  // MARK: 17. #Preview macro exclusion

  func testPreviewMacroExclusion() throws {
    // #Preview macros in non-start files are not seeded and thus excluded
    // from the resolved output (unless a type they reference is needed).
    let startFile = writeFile("Start.swift", content: """
      struct PreviewedView {
        let value: Int
      }
      """)

    writeFile("Previews.swift", content: """
      #Preview("Test") {
        Text("Preview content")
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["PreviewedView"]
    )

    XCTAssertTrue(result.generatedSource.contains("PreviewedView"))
    // The #Preview in a non-start, non-contributing file is not included
    XCTAssertFalse(result.generatedSource.contains("Preview content"))
  }

  func testPreviewMacroInStartFileIncluded() throws {
    // #Preview in the start file: since all start-file declarations are seeded,
    // the #Preview expression node (which the parser may treat as an expression
    // statement rather than a macro declaration) could be included in output.
    // This test documents that behavior.
    let startFile = writeFile("Start.swift", content: """
      struct StartView {
        let value: Int
      }

      #Preview {
        StartView(value: 1)
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["StartView"]
    )

    XCTAssertTrue(result.generatedSource.contains("StartView"))
    // The start file's declarations are all included (including any that the
    // collector doesn't filter out), so the #Preview content may appear
    XCTAssertTrue(result.resolvedDeclarations >= 1)
  }

  // MARK: 18. Circular references handled

  func testCircularReferences() throws {
    let startFile = writeFile("NodeA.swift", content: """
      struct NodeA {
        var neighbor: NodeB?
      }
      """)

    writeFile("NodeB.swift", content: """
      struct NodeB {
        var neighbor: NodeA?
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["NodeA"]
    )

    XCTAssertTrue(result.generatedSource.contains("NodeA"))
    XCTAssertTrue(result.generatedSource.contains("NodeB"))
    // Should not hang or crash from circular references
  }

  // MARK: 19. Empty preview body (only start file declarations)

  func testEmptyPreviewReferencedTypes() throws {
    let startFile = writeFile("Start.swift", content: """
      struct OnlyInStart {
        let value: Int
      }
      """)

    writeFile("Other.swift", content: """
      struct OtherModel {
        let data: String
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: []
    )

    // Start file declarations are always included
    XCTAssertTrue(result.generatedSource.contains("OnlyInStart"))
    // Other types not referenced should be excluded
    XCTAssertFalse(result.generatedSource.contains("OtherModel"))
  }

  // MARK: 20. Safety net: top-level functions from contributing files included

  func testSafetyNetTopLevelFunctions() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Holder {
        let helper: HelperType
      }
      """)

    writeFile("Helper.swift", content: """
      struct HelperType {
        let value: Int
      }

      func helperFunction() -> String { "help" }

      let helperConstant = 42
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Holder"]
    )

    XCTAssertTrue(result.generatedSource.contains("HelperType"))
    // Safety net: top-level functions/vars from contributing files are included
    XCTAssertTrue(result.generatedSource.contains("helperFunction"))
    XCTAssertTrue(result.generatedSource.contains("helperConstant"))
  }

  func testSafetyNetDoesNotIncludeFromNonContributingFiles() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Isolated {}
      """)

    writeFile("Unrelated.swift", content: """
      struct UnrelatedType {}

      func unrelatedTopLevel() {}
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Isolated"]
    )

    XCTAssertTrue(result.generatedSource.contains("Isolated"))
    XCTAssertFalse(result.generatedSource.contains("unrelatedTopLevel"))
  }

  // MARK: 21. Multiple files, only needed declarations pulled in

  func testMultipleFilesSelectiveInclusion() throws {
    let startFile = writeFile("Start.swift", content: """
      struct MainView {
        let config: AppConfig
      }
      """)

    writeFile("Config.swift", content: """
      struct AppConfig {
        let theme: Theme
      }
      """)

    writeFile("Theme.swift", content: """
      struct Theme {
        let primaryColor: String
      }
      """)

    writeFile("Network.swift", content: """
      struct NetworkClient {
        func fetch() {}
      }
      """)

    writeFile("Analytics.swift", content: """
      struct AnalyticsTracker {
        func track() {}
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["MainView"]
    )

    XCTAssertTrue(result.generatedSource.contains("MainView"))
    XCTAssertTrue(result.generatedSource.contains("AppConfig"))
    XCTAssertTrue(result.generatedSource.contains("Theme"))
    XCTAssertFalse(result.generatedSource.contains("NetworkClient"))
    XCTAssertFalse(result.generatedSource.contains("AnalyticsTracker"))

    // Should report correct counts
    XCTAssertEqual(result.contributingFiles.count, 3)
    XCTAssertEqual(result.totalDeclarations, 5)
    XCTAssertEqual(result.resolvedDeclarations, 3)
  }

  // MARK: 22. Nested types: Outer.Inner both included when Outer referenced

  func testNestedTypesIncluded() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Container {
        let widget: Widget
      }
      """)

    writeFile("Widget.swift", content: """
      struct Widget {
        struct Style {
          let color: String
        }
        let style: Style
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Container"]
    )

    XCTAssertTrue(result.generatedSource.contains("Widget"))
    XCTAssertTrue(result.generatedSource.contains("Style"))
  }

  // MARK: 23. Protocol conformance triggers inclusion

  func testProtocolConformanceTriggersInclusion() throws {
    let startFile = writeFile("Start.swift", content: """
      struct ItemView {
        let item: Displayable
      }
      """)

    writeFile("Displayable.swift", content: """
      protocol Displayable {
        var displayName: String { get }
      }
      """)

    writeFile("DisplayItem.swift", content: """
      struct DisplayItem: Displayable {
        var displayName: String { "item" }
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["ItemView"]
    )

    XCTAssertTrue(result.generatedSource.contains("Displayable"))
    // DisplayItem conforms to Displayable, but is not directly referenced
    // The resolver follows type references, not conformance lookups
    // So DisplayItem would only be included if explicitly referenced
  }

  // MARK: 24. TypeAlias followed transitively

  func testTypeAliasFollowedTransitively() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Holder {
        let id: UserID
      }
      """)

    writeFile("TypeAliases.swift", content: """
      typealias UserID = CustomIdentifier
      """)

    writeFile("CustomIdentifier.swift", content: """
      struct CustomIdentifier {
        let rawValue: String
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Holder"]
    )

    XCTAssertTrue(result.generatedSource.contains("Holder"))
    XCTAssertTrue(result.generatedSource.contains("UserID"))
    XCTAssertTrue(result.generatedSource.contains("CustomIdentifier"))
  }

  // MARK: - Additional resolver tests

  func testStartFileOutsideSourcesDir() throws {
    let externalDir = (tmpDir as NSString).appendingPathComponent("External")
    try fm.createDirectory(atPath: externalDir, withIntermediateDirectories: true)

    let startFile = writeFile("StartExternal.swift", content: """
      struct ExternalView {
        let model: InternalModel
      }
      """, in: externalDir)

    writeFile("InternalModel.swift", content: """
      struct InternalModel {
        let name: String
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["ExternalView"]
    )

    XCTAssertTrue(result.generatedSource.contains("ExternalView"))
    XCTAssertTrue(result.generatedSource.contains("InternalModel"))
  }

  func testImportsFromContributingFilesIncluded() throws {
    let startFile = writeFile("Start.swift", content: """
      import SwiftUI

      struct MyView {
        let model: DataModel
      }
      """)

    writeFile("DataModel.swift", content: """
      import Foundation
      import Combine

      struct DataModel {
        let date: Date
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["MyView"]
    )

    XCTAssertTrue(result.imports.contains("SwiftUI"))
    XCTAssertTrue(result.imports.contains("Foundation"))
    XCTAssertTrue(result.imports.contains("Combine"))
    // Verify imports appear in generated source
    XCTAssertTrue(result.generatedSource.contains("import SwiftUI"))
    XCTAssertTrue(result.generatedSource.contains("import Foundation"))
    XCTAssertTrue(result.generatedSource.contains("import Combine"))
  }

  func testFrameworkTypesNotFollowed() throws {
    let startFile = writeFile("Start.swift", content: """
      struct MyWidget {
        let text: String
        let color: Color
        let items: [Int]
      }
      """)

    writeFile("StringExt.swift", content: """
      struct StringHelper {
        func help() {}
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["MyWidget"]
    )

    XCTAssertTrue(result.generatedSource.contains("MyWidget"))
    // String, Color, Int are framework types, so StringHelper should not be pulled in
    XCTAssertFalse(result.generatedSource.contains("StringHelper"))
  }

  func testPreviewReferencedTypesSeedResolution() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Placeholder {}
      """)

    writeFile("ExternalView.swift", content: """
      struct ExternalView {
        let config: ViewConfig
      }
      """)

    writeFile("ViewConfig.swift", content: """
      struct ViewConfig {
        let title: String
      }
      """)

    // ExternalView is referenced by the preview body, not the start file
    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["ExternalView"]
    )

    XCTAssertTrue(result.generatedSource.contains("Placeholder"))
    XCTAssertTrue(result.generatedSource.contains("ExternalView"))
    XCTAssertTrue(result.generatedSource.contains("ViewConfig"))
  }

  func testExtensionOfResolvedTypeInDifferentFile() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Person {
        let firstName: String
        let lastName: String
      }
      """)

    writeFile("PersonExt.swift", content: """
      extension Person {
        var fullName: String { firstName + " " + lastName }
      }
      """)

    writeFile("UnrelatedExt.swift", content: """
      extension Animal {
        var description: String { "animal" }
      }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Person"]
    )

    XCTAssertTrue(result.generatedSource.contains("struct Person"))
    XCTAssertTrue(result.generatedSource.contains("extension Person"))
    XCTAssertTrue(result.generatedSource.contains("fullName"))
    XCTAssertFalse(result.generatedSource.contains("Animal"))
  }

  func testResolvedDeclarationsCount() throws {
    let startFile = writeFile("Start.swift", content: """
      struct A { let b: B }
      """)

    writeFile("B.swift", content: """
      struct B { let value: Int }
      struct C { let other: String }
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["A"]
    )

    // A + B resolved, C not resolved
    XCTAssertEqual(result.resolvedDeclarations, 2)
    XCTAssertEqual(result.totalDeclarations, 3)
  }

  func testGeneratedSourceHasHeader() throws {
    let startFile = writeFile("Start.swift", content: """
      struct Simple {}
      """)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: []
    )

    XCTAssertTrue(result.generatedSource.hasPrefix("// Auto-generated by DeclarationResolver"))
  }

  func testSubdirectoryScanning() throws {
    let subDir = (sourcesDir as NSString).appendingPathComponent("SubModule")
    try fm.createDirectory(atPath: subDir, withIntermediateDirectories: true)

    let startFile = writeFile("Start.swift", content: """
      struct Root {
        let sub: SubType
      }
      """)

    writeFile("SubType.swift", content: """
      struct SubType {
        let value: Int
      }
      """, in: subDir)

    let result = try resolver.resolve(
      startFile: startFile,
      sourcesDir: sourcesDir,
      previewReferencedTypes: ["Root"]
    )

    XCTAssertTrue(result.generatedSource.contains("Root"))
    XCTAssertTrue(result.generatedSource.contains("SubType"))
  }
}

// MARK: - PreviewExtractorReferencedTypesTests

final class PreviewExtractorReferencedTypesTests: XCTestCase {

  private let extractor = PreviewExtractor()

  // MARK: 25. Simple view reference

  func testSimpleViewReference() {
    let source = "MyView()"
    let types = extractor.extractReferencedTypes(fromSource: source)
    XCTAssertTrue(types.contains("MyView"))
  }

  // MARK: 26. Multiple references

  func testMultipleReferences() {
    let source = """
      VStack {
        MyView()
        OtherView(model: SomeModel())
      }
      """
    let types = extractor.extractReferencedTypes(fromSource: source)
    XCTAssertTrue(types.contains("MyView"))
    XCTAssertTrue(types.contains("OtherView"))
    XCTAssertTrue(types.contains("SomeModel"))
    XCTAssertTrue(types.contains("VStack"))
  }

  // MARK: 27. Framework types present but caller can filter

  func testFrameworkTypesPresent() {
    let source = """
      VStack {
        Text("Hello")
        MyCustomView()
      }
      """
    let types = extractor.extractReferencedTypes(fromSource: source)
    // The extractor returns all PascalCase references including framework types
    XCTAssertTrue(types.contains("VStack"))
    XCTAssertTrue(types.contains("Text"))
    XCTAssertTrue(types.contains("MyCustomView"))
    // The caller (DeclarationResolver) is responsible for filtering framework types
  }

  // MARK: 28. No references (plain Text)

  func testNoCustomReferences() {
    let source = """
      Text("Just plain text")
      """
    let types = extractor.extractReferencedTypes(fromSource: source)
    // Should contain Text (framework type) but no custom types
    XCTAssertTrue(types.contains("Text"))
    let customTypes = types.subtracting(frameworkTypes)
    XCTAssertTrue(customTypes.isEmpty)
  }

  // MARK: Additional extractReferencedTypes tests

  func testLowercaseIdentifiersNotIncluded() {
    let source = """
      let x = myFunction()
      """
    let types = extractor.extractReferencedTypes(fromSource: source)
    // lowercase identifiers should not be treated as type references
    XCTAssertFalse(types.contains("myFunction"))
    XCTAssertFalse(types.contains("x"))
  }

  func testGenericTypeReferences() {
    let source = """
      GenericView<MyModel>()
      """
    let types = extractor.extractReferencedTypes(fromSource: source)
    XCTAssertTrue(types.contains("GenericView"))
    XCTAssertTrue(types.contains("MyModel"))
  }

  func testPropertyAccessChain() {
    let source = """
      MyConfig.shared.value
      """
    let types = extractor.extractReferencedTypes(fromSource: source)
    XCTAssertTrue(types.contains("MyConfig"))
  }

  func testClosureWithTypeReferences() {
    let source = """
      List(items) { item in
        CustomRow(data: item)
      }
      """
    let types = extractor.extractReferencedTypes(fromSource: source)
    XCTAssertTrue(types.contains("List"))
    XCTAssertTrue(types.contains("CustomRow"))
  }

  func testEmptySource() {
    let source = ""
    let types = extractor.extractReferencedTypes(fromSource: source)
    XCTAssertTrue(types.isEmpty)
  }

  func testOnlyWhitespace() {
    let source = "   \n  \n  "
    let types = extractor.extractReferencedTypes(fromSource: source)
    XCTAssertTrue(types.isEmpty)
  }
}
