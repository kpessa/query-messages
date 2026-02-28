//
//  ModelsQAEntry.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/26/26.
//

import Foundation

struct QAEntry: Identifiable, Codable {
    let id: UUID
    let question: String
    let answer: String
    let date: Date
    let tokenUsage: TokenUsage?

    init(question: String, answer: String, tokenUsage: TokenUsage? = nil) {
        self.id = UUID()
        self.question = question
        self.answer = answer
        self.date = Date()
        self.tokenUsage = tokenUsage
    }
}
