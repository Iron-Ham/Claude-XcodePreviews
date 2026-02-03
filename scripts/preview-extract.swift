#!/usr/bin/env swift
//
// preview-extract.swift - Extract #Preview content from Swift files
//
// This tool parses Swift files to extract #Preview macro declarations
// and generates a minimal host app that renders just that preview.
//
// Usage: swift preview-extract.swift <input.swift> [preview-name]

import Foundation

struct PreviewInfo {
    let name: String
    let body: String
    let startLine: Int
    let endLine: Int
}

func extractPreviews(from content: String) -> [PreviewInfo] {
    var previews: [PreviewInfo] = []
    let lines = content.components(separatedBy: .newlines)

    var i = 0
    while i < lines.count {
        let line = lines[i]

        // Look for #Preview declarations
        if line.contains("#Preview") {
            var previewName = "Preview"
            var bodyLines: [String] = []
            var braceCount = 0
            var started = false
            let startLine = i + 1

            // Extract preview name if present: #Preview("Name") or #Preview(name:)
            if let nameMatch = line.range(of: #"#Preview\s*\(\s*"([^"]+)""#, options: .regularExpression) {
                let match = String(line[nameMatch])
                if let quoteStart = match.firstIndex(of: "\""),
                   let quoteEnd = match.lastIndex(of: "\""), quoteStart < quoteEnd {
                    let nameStart = match.index(after: quoteStart)
                    previewName = String(match[nameStart..<quoteEnd])
                }
            }

            // Find the opening brace and extract body
            var j = i
            while j < lines.count {
                let currentLine = lines[j]

                for char in currentLine {
                    if char == "{" {
                        if !started {
                            started = true
                        }
                        braceCount += 1
                    } else if char == "}" {
                        braceCount -= 1
                    }
                }

                if started {
                    bodyLines.append(currentLine)
                }

                if started && braceCount == 0 {
                    // Found the end of the preview
                    let body = bodyLines.joined(separator: "\n")
                    previews.append(PreviewInfo(
                        name: previewName,
                        body: body,
                        startLine: startLine,
                        endLine: j + 1
                    ))
                    i = j
                    break
                }

                j += 1
            }
        }

        i += 1
    }

    return previews
}

func extractImports(from content: String) -> [String] {
    var imports: [String] = []
    let lines = content.components(separatedBy: .newlines)

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("import ") {
            imports.append(trimmed)
        }
    }

    // Always ensure SwiftUI is imported
    if !imports.contains("import SwiftUI") {
        imports.insert("import SwiftUI", at: 0)
    }

    return imports
}

func generatePreviewHost(
    originalFile: String,
    content: String,
    preview: PreviewInfo,
    imports: [String]
) -> String {
    // Extract the preview body (removing outer braces)
    var body = preview.body
    if body.hasPrefix("{") {
        body = String(body.dropFirst())
    }
    if body.hasSuffix("}") {
        body = String(body.dropLast())
    }
    body = body.trimmingCharacters(in: .whitespacesAndNewlines)

    // Check if the body returns a view or is a view builder
    let needsReturn = !body.contains("return ") && !body.hasPrefix("let ") && !body.hasPrefix("var ")

    return """
    // Auto-generated Preview Host
    // Source: \(originalFile)
    // Preview: \(preview.name)

    \(imports.joined(separator: "\n"))

    // Include the original file content (types/views defined there)
    \(content)

    // Preview Host App
    @main
    struct PreviewHostApp: App {
        var body: some Scene {
            WindowGroup {
                PreviewContainer()
            }
        }
    }

    struct PreviewContainer: View {
        var body: some View {
            \(needsReturn ? body : "previewContent")
        }

        \(needsReturn ? "" : """
        @ViewBuilder
        var previewContent: some View {
            \(body)
        }
        """)
    }
    """
}

// Main execution
let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage: preview-extract.swift <input.swift> [preview-name]")
    print("")
    print("Options:")
    print("  --list    List all previews in the file")
    print("  --output  Specify output file path")
    exit(1)
}

let inputPath = args[1]
let previewName = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : nil
let listOnly = args.contains("--list")

guard FileManager.default.fileExists(atPath: inputPath) else {
    print("Error: File not found: \(inputPath)")
    exit(1)
}

guard let content = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
    print("Error: Could not read file: \(inputPath)")
    exit(1)
}

let previews = extractPreviews(from: content)

if previews.isEmpty {
    print("No #Preview declarations found in \(inputPath)")
    exit(1)
}

if listOnly {
    print("Previews found in \(inputPath):")
    for (index, preview) in previews.enumerated() {
        print("  \(index + 1). \"\(preview.name)\" (lines \(preview.startLine)-\(preview.endLine))")
    }
    exit(0)
}

// Select the preview to render
let selectedPreview: PreviewInfo
if let name = previewName {
    guard let preview = previews.first(where: { $0.name == name }) else {
        print("Error: Preview '\(name)' not found")
        print("Available previews:")
        for preview in previews {
            print("  - \"\(preview.name)\"")
        }
        exit(1)
    }
    selectedPreview = preview
} else {
    selectedPreview = previews[0]
    if previews.count > 1 {
        print("Multiple previews found, using first: \"\(selectedPreview.name)\"")
        print("Specify a preview name to use a different one.")
    }
}

let imports = extractImports(from: content)
let hostCode = generatePreviewHost(
    originalFile: inputPath,
    content: content,
    preview: selectedPreview,
    imports: imports
)

print(hostCode)
