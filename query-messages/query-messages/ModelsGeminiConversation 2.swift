//
//  GeminiConversation.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

/// Represents a part of a Gemini message
struct GeminiPart {
    let text: String
}

/// Represents a single message in a Gemini conversation
struct GeminiMessage {
    let role: String  // "user" or "model"
    let parts: [GeminiPart]
}

/// Manages the conversation history for Gemini API calls
@Observable
class GeminiConversation {
    var messages: [GeminiMessage] = []
    
    /// Add a user message to the conversation
    func addUserMessage(_ text: String) {
        let part = GeminiPart(text: text)
        let message = GeminiMessage(role: "user", parts: [part])
        messages.append(message)
    }
    
    /// Add a model response to the conversation
    func addModelResponse(_ text: String) {
        let part = GeminiPart(text: text)
        let message = GeminiMessage(role: "model", parts: [part])
        messages.append(message)
    }
    
    /// Reset the conversation
    func reset() {
        messages.removeAll()
    }
}
