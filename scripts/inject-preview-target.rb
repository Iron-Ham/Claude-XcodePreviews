#!/usr/bin/env ruby
#
# inject-preview-target.rb - Dynamically create a preview target in an Xcode project
#
# This script adds a lightweight "PreviewHost" target to an existing Xcode project,
# configured to depend only on the modules needed for the preview.
#
# Usage:
#   ruby inject-preview-target.rb <project.xcodeproj> <module-name> [options]
#
# Options:
#   --source <file>       Swift file containing the preview
#   --preview-name <name> Name for the preview target (default: PreviewHost)
#   --clean               Remove existing preview target first
#   --dry-run             Show what would be done without modifying
#
# Requires: gem install xcodeproj

require 'fileutils'
require 'json'

begin
  require 'xcodeproj'
rescue LoadError
  puts "Error: xcodeproj gem not found"
  puts "Install with: gem install xcodeproj"
  exit 1
end

# Parse arguments
project_path = nil
module_name = nil
source_file = nil
preview_name = "PreviewHost"
clean = false
dry_run = false

ARGV.each_with_index do |arg, i|
  case arg
  when "--source"
    source_file = ARGV[i + 1]
  when "--preview-name"
    preview_name = ARGV[i + 1]
  when "--clean"
    clean = true
  when "--dry-run"
    dry_run = true
  when "--help", "-h"
    puts File.read(__FILE__).lines[2..15].join
    exit 0
  else
    if !arg.start_with?("--") && ARGV[i - 1] != "--source" && ARGV[i - 1] != "--preview-name"
      if project_path.nil?
        project_path = arg
      elsif module_name.nil?
        module_name = arg
      end
    end
  end
end

if project_path.nil? || module_name.nil?
  puts "Usage: inject-preview-target.rb <project.xcodeproj> <module-name> [--source <file>]"
  exit 1
end

unless File.exist?(project_path)
  puts "Error: Project not found: #{project_path}"
  exit 1
end

puts "Opening project: #{project_path}"
project = Xcodeproj::Project.open(project_path)

# Find the target module
target_module = project.targets.find { |t| t.name == module_name }
unless target_module
  puts "Error: Module '#{module_name}' not found in project"
  puts "Available targets:"
  project.targets.each { |t| puts "  - #{t.name}" }
  exit 1
end

puts "Found module: #{module_name}"

# Check for existing preview target
existing = project.targets.find { |t| t.name == preview_name }
if existing
  if clean
    puts "Removing existing #{preview_name} target..."
    unless dry_run
      existing.remove_from_project
    end
  else
    puts "Preview target '#{preview_name}' already exists"
    puts "Use --clean to remove and recreate"
    exit 0
  end
end

if dry_run
  puts "\n[DRY RUN] Would create:"
  puts "  - Target: #{preview_name}"
  puts "  - Dependency: #{module_name}"
  puts "  - Bundle ID: com.preview.host"
  exit 0
end

# Create preview host source directory
preview_dir = File.join(File.dirname(project_path), preview_name)
FileUtils.mkdir_p(preview_dir)

# Generate preview host app source
preview_source = <<~SWIFT
  // Auto-generated PreviewHost
  // Target module: #{module_name}

  import SwiftUI
  import #{module_name}

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
          NavigationStack {
              Text("Preview Host")
                  .navigationTitle("#{module_name}")
          }
      }
  }
SWIFT

# If source file provided, extract the preview
if source_file && File.exist?(source_file)
  content = File.read(source_file)

  # Extract imports
  imports = content.scan(/^import \w+/).map { |i| i.sub("import ", "") }.uniq
  import_statements = imports.map { |i| "import #{i}" }.join("\n")

  # Extract preview body
  if content =~ /#Preview.*?\{(.*?)^\}/m
    preview_body = $1.strip

    preview_source = <<~SWIFT
      // Auto-generated PreviewHost
      // Source: #{File.basename(source_file)}

      #{import_statements}

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
      #{preview_body.gsub(/^/, '        ')}
          }
      }
    SWIFT
  end

  # Also copy the source file
  FileUtils.cp(source_file, File.join(preview_dir, File.basename(source_file)))
end

# Write preview host source
host_file = File.join(preview_dir, "PreviewHostApp.swift")
File.write(host_file, preview_source)
puts "Created: #{host_file}"

# Create the target
puts "Creating target: #{preview_name}"

preview_target = project.new_target(
  :application,
  preview_name,
  :ios,
  "17.0"
)

# Configure build settings
preview_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.preview.host'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationPortrait'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
end

# Add source files to target
preview_group = project.main_group.new_group(preview_name, preview_dir)

Dir.glob(File.join(preview_dir, "*.swift")).each do |swift_file|
  file_ref = preview_group.new_file(swift_file)
  preview_target.source_build_phase.add_file_reference(file_ref)
  puts "Added source: #{File.basename(swift_file)}"
end

# Add dependency on the module
puts "Adding dependency: #{module_name}"
preview_target.add_dependency(target_module)

# Save project
project.save
puts "Saved project"

# Create scheme
scheme_dir = File.join(project_path, "xcshareddata", "xcschemes")
FileUtils.mkdir_p(scheme_dir)

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(preview_target)
scheme.set_launch_target(preview_target)

scheme_path = File.join(scheme_dir, "#{preview_name}.xcscheme")
scheme.save_as(project_path, preview_name)
puts "Created scheme: #{preview_name}"

puts "\n✅ Preview target created successfully!"
puts "\nTo build and run:"
puts "  xcodebuild -project #{project_path} -scheme #{preview_name} -destination 'platform=iOS Simulator,name=iPhone 17 Pro'"
