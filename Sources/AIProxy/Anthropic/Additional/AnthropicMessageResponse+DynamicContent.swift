//
//  MessageResponse+DynamicContent.swift
//  AIProxy
//
//  Created by Mac Mini on 06.09.2025.
//

import Foundation

public extension Dictionary where Key == String, Value == AnthropicMessageResponse.Content.DynamicContent {
  
  /// Creates a formatted string representation of the dictionary
  /// - Parameters:
  ///   - indent: The indentation level (default: 0)
  ///   - indentSize: Number of spaces per indent level (default: 2)
  /// - Returns: A formatted string representation
  func formattedDescription(indent: Int = 0, indentSize: Int = 2) -> String {
    let indentation = String(repeating: " ", count: indent * indentSize)
    let nextIndent = indent + 1
    
    return self.map { key, value in
      let valueStr = formatValue(value, indent: nextIndent, indentSize: indentSize)
      return "\(indentation)\(key): \(valueStr)"
    }.joined(separator: "\n")
  }
  
  /// Formats a single DynamicContent value
  private func formatValue(_ value: AnthropicMessageResponse.Content.DynamicContent, indent: Int, indentSize: Int) -> String {
    let indentation = String(repeating: " ", count: indent * indentSize)
    
    switch value {
    case .string(let str):
      return "\"\(str)\""
      
    case .integer(let num):
      return "\(num)"
      
    case .double(let num):
      return "\(num)"
      
    case .bool(let bool):
      return "\(bool)"
      
    case .null:
      return "null"
      
    case .dictionary(let dict):
      let dictStr = dict.formattedDescription(indent: indent + 1, indentSize: indentSize)
      return "{\n\(dictStr)\n\(indentation)}"
      
    case .array(let arr):
      if arr.isEmpty {
        return "[]"
      }
      
      let items = arr.enumerated().map { index, item in
        let itemStr = formatValue(item, indent: indent + 1, indentSize: indentSize)
        return "\(indentation)  [\(index)]: \(itemStr)"
      }.joined(separator: "\n")
      
      return "[\n\(items)\n\(indentation)]"
    }
  }
}
