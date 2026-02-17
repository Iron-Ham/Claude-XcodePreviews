import Foundation
import PathKit
import XcodeProj

// MARK: - SPMProjectError

public enum SPMProjectError: Error, CustomStringConvertible {
  case projectCreationFailed(String)
  case sourceFileError(String)

  public var description: String {
    switch self {
    case .projectCreationFailed(let msg):
      "Failed to create SPM preview project: \(msg)"
    case .sourceFileError(let msg):
      "Source file error: \(msg)"
    }
  }
}

// MARK: - SPMProjectCreator

public struct SPMProjectCreator {

  // MARK: Public

  public struct ProjectPaths {
    public let projectPath: String
  }

  public init() {}

  /// Create a temporary Xcode project that depends on a local SPM package.
  public func createProject(
    tempDir: String,
    previewHostDir: String,
    packageDir: String,
    moduleName: String,
    deploymentTarget: String,
    previewBody: String,
    imports: [String]
  ) throws -> ProjectPaths {
    let fm = FileManager.default

    // Ensure directories exist
    try fm.createDirectory(atPath: previewHostDir, withIntermediateDirectories: true)

    // Generate the host app source
    let hostAppPath = try generateHostApp(
      in: previewHostDir,
      previewBody: previewBody,
      imports: imports,
      moduleName: moduleName
    )
    logVerbose("Generated host app: \(hostAppPath)")

    // Create the Xcode project
    let projectPath = (tempDir as NSString).appendingPathComponent("PreviewHost.xcodeproj")

    let mainGroup = PBXGroup(children: [], sourceTree: .group)
    let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
    mainGroup.children.append(productsGroup)

    // Project-level build configurations
    let projectDebugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
    let projectReleaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
    let projectConfigList = XCConfigurationList(
      buildConfigurations: [projectDebugConfig, projectReleaseConfig],
      defaultConfigurationName: "Debug"
    )

    let project = PBXProject(
      name: "PreviewHost",
      buildConfigurationList: projectConfigList,
      compatibilityVersion: "Xcode 14.0",
      preferredProjectObjectVersion: nil,
      minimizedProjectReferenceProxies: nil,
      mainGroup: mainGroup
    )

    let pbxproj = PBXProj(
      rootObject: project,
      objects: [
        mainGroup, productsGroup,
        projectDebugConfig, projectReleaseConfig, projectConfigList,
        project,
      ]
    )

    // Create target
    let target = createTarget(in: pbxproj, deploymentTarget: deploymentTarget)

    // Add to project's targets
    project.targets.append(target)

    // Add product reference to Products group
    if let productRef = target.product {
      productsGroup.children.append(productRef)
    }

    // Add PreviewHost source group and files
    let previewGroup = PBXGroup(
      children: [],
      sourceTree: .absolute,
      name: "PreviewHost",
      path: previewHostDir
    )
    pbxproj.add(object: previewGroup)
    mainGroup.children.append(previewGroup)

    try addPreviewHostSources(
      to: target,
      group: previewGroup,
      previewHostDir: previewHostDir,
      pbxproj: pbxproj
    )

    // Add local SPM package reference
    let localPkgRef = XCLocalSwiftPackageReference(relativePath: packageDir)
    pbxproj.add(object: localPkgRef)
    project.localPackages.append(localPkgRef)

    // Add package product dependency for the module.
    // For local packages, the package property (XCRemoteSwiftPackageReference) is not set —
    // xcodebuild resolves the product by name from the project's localPackages list.
    let pkgProduct = XCSwiftPackageProductDependency(productName: moduleName)
    pbxproj.add(object: pkgProduct)

    if target.packageProductDependencies == nil {
      target.packageProductDependencies = []
    }
    target.packageProductDependencies?.append(pkgProduct)

    // Write project to disk
    let projPath = Path(projectPath)
    let xcodeproj = XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
    do {
      try xcodeproj.write(path: projPath)
    } catch {
      throw SPMProjectError.projectCreationFailed(error.localizedDescription)
    }
    log(.info, "Created Xcode project: \(projectPath)")

    // Create scheme
    let projectFileName = projPath.lastComponent
    let buildableRef = XCScheme.BuildableReference(
      referencedContainer: "container:\(projectFileName)",
      blueprint: target,
      buildableName: "PreviewHost.app",
      blueprintName: "PreviewHost"
    )

    let scheme = XCScheme(
      name: "PreviewHost",
      lastUpgradeVersion: nil,
      version: nil,
      buildAction: XCScheme.BuildAction(
        buildActionEntries: [
          XCScheme.BuildAction.Entry(
            buildableReference: buildableRef,
            buildFor: XCScheme.BuildAction.Entry.BuildFor.default
          ),
        ]
      ),
      testAction: nil,
      launchAction: XCScheme.LaunchAction(
        runnable: XCScheme.Runnable(
          buildableReference: buildableRef
        ),
        buildConfiguration: "Debug"
      ),
      profileAction: nil,
      analyzeAction: nil,
      archiveAction: nil
    )

    let schemesDir = projPath + "xcshareddata/xcschemes"
    do {
      try schemesDir.mkpath()
    } catch {
      log(.warning, "Failed to create schemes directory: \(error)")
    }
    try scheme.write(path: schemesDir + "PreviewHost.xcscheme", override: true)
    log(.info, "Created scheme: PreviewHost")

    return ProjectPaths(projectPath: projectPath)
  }

