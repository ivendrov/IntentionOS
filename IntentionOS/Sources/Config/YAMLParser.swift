import Foundation

/// Simple YAML parser for the subset of YAML used in Intention OS config files
class YAMLParser {

    enum YAMLValue {
        case string(String)
        case int(Int)
        case bool(Bool)
        case array([YAMLValue])
        case dictionary([String: YAMLValue])
        case null

        var stringValue: String? {
            if case .string(let s) = self { return s }
            return nil
        }

        var intValue: Int? {
            if case .int(let i) = self { return i }
            return nil
        }

        var boolValue: Bool? {
            if case .bool(let b) = self { return b }
            return nil
        }

        var arrayValue: [YAMLValue]? {
            if case .array(let a) = self { return a }
            return nil
        }

        var dictionaryValue: [String: YAMLValue]? {
            if case .dictionary(let d) = self { return d }
            return nil
        }
    }

    struct ParseError: Error {
        let message: String
        let line: Int
    }

    func parse(_ yaml: String) throws -> YAMLValue {
        let lines = yaml.components(separatedBy: .newlines)
        var index = 0
        return try parseValue(lines: lines, index: &index, baseIndent: 0)
    }

    private func parseValue(lines: [String], index: inout Int, baseIndent: Int) throws -> YAMLValue {
        // Skip empty lines and comments
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            break
        }

        guard index < lines.count else { return .null }

        let line = lines[index]
        let indent = getIndent(line)

        // Check if it's a list item
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") {
            return try parseArray(lines: lines, index: &index, baseIndent: indent)
        }

        // Check if it's a key-value pair
        if let colonIndex = trimmed.firstIndex(of: ":") {
            return try parseDictionary(lines: lines, index: &index, baseIndent: indent)
        }

        // Simple value
        index += 1
        return parseScalar(trimmed)
    }

    private func parseDictionary(lines: [String], index: inout Int, baseIndent: Int) throws -> YAMLValue {
        var dict: [String: YAMLValue] = [:]

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            let currentIndent = getIndent(line)

            // If we've dedented, we're done with this dictionary
            if currentIndent < baseIndent {
                break
            }

            // If we're at a different indent level than expected, break
            if currentIndent != baseIndent {
                index += 1
                continue
            }

            // Parse key
            guard let colonIndex = trimmed.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let afterColon = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            if afterColon.isEmpty {
                // Value is on next lines (nested structure)
                index += 1
                // Look ahead to find the next non-empty line's indent
                var nextIndent = baseIndent + 2
                var lookAhead = index
                while lookAhead < lines.count {
                    let nextLine = lines[lookAhead]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if !nextTrimmed.isEmpty && !nextTrimmed.hasPrefix("#") {
                        nextIndent = getIndent(nextLine)
                        break
                    }
                    lookAhead += 1
                }
                dict[key] = try parseValue(lines: lines, index: &index, baseIndent: nextIndent)
            } else if afterColon.hasPrefix("[") && afterColon.hasSuffix("]") {
                // Inline array
                let content = String(afterColon.dropFirst().dropLast())
                let items = content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                dict[key] = .array(items.filter { !$0.isEmpty }.map { parseScalar($0) })
                index += 1
            } else {
                // Inline value
                dict[key] = parseScalar(afterColon)
                index += 1
            }
        }

        return .dictionary(dict)
    }

    private func parseArray(lines: [String], index: inout Int, baseIndent: Int) throws -> YAMLValue {
        var array: [YAMLValue] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            let currentIndent = getIndent(line)

            // If we've dedented, we're done with this array
            if currentIndent < baseIndent {
                break
            }

            // If we're not at the base indent for this array, might be nested content
            if currentIndent != baseIndent {
                index += 1
                continue
            }

            // Must be a list item at this point
            guard trimmed.hasPrefix("- ") else {
                break
            }

            let afterDash = String(trimmed.dropFirst(2))

            // Check if it's a nested object (key: value after -)
            if let colonIndex = afterDash.firstIndex(of: ":") {
                // It's an object, parse it
                let key = String(afterDash[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(afterDash[afterDash.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

                var objDict: [String: YAMLValue] = [:]

                if value.isEmpty {
                    // Nested structure
                    index += 1
                    let nestedIndent = baseIndent + 2
                    let nested = try parseValue(lines: lines, index: &index, baseIndent: nestedIndent)
                    if case .dictionary(let d) = nested {
                        objDict[key] = nested
                        // Merge any additional keys at the same level
                        for (k, v) in d {
                            objDict[key] = nested
                        }
                    } else {
                        objDict[key] = nested
                    }
                } else {
                    objDict[key] = parseScalar(value)
                    index += 1
                }

                // Continue parsing additional keys for this object
                while index < lines.count {
                    let nextLine = lines[index]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    let nextIndent = getIndent(nextLine)

                    if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("#") {
                        index += 1
                        continue
                    }

                    // Check if we're still in the object (indented more than the list item)
                    if nextIndent <= baseIndent {
                        break
                    }

                    // Parse additional key-value pairs
                    if let colonIdx = nextTrimmed.firstIndex(of: ":") {
                        let k = String(nextTrimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        let v = String(nextTrimmed[nextTrimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                        if v.isEmpty {
                            index += 1
                            objDict[k] = try parseValue(lines: lines, index: &index, baseIndent: nextIndent + 2)
                        } else if v.hasPrefix("[") && v.hasSuffix("]") {
                            // Inline array
                            let content = String(v.dropFirst().dropLast())
                            let items = content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            objDict[k] = .array(items.filter { !$0.isEmpty }.map { parseScalar($0) })
                            index += 1
                        } else {
                            objDict[k] = parseScalar(v)
                            index += 1
                        }
                    } else {
                        break
                    }
                }

                array.append(.dictionary(objDict))
            } else {
                // Simple value
                array.append(parseScalar(afterDash))
                index += 1
            }
        }

        return .array(array)
    }

    private func parseScalar(_ value: String) -> YAMLValue {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Remove quotes if present
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return .string(String(trimmed.dropFirst().dropLast()))
        }

        // Check for boolean
        if trimmed.lowercased() == "true" || trimmed.lowercased() == "yes" {
            return .bool(true)
        }
        if trimmed.lowercased() == "false" || trimmed.lowercased() == "no" {
            return .bool(false)
        }

        // Check for null
        if trimmed.lowercased() == "null" || trimmed == "~" || trimmed.isEmpty {
            return .null
        }

        // Check for integer
        if let intVal = Int(trimmed) {
            return .int(intVal)
        }

        return .string(trimmed)
    }

    private func getIndent(_ line: String) -> Int {
        var count = 0
        for char in line {
            if char == " " {
                count += 1
            } else if char == "\t" {
                count += 2
            } else {
                break
            }
        }
        return count
    }
}

// MARK: - Convenience extensions for decoding

extension YAMLParser.YAMLValue {
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: toJSON())
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    private func toJSON() -> Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { $0.toJSON() }
        case .dictionary(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = value.toJSON()
            }
            return result
        }
    }
}
