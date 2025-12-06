import Foundation

/// Formats stack traces for better readability
public class StackTraceFormatter {
    
    public static let shared = StackTraceFormatter()
    
    private init() {}
    
    /// Formats raw stack trace symbols into readable format
    /// - Parameter symbols: Array of stack frame strings from Thread.callStackSymbols or NSException.callStackSymbols
    /// - Returns: Formatted stack trace string
    public func format(_ symbols: [String]) -> String {
        let frames = symbols.enumerated().map { index, symbol in
            formatFrame(index: index, symbol: symbol)
        }
        return frames.joined(separator: "\n")
    }
    
    /// Formats a single stack frame
    private func formatFrame(index: Int, symbol: String) -> String {
        let parsed = parseSymbol(symbol)
        
        var result = "\(String(format: "%2d", index)). "
        
        if let parsed = parsed {
            if parsed.isAppCode {
                // App code - show demangled name with estimated line
                let demangled = demangle(parsed.symbolName) ?? parsed.symbolName
                result += "[\(parsed.moduleName)] \(demangled)"
                
                if let offset = parsed.offset {
                    // Show byte offset and estimated line number
                    let estimatedLine = estimateLineNumber(byteOffset: offset)
                    result += " (offset: +\(offset), ~line \(estimatedLine))"
                }
            } else {
                // System framework - check if it's just a UUID
                if isUUID(parsed.symbolName) {
                    result += "[\(parsed.moduleName)] (system)"
                } else {
                    result += "[\(parsed.moduleName)] \(parsed.symbolName)"
                }
            }
        } else {
            result += symbol.trimmingCharacters(in: .whitespaces)
        }
        
        return result
    }
    
    /// Checks if a string is a UUID (no symbol info available)
    private func isUUID(_ string: String) -> Bool {
        let uuidPattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$"
        return string.range(of: uuidPattern, options: .regularExpression) != nil
    }
    
    /// Estimates line number from byte offset
    /// Assumes ~4 bytes per line on average (ARM64 instruction size)
    /// This is a rough estimate - accurate line numbers require dSYM
    private func estimateLineNumber(byteOffset: Int) -> String {
        // ARM64: typically 4 bytes per instruction
        // Swift code: roughly 2-4 instructions per source line
        // Estimate: ~8-16 bytes per line, use 10 as middle ground
        let estimatedLines = max(1, byteOffset / 10)
        return "~\(estimatedLines)"
    }
    
    // MARK: - Symbol Parsing
    
    private struct ParsedSymbol {
        let frameNumber: Int
        let moduleName: String
        let address: String
        let symbolName: String
        let offset: Int?
        let isAppCode: Bool
    }
    
    private func parseSymbol(_ symbol: String) -> ParsedSymbol? {
        let components = symbol.split(separator: " ", omittingEmptySubsequences: true)
        
        guard components.count >= 4 else { return nil }
        guard let frameNumber = Int(components[0]) else { return nil }
        
        let moduleName = String(components[1])
        let address = String(components[2])
        
        var symbolName = ""
        var offset: Int?
        var symbolParts: [String] = []
        var foundPlus = false
        
        for i in 3..<components.count {
            let part = String(components[i])
            if part == "+" {
                foundPlus = true
            } else if foundPlus {
                offset = Int(part)
            } else {
                symbolParts.append(part)
            }
        }
        
        symbolName = symbolParts.joined(separator: " ")
        
        let systemFrameworks = [
            "UIKitCore", "CoreFoundation", "Foundation", "libsystem",
            "libobjc", "libdispatch", "GraphicsServices", "dyld",
            "CoreGraphics", "QuartzCore", "Security", "CFNetwork"
        ]
        
        let isAppCode = !systemFrameworks.contains { moduleName.contains($0) }
        
        return ParsedSymbol(
            frameNumber: frameNumber,
            moduleName: moduleName,
            address: address,
            symbolName: symbolName,
            offset: offset,
            isAppCode: isAppCode
        )
    }
    