  /// Extract iOS deployment target from Package.swift.
  /// Parses patterns like `.iOS(.v17)` → `"17.0"` or `.iOS("17.0")` → `"17.0"`.
  public static func parseDeploymentTarget(packagePath: String) -> String {
    guard let content = try? String(contentsOfFile: packagePath, encoding: .utf8) else {
      log(.warning, "Cannot read Package.swift at \(packagePath), defaulting to iOS 17.0")
      return "17.0"
    }

    // Match .iOS(.v17) or .iOS(.v17_0) style
    if let range = content.range(
      of: #"\.iOS\(\.v(\d+)(?:_(\d+))?\)"#,
      options: .regularExpression
    ) {
      let match = String(content[range])
      let digits = match.components(separatedBy: CharacterSet.decimalDigits.inverted)
        .filter { !$0.isEmpty }
      if let major = digits.first {
        let minor = digits.count > 1 ? digits[1] : "0"
        return "\(major).\(minor)"
      }
    }

    // Match .iOS("17.0") style
    if let range = content.range(
      of: #"\.iOS\("(\d+\.\d+)"\)"#,
      options: .regularExpression
    ) {
      let match = String(content[range])
      let digits = match.components(separatedBy: CharacterSet(charactersIn: "\""))
      if let version = digits.first(where: { $0.contains(".") && $0.first?.isNumber == true }) {
        return version
      }
    }

    log(.warning, "Could not parse iOS deployment target from Package.swift, defaulting to 17.0")
    return "17.0"
  }

  // MARK: Private

  private func generateHostApp(
    in previewHostDir: String,
    previewBody: String,
    imports: [String],
    moduleName: String
  ) throws -> String {
    var importStatements = ""
    for imp in imports {
      importStatements += "import \(imp)\n"
    }
    // Add module import if not already in the list
    if !imports.contains(moduleName) {
      importStatements += "import \(moduleName)\n"
    }

    let indentedBody = previewBody
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { "        \($0)" }
      .joined(separator: "\n")

    let content = """
      // Auto-generated PreviewHost

      import SwiftUI
      \(importStatements)
      @main
      struct PreviewHostApp: App {
          var body: some Scene {
              WindowGroup {
                  PreviewContent()
              }
          }
      }

      struct PreviewContent: View {
          var body: some View {
      \(indentedBody)
          }
      }
      """

    let path = (previewHostDir as NSString).appendingPathComponent("PreviewHostApp.swift")
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }

  private func createTarget(
    in pbxproj: PBXProj,
    deploymentTarget: String
  ) -> PBXNativeTarget {
    let buildSettings: BuildSettings = [
      "PRODUCT_NAME": "PreviewHost",
      "PRODUCT_BUNDLE_IDENTIFIER": "com.preview.spm.host",
      "GENERATE_INFOPLIST_FILE": "YES",
      "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
      "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
      "SWIFT_VERSION": "5.0",
      "CODE_SIGN_STYLE": "Automatic",
      "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
      "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
      "SDKROOT": "iphoneos",
    ]

    let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: buildSettings)
    let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: buildSettings)
    pbxproj.add(object: debugConfig)
    pbxproj.add(object: releaseConfig)

    let configList = XCConfigurationList(
      buildConfigurations: [debugConfig, releaseConfig],
      defaultConfigurationName: "Debug"
    )
    pbxproj.add(object: configList)

    let sourcesPhase = PBXSourcesBuildPhase()
    pbxproj.add(object: sourcesPhase)

    let frameworksPhase = PBXFrameworksBuildPhase()
    pbxproj.add(object: frameworksPhase)

    let resourcesPhase = PBXResourcesBuildPhase()
    pbxproj.add(object: resourcesPhase)

    let productRef = PBXFileReference(
      sourceTree: .buildProductsDir,
      explicitFileType: "wrapper.application",
      path: "PreviewHost.app",
      includeInIndex: false
    )
    pbxproj.add(object: productRef)

    let target = PBXNativeTarget(
      name: "PreviewHost",
      buildConfigurationList: configList,
      buildPhases: [sourcesPhase, frameworksPhase, resourcesPhase],
      product: productRef,
      productType: .application
    )
    pbxproj.add(object: target)

    return target
  }

  private func addPreviewHostSources(
    to target: PBXNativeTarget,
    group: PBXGroup?,
    previewHostDir: String,
    pbxproj: PBXProj
  ) throws {
    let fm = FileManager.default
    let files: [String]
    do {
      files = try fm.contentsOfDirectory(atPath: previewHostDir)
    } catch {
      throw SPMProjectError.sourceFileError("Cannot list directory: \(error)")
    }

    for fileName in files where fileName.hasSuffix(".swift") {
      let filePath = (previewHostDir as NSString).appendingPathComponent(fileName)
      let fileRef = PBXFileReference(
        sourceTree: .absolute,
        name: fileName,
        lastKnownFileType: "sourcecode.swift",
        path: filePath
      )
      pbxproj.add(object: fileRef)
      group?.children.append(fileRef)

      let buildFile = PBXBuildFile(file: fileRef)
      pbxproj.add(object: buildFile)
      try target.sourcesBuildPhase()?.files?.append(buildFile)

      logVerbose("  Added source: \(fileName)")
    }
  }
}
