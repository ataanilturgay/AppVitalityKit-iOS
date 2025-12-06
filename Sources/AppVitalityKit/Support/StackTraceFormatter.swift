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
        // Example input:
        // "3   iOSBilyonerCase   0x0000000104e83538 $s15iOSBilyonerCase18CartViewControllerC11viewDidLoadyyF + 268"
        
        let parsed = parseSymbol(symbol)
        
        var result = "\(String(format: "%2d", index)). "
        
        if let parsed = parsed {
            // App code - show demangled name
            if parsed.isAppCode {
                let demangled = demangle(parsed.symbolName) ?? parsed.symbolName
                result += "[\(parsed.moduleName)] \(demangled)"
                if let offset = parsed.offset {
                    result += " +\(offset)"
                }
            } else {
                // System framework - show condensed
                result += "[\(parsed.moduleName)] \(parsed.symbolName)"
            }
        } else {
            // Couldn't parse, show original
            result += symbol.trimmingCharacters(in: .whitespaces)
        }
        
        return result
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
        // Pattern: "3   ModuleName   0x00000001 symbolName + 123"
        let components = symbol.split(separator: " ", omittingEmptySubsequences: true)
        
        guard components.count >= 4 else { return nil }
        
        guard let frameNumber = Int(components[0]) else { return nil }
        
        let moduleName = String(components[1])
        let address = String(components[2])
        
        // Find symbol name and offset
        var symbolName = ""
        var offset: Int?
        
        // Everything after address until "+" or end
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
        
        // Determine if it's app code (not system framework)
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
    
    /// Attempts to demangle Swift symbols into readable format
    /// Uses simplified parsing (full demangling would require Swift runtime)
    private func demangle(_ symbol: String) -> String? {
        // Swift symbols start with $s or _$s
        guard symbol.hasPrefix("$s") || symbol.hasPrefix("_$s") else {
            // Might be Obj-C, return as-is with cleanup
            return cleanObjCSymbol(symbol)
        }
        
        // Try to extract readable parts from mangled Swift symbol
        // Example: $s15iOSBilyonerCase18CartViewControllerC11viewDidLoadyyF
        // Format: $s<module_length><module><class_length><class>...<method>
        
        var result = parseSwiftSymbol(symbol)
        return result
    }
    
    private func parseSwiftSymbol(_ symbol: String) -> String {
        var s = symbol
        
        // Remove prefix
        if s.hasPrefix("_$s") {
            s = String(s.dropFirst(3))
        } else if s.hasPrefix("$s") {
            s = String(s.dropFirst(2))
        }
        
        var parts: [String] = []
        var index = s.startIndex
        
        // Parse length-prefixed strings
        while index < s.endIndex {
            // Try to read a number (length)
            var lengthStr = ""
            while index < s.endIndex, let digit = Int(String(s[index])), digit >= 0 && digit <= 9 {
                lengthStr += String(s[index])
                index = s.index(after: index)
            }
            
            if let length = Int(lengthStr), length > 0 {
                // Read 'length' characters
                let endIndex = s.index(index, offsetBy: min(length, s.distance(from: index, to: s.endIndex)))
                let part = String(s[index..<endIndex])
                parts.append(part)
                index = endIndex
            } else {
                // Skip unknown character
                if index < s.endIndex {
                    index = s.index(after: index)
                }
            }
        }
        
        // Build readable string
        if parts.count >= 2 {
            // Usually: Module, Class, Method
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
        // Remove common prefixes/suffixes
        var s = symbol
        
        // Remove leading underscores
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
    
    /// Finds the first app code frame (likely crash location)
    private func findCrashLocation(in symbols: [String]) -> String? {
        for symbol in symbols {
            if let parsed = parseSymbol(symbol), parsed.isAppCode {
                let demangled = demangle(parsed.symbolName) ?? parsed.symbolName
                return "[\(parsed.moduleName)] \(demangled)"
            }
        }
        return nil
    }
}

// MARK: - Convenience Extensions

public extension Array where Element == String {
    /// Formats stack trace symbols for readability
    var formattedStackTrace: String {
        return StackTraceFormatter.shared.format(self)
    }
}
