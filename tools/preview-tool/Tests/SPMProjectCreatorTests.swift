import Foundation
import XCTest
import XcodeProj
import PathKit

@testable import PreviewToolLib

// MARK: - SPMProjectCreatorTests

final class SPMProjectCreatorTests: XCTestCase {

  private var tmpDir: String!
  private var previewHostDir: String!
  private var packageDir: String!
  private let fm = FileManager.default
  private let creator = SPMProjectCreator()

  // MARK: Setup / Teardown

  override func setUp() {
    super.setUp()

    tmpDir = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("SPMProjectCreatorTests_\(UUID().uuidString)")
    try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

    previewHostDir = (tmpDir as NSString).appendingPathComponent("PreviewHost")
    packageDir = (tmpDir as NSString).appendingPathComponent("TestPackage")
    try! fm.createDirectory(atPath: packageDir, withIntermediateDirectories: true)

    // Create a minimal Package.swift
    let packageSwift = """
      // swift-tools-version: 5.9
      import PackageDescription
      let package = Package(
          name: "TestPackage",
          platforms: [.iOS(.v17)],
          products: [
              .library(name: "TestModule", targets: ["TestModule"]),
          ],
          targets: [
              .target(name: "TestModule"),
          ]
      )
      """
    let packagePath = (packageDir as NSString).appendingPathComponent("Package.swift")
    try! packageSwift.write(toFile: packagePath, atomically: true, encoding: .utf8)
  }

  override func tearDown() {
    try? fm.removeItem(atPath: tmpDir)
    super.tearDown()
  }

  // MARK: Helpers

  private func openProject(at path: String) throws -> XcodeProj {
    try XcodeProj(path: Path(path))
  }

  // MARK: Tests