    // MARK: - Swift Symbol Demangling
    
    private func demangle(_ symbol: String) -> String? {
        guard symbol.hasPrefix("$s") || symbol.hasPrefix("_$s") else {
            return cleanObjCSymbol(symbol)
        }
        return parseSwiftSymbol(symbol)
    }
    
    private func parseSwiftSymbol(_ symbol: String) -> String {
        var s = symbol
        
        if s.hasPrefix("_$s") {
            s = String(s.dropFirst(3))
        } else if s.hasPrefix("$s") {
            s = String(s.dropFirst(2))
        }
        
        var parts: [String] = []
        var index = s.startIndex
        
        while index < s.endIndex {
            var lengthStr = ""
            while index < s.endIndex, let digit = Int(String(s[index])), digit >= 0 && digit <= 9 {
                lengthStr += String(s[index])
                index = s.index(after: index)
            }
            
            if let length = Int(lengthStr), length > 0 {
                let endIndex = s.index(index, offsetBy: min(length, s.distance(from: index, to: s.endIndex)))
                let part = String(s[index..<endIndex])
                parts.append(part)
                index = endIndex
            } else {
                if index < s.endIndex {
                    index = s.index(after: index)
                }
            }
        }
        
        if parts.count >= 2 {
            let className = parts.count >= 2 ? parts[1] : ""
            let methodName = parts.count >= 3 ? parts[2] : ""
            
            if !methodName.isEmpty {
                return "\(className).\(methodName)()"
            } else if !className.isEmpty {
                return className
            }
        }
        
        return parts.joined(separator: ".")
    }
    
    private func cleanObjCSymbol(_ symbol: String) -> String {
        var s = symbol
        while s.hasPrefix("_") {
            s = String(s.dropFirst())
        }
        return s
    }
    
    // MARK: - Crash Summary
    
    /// Generates a human-readable crash summary
    public func generateSummary(
        title: String,
        reason: String?,
        stackSymbols: [String],
        breadcrumbs: [String]
    ) -> String {
        
        var summary = """
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        💥 CRASH: \(title)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        """
        
        if let reason = reason {
            summary += "Reason: \(reason)\n\n"
        }
        
        // Find the crash location (first app code frame)
        if let crashLocation = findCrashLocation(in: stackSymbols) {
            summary += """
            📍 Crash Location:
               \(crashLocation)
            
            """
        }
        
        // Last user actions
        if !breadcrumbs.isEmpty {
            summary += """
            
            👆 Last User Actions:
            
            """
            for crumb in breadcrumbs.suffix(5) {
                summary += "   • \(crumb)\n"
            }
        }
        
        // Formatted stack trace (app code only for summary)
        summary += """
        
        📚 Stack Trace (App Code):
        
        """
        
        let appFrames = stackSymbols.enumerated().compactMap { index, symbol -> String? in
            let parsed = parseSymbol(symbol)
            guard let p = parsed, p.isAppCode else { return nil }
            return formatFrame(index: index, symbol: symbol)
        }
        
        if appFrames.isEmpty {
            summary += "   (No app code frames found)\n"
        } else {
            for frame in appFrames.prefix(10) {
                summary += "   \(frame)\n"
            }
        }
        
        summary += "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        return summary
    }
    
    /// Finds the first app code frame with detailed info
    private func findCrashLocation(in symbols: [String]) -> String? {
        for symbol in symbols {
            if let parsed = parseSymbol(symbol), parsed.isAppCode {
                let demangled = demangle(parsed.symbolName) ?? parsed.symbolName
                var location = "[\(parsed.moduleName)] \(demangled)"
                
                if let offset = parsed.offset {
                    let estimatedLine = estimateLineNumber(byteOffset: offset)
                    location += " (byte +\(offset), estimated line \(estimatedLine))"
                }
                
                return location
            }
        }
        return nil
    }
}

// MARK: - Convenience Extensions

public extension Array where Element == String {
    var formattedStackTrace: String {
        return StackTraceFormatter.shared.format(self)
    }
}
