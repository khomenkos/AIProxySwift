//
//  AnthropicService.swift
//  
//
//  Created by Lou Zell on 12/13/24.
//

import Foundation

public protocol AnthropicService {
    
    /// Initiates a non-streaming request to /v1/messages.
    ///
    /// - Parameters:
    ///   - body: The message request body. See this reference:
    ///                         https://docs.anthropic.com/en/api/messages
    /// - Returns: The message response body, See this reference:
    ///            https://platform.openai.com/docs/api-reference/chat/object
    func messageRequest(
        body: AnthropicMessageRequestBody
    ) async throws -> AnthropicMessageResponseBody


    /// Initiates a streaming request to /v1/messages.
    ///
    /// - Parameters:
    ///   - body: The message request body. See this reference:
    ///                         https://docs.anthropic.com/en/api/messages
    /// - Returns: The message response body, See this reference:
    ///            https://platform.openai.com/docs/api-reference/chat/object
    func streamingMessageRequest(
        body: AnthropicMessageRequestBody
    ) async throws -> AnthropicAsyncChunks
    
    // additional
    func streamingMessageRequestV2(
        body: AnthropicMessageRequestBody
    ) async throws -> AsyncThrowingStream<AnthropicMessageStreamResponse, Error>
}

extension AnthropicService {
  
  public func fetchStream<T: Decodable>(
    type: T.Type,
    with byteStream: URLSession.AsyncBytes
  ) async throws -> AsyncThrowingStream<T, Error> {

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
            
          for try await line in byteStream.lines {
            // TODO: Test the `event` line
            if line.hasPrefix("data:"),
               let data = line.dropFirst(5).data(using: .utf8) {
#if DEBUG
              print("DEBUG JSON STREAM LINE = \(try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any])")
#endif
              do {
                let decoderWithSnakeCaseStrategy = JSONDecoder()
                decoderWithSnakeCaseStrategy.keyDecodingStrategy = .convertFromSnakeCase
                let decoded = try decoderWithSnakeCaseStrategy.decode(T.self, from: data)
                continuation.yield(decoded)
              } catch let DecodingError.keyNotFound(key, context) {
                let debug = "Key '\(key.stringValue)' not found: \(context.debugDescription)"
                let codingPath = "codingPath: \(context.codingPath)"
                let debugMessage = debug + codingPath
#if DEBUG
                print(debugMessage)
#endif
                throw APIError.dataCouldNotBeReadMissingData(description: debugMessage)
              } catch {
#if DEBUG
                debugPrint("CONTINUATION ERROR DECODING \(error.localizedDescription)")
#endif
                continuation.finish(throwing: error)
              }
            }
          }
          continuation.finish()
        } catch let DecodingError.keyNotFound(key, context) {
          let debug = "Key '\(key.stringValue)' not found: \(context.debugDescription)"
          let codingPath = "codingPath: \(context.codingPath)"
          let debugMessage = debug + codingPath
#if DEBUG
          print(debugMessage)
#endif
          throw APIError.dataCouldNotBeReadMissingData(description: debugMessage)
        } catch {
#if DEBUG
          print("CONTINUATION ERROR DECODING \(error.localizedDescription)")
#endif
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }
}

public enum APIError: Error {
  
  case requestFailed(description: String)
  case responseUnsuccessful(description: String)
  case invalidData
  case jsonDecodingFailure(description: String)
  case dataCouldNotBeReadMissingData(description: String)
  case bothDecodingStrategiesFailed
  case timeOutError
  
  public var displayDescription: String {
    switch self {
    case .requestFailed(let description): return description
    case .responseUnsuccessful(let description): return description
    case .invalidData: return "Invalid data"
    case .jsonDecodingFailure(let description): return description
    case .dataCouldNotBeReadMissingData(let description): return description
    case .bothDecodingStrategiesFailed: return "Decoding strategies failed."
    case .timeOutError: return "Time Out Error."
    }
  }
}

