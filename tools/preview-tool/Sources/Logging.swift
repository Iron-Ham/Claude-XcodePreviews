import Foundation

// MARK: - LogLevel

public enum LogLevel {
  case info
  case success
  case warning
  case error
}

public func log(_ level: LogLevel, _ message: String) {
  let prefix =
    switch level {
    case .info: "\u{001B}[0;34m[INFO]\u{001B}[0m"
    case .success: "\u{001B}[0;32m[SUCCESS]\u{001B}[0m"
    case .warning: "\u{001B}[1;33m[WARNING]\u{001B}[0m"
    case .error: "\u{001B}[0;31m[ERROR]\u{001B}[0m"
    }
  let output = "\(prefix) \(message)\n"
  if level == .error {
    FileHandle.standardError.write(Data(output.utf8))
  } else {
    print("\(prefix) \(message)")
  }
}

public var verbose = false

public func logVerbose(_ message: String) {
  if verbose {
    log(.info, message)
  }
}
