#!/usr/bin/env ruby
# preview-helper.rb - Ruby utilities for preview capture
#
# Usage:
#   ruby preview-helper.rb find-simulator "iPhone 17 Pro"
#   ruby preview-helper.rb extract-preview path/to/file.swift
#   ruby preview-helper.rb simulator-state <udid>

require 'json'

def find_simulator(name)
  json = `xcrun simctl list devices available -j 2>/dev/null`
  data = JSON.parse(json)

  # Collect all matching devices with their runtime version
  candidates = []
  data['devices'].each do |runtime, devices|
    next unless runtime.include?('iOS')
    # Extract version number (e.g., "com.apple.CoreSimulator.SimRuntime.iOS-26-2" -> [26, 2])
    version_parts = runtime.scan(/(\d+)/).flatten.map(&:to_i)
    devices.each do |device|
      if device['name'] == name && device['isAvailable']
        candidates << { udid: device['udid'], version: version_parts }
      end
    end
  end

  if candidates.empty?
    exit 1
  end

  # Sort by version descending (latest runtime first) and pick the first
  best = candidates.sort_by { |c| c[:version] }.last
  puts best[:udid]
  exit 0
end

def simulator_state(udid)
  json = `xcrun simctl list devices -j 2>/dev/null`
  data = JSON.parse(json)

  data['devices'].each do |_, devices|
    devices.each do |device|
      if device['udid'] == udid
        puts device['state']
        exit 0
      end
    end
  end

  puts 'Unknown'
end

def first_booted_simulator
  json = `xcrun simctl list devices booted -j 2>/dev/null`
  data = JSON.parse(json)

  data['devices'].each do |_, devices|
    devices.each do |device|
      if device['state'] == 'Booted'
        puts device['udid']
        exit 0
      end
    end
  end

  exit 1
end

def extract_preview(file_path)
  unless File.exist?(file_path)
    puts 'Text("File not found")'
    exit 0
  end

  content = File.read(file_path)

  # Find #Preview and extract its body using brace counting
  # Match #Preview with optional parameters: #Preview { }, #Preview("name") { }, #Preview(traits: ...) { }
  match = content.match(/#Preview(?:\s*\([^)]*\))?\s*\{/)

  unless match
    puts 'Text("No #Preview found")'
    exit 0
  end

  # Start after the opening brace
  start_pos = match.end(0)
  brace_count = 1
  pos = start_pos

  while pos < content.length && brace_count > 0
    char = content[pos]
    if char == '{'
      brace_count += 1
    elsif char == '}'
      brace_count -= 1
    end
    pos += 1
  end

  if brace_count != 0
    puts 'Text("Malformed #Preview")'
    exit 0
  end

  # Extract body (excluding final closing brace)
  body = content[start_pos...pos-1]

  # Split into lines and remove leading/trailing empty lines
  lines = body.split("\n")
  lines.shift while lines.any? && lines.first.strip.empty?
  lines.pop while lines.any? && lines.last.strip.empty?

  return if lines.empty?

  # Find minimum indentation (excluding empty lines)
  min_indent = lines
    .reject { |line| line.strip.empty? }
    .map { |line| line.length - line.lstrip.length }
    .min || 0

  # Dedent all lines
  if min_indent > 0
    lines = lines.map do |line|
      line.length >= min_indent ? line[min_indent..] : line
    end
  end

  puts lines.join("\n")
end

def simulator_info(udid)
  json = `xcrun simctl list devices -j 2>/dev/null`
  data = JSON.parse(json)

  data['devices'].each do |_, devices|
    devices.each do |device|
      if device['udid'] == udid
        puts "#{device['name']} (#{device['state']})"
        exit 0
      end
    end
  end

  puts 'Unknown simulator'
end

def first_booted_info
  json = `xcrun simctl list devices booted -j 2>/dev/null`
  data = JSON.parse(json)

  data['devices'].each do |_, devices|
    devices.each do |device|
      if device['state'] == 'Booted'
        puts "#{device['name']} (#{device['udid']})"
        exit 0
      end
    end
  end

  puts 'No booted simulator'
end

# Main command dispatch
case ARGV[0]
when 'find-simulator'
  find_simulator(ARGV[1])
when 'simulator-state'
  simulator_state(ARGV[1])
when 'first-booted'
  first_booted_simulator
when 'first-booted-info'
  first_booted_info
when 'simulator-info'
  simulator_info(ARGV[1])
when 'extract-preview'
  extract_preview(ARGV[1])
else
  STDERR.puts "Usage: preview-helper.rb <command> [args]"
  STDERR.puts "Commands:"
  STDERR.puts "  find-simulator <name>   - Find simulator UDID by name"
  STDERR.puts "  simulator-state <udid>  - Get simulator state"
  STDERR.puts "  first-booted            - Get first booted simulator UDID"
  STDERR.puts "  extract-preview <file>  - Extract #Preview body from Swift file"
  exit 1
end
