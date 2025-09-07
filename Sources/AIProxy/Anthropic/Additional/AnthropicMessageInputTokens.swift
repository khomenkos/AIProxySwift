//
//  AnthropicMessageInputTokens.swift
//  AIProxy
//
//  Created by Mac Mini on 06.09.2025.
//

import Foundation

public struct AnthropicMessageInputTokens: Decodable {
   
   /// The total number of tokens across the provided list of messages, system prompt, and tools.
   public let inputTokens: Int
   
   public init(from decoder: Decoder) throws {
      if let container = try? decoder.singleValueContainer(),
         let dict = try? container.decode([String: Int].self),
         let tokens = dict["input_tokens"] {
         self.inputTokens = tokens
      } else {
         // Try regular JSON decoding as fallback
         let container = try decoder.container(keyedBy: CodingKeys.self)
         self.inputTokens = try container.decode(Int.self, forKey: .inputTokens)
      }
   }
   
   private enum CodingKeys: String, CodingKey {
      case inputTokens = "input_tokens"
   }
}
