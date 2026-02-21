//
//  GeminiConversation.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

struct GeminiMessage: Codable {
    let role: String  // "user" or "model"
    let parts: [Part]
    
    struct Part: Codable {
        let text: String
    }
    
    init(role: String, text: String) {
        self.role = role
        self.parts = [Part(text: text)]
    }
}

@Observable
class GeminiConversation {
    var messages: [GeminiMessage] = []
    
    func addUserMessage(_ text: String) {
        messages.append(GeminiMessage(role: "user", text: text))
    }
    
    func addModelResponse(_ text: String) {
        messages.append(GeminiMessage(role: "model", text: text))
    }
    
    func reset() {
        messages.removeAll()
    }
}