  func testBasicProjectCreation() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI"]
    )

    XCTAssertTrue(fm.fileExists(atPath: result.projectPath), "Project should be created on disk")

    let proj = try openProject(at: result.projectPath)
    let targets = proj.pbxproj.nativeTargets.filter { $0.name == "PreviewHost" }
    XCTAssertEqual(targets.count, 1, "Should have exactly one PreviewHost target")
  }

  func testTargetHasCorrectProductType() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI"]
    )

    let proj = try openProject(at: result.projectPath)
    let target = proj.pbxproj.nativeTargets.first { $0.name == "PreviewHost" }
    XCTAssertNotNil(target)
    XCTAssertEqual(target?.productType, .application)
  }

  func testBuildSettings() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "16.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI"]
    )

    let proj = try openProject(at: result.projectPath)
    let target = proj.pbxproj.nativeTargets.first { $0.name == "PreviewHost" }
    let configs = target?.buildConfigurationList?.buildConfigurations ?? []
    XCTAssertFalse(configs.isEmpty)

    for config in configs {
      let settings = config.buildSettings
      XCTAssertEqual(settings["PRODUCT_NAME"]?.stringValue, "PreviewHost")
      XCTAssertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"]?.stringValue, "com.preview.spm.host")
      XCTAssertEqual(settings["SWIFT_VERSION"]?.stringValue, "5.0")
      XCTAssertEqual(settings["SDKROOT"]?.stringValue, "iphoneos")
      XCTAssertEqual(settings["IPHONEOS_DEPLOYMENT_TARGET"]?.stringValue, "16.0")
    }
  }

  func testBuildPhasesPresent() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI"]
    )

    let proj = try openProject(at: result.projectPath)
    let target = proj.pbxproj.nativeTargets.first { $0.name == "PreviewHost" }
    let phases = target?.buildPhases ?? []

    XCTAssertTrue(phases.contains { $0 is PBXSourcesBuildPhase })
    XCTAssertTrue(phases.contains { $0 is PBXFrameworksBuildPhase })
    XCTAssertTrue(phases.contains { $0 is PBXResourcesBuildPhase })
  }

  func testHostAppGenerated() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello from SPM\")",
      imports: ["SwiftUI"]
    )

    let hostAppPath = (previewHostDir as NSString).appendingPathComponent("PreviewHostApp.swift")
    XCTAssertTrue(fm.fileExists(atPath: hostAppPath))

    let content = try String(contentsOfFile: hostAppPath, encoding: .utf8)
    XCTAssertTrue(content.contains("import SwiftUI"))
    XCTAssertTrue(content.contains("import TestModule"))
    XCTAssertTrue(content.contains("@main"))
    XCTAssertTrue(content.contains("PreviewHostApp"))
    XCTAssertTrue(content.contains("PreviewContent"))
    XCTAssertTrue(content.contains("Hello from SPM"))

    // Verify project was actually created
    XCTAssertTrue(fm.fileExists(atPath: result.projectPath))
  }

  func testModuleImportNotDuplicated() throws {
    // When "TestModule" is already in imports, it shouldn't appear twice
    _ = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI", "TestModule"]
    )

    let hostAppPath = (previewHostDir as NSString).appendingPathComponent("PreviewHostApp.swift")
    let content = try String(contentsOfFile: hostAppPath, encoding: .utf8)

    let moduleImportCount = content.components(separatedBy: "import TestModule").count - 1
    XCTAssertEqual(moduleImportCount, 1, "Module import should appear exactly once")
  }

  func testSchemeCreated() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI"]
    )

    let schemePath = (result.projectPath as NSString).appendingPathComponent(
      "xcshareddata/xcschemes/PreviewHost.xcscheme"
    )
    XCTAssertTrue(fm.fileExists(atPath: schemePath), "PreviewHost scheme should be created")
  }

  func testLocalPackageReferenceAdded() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI"]
    )

    let proj = try openProject(at: result.projectPath)
    let project = proj.pbxproj.projects.first
    XCTAssertNotNil(project)

    let localPackages = project?.localPackages ?? []
    XCTAssertEqual(localPackages.count, 1, "Should have one local package reference")
    XCTAssertEqual(localPackages.first?.relativePath, packageDir)
  }

  func testPackageProductDependencyAdded() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI"]
    )

    let proj = try openProject(at: result.projectPath)
    let target = proj.pbxproj.nativeTargets.first { $0.name == "PreviewHost" }
    let pkgDeps = target?.packageProductDependencies ?? []

    XCTAssertEqual(pkgDeps.count, 1, "Should have one package product dependency")
    XCTAssertEqual(pkgDeps.first?.productName, "TestModule")
  }

  func testSourceFilesAddedToTarget() throws {
    let result = try creator.createProject(
      tempDir: tmpDir,
      previewHostDir: previewHostDir,
      packageDir: packageDir,
      moduleName: "TestModule",
      deploymentTarget: "17.0",
      previewBody: "Text(\"Hello\")",
      imports: ["SwiftUI"]
    )

    let proj = try openProject(at: result.projectPath)
    let target = proj.pbxproj.nativeTargets.first { $0.name == "PreviewHost" }
    let sourcesPhase = try target?.sourcesBuildPhase()
    let sourceFiles = sourcesPhase?.files ?? []
    let fileNames = sourceFiles.compactMap { $0.file?.name }

    XCTAssertTrue(fileNames.contains("PreviewHostApp.swift"))
  }

  // MARK: - Deployment Target Parsing

  func testParseDeploymentTargetV17() {
    let packagePath = writePackageSwift("""
      // swift-tools-version: 5.9
      import PackageDescription
      let package = Package(
          name: "Test",
          platforms: [.iOS(.v17)]
      )
      """)

    XCTAssertEqual(SPMProjectCreator.parseDeploymentTarget(packagePath: packagePath), "17.0")
  }

  func testParseDeploymentTargetV16_4() {
    let packagePath = writePackageSwift("""
      // swift-tools-version: 5.9
      import PackageDescription
      let package = Package(
          name: "Test",
          platforms: [.iOS(.v16_4)]
      )
      """)

    XCTAssertEqual(SPMProjectCreator.parseDeploymentTarget(packagePath: packagePath), "16.4")
  }

  func testParseDeploymentTargetStringFormat() {
    let packagePath = writePackageSwift("""
      // swift-tools-version: 6.0
      import PackageDescription
      let package = Package(
          name: "Test",
          platforms: [.iOS("18.0")]
      )
      """)

    XCTAssertEqual(SPMProjectCreator.parseDeploymentTarget(packagePath: packagePath), "18.0")
  }

  func testParseDeploymentTargetMissing() {
    let packagePath = writePackageSwift("""
      // swift-tools-version: 5.9
      import PackageDescription
      let package = Package(name: "Test")
      """)

    XCTAssertEqual(
      SPMProjectCreator.parseDeploymentTarget(packagePath: packagePath), "17.0",
      "Should default to 17.0 when no iOS platform specified"
    )
  }

  func testParseDeploymentTargetFileNotFound() {
    XCTAssertEqual(
      SPMProjectCreator.parseDeploymentTarget(packagePath: "/nonexistent/Package.swift"), "17.0",
      "Should default to 17.0 when file not found"
    )
  }

  // MARK: Private Helpers

  private func writePackageSwift(_ content: String) -> String {
    let dir = (tmpDir as NSString).appendingPathComponent(UUID().uuidString)
    try! fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = (dir as NSString).appendingPathComponent("Package.swift")
    try! content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }
}
