//
//  GeminiService.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

struct TokenUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    var totalTokens: Int { promptTokens + completionTokens }
    static let inputCostPerMToken = 0.075
    static let outputCostPerMToken = 0.30
    var estimatedCost: Double {
        Double(promptTokens) * Self.inputCostPerMToken / 1_000_000
        + Double(completionTokens) * Self.outputCostPerMToken / 1_000_000
    }
}

enum GeminiError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(Error)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Gemini API key not found. Set GEMINI_API_KEY environment variable."
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}

actor GeminiService {
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    init() throws {
        // Try environment variable first
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            self.apiKey = key
        } 
        // Try loading from ~/.gemini_api_key file
        else if let key = Self.loadAPIKeyFromFile(), !key.isEmpty {
            self.apiKey = key
        } else {
            throw GeminiError.noAPIKey
        }
    }
    
    private static func loadAPIKeyFromFile() -> String? {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let keyPath = homeDirectory.appendingPathComponent(".gemini_api_key")
        
        guard let key = try? String(contentsOf: keyPath, encoding: .utf8) else {
            return nil
        }
        
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - API Call

    private func call(prompt: String) async throws -> (text: String, usage: TokenUsage?) {
        let url = URL(string: "\(baseURL)?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build payload using plain Foundation types — no actor-isolated model types
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": prompt]]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }

            return try parseResponse(data)

        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.networkError(error)
        }
    }

    private func parseResponse(_ data: Data) throws -> (text: String, usage: TokenUsage?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.invalidResponse
        }

        var usage: TokenUsage? = nil
        if let usageMeta = json["usageMetadata"] as? [String: Any],
           let promptTokens = usageMeta["promptTokenCount"] as? Int,
           let completionTokens = usageMeta["candidatesTokenCount"] as? Int {
            usage = TokenUsage(promptTokens: promptTokens, completionTokens: completionTokens)
        }

        return (text: text, usage: usage)
    }
    
    // MARK: - Convenience Methods

    func askQuestion(
        messages: [Message],
        fileContent: String? = nil,
        question: String,
        priorQA: [QAEntry] = []
    ) async throws -> (String, TokenUsage?) {
        var prompt = ""

        if let fileContent, !fileContent.isEmpty {
            prompt += "Background context:\n\n\(fileContent)\n\n---\n\n"
        }

        prompt += "CONTEXT: In the conversation below, \"Me\" is always Kurt. Keep this in mind when answering questions about the conversation.\n\n"
        prompt += "Here is the full conversation:\n\n"
        for message in messages {
            prompt += "[\(message.messageDate)] \(message.sender): \(message.content)\n"
        }
        prompt += "\n"

        if !priorQA.isEmpty {
            prompt += "Previous questions you have already answered about this conversation:\n"
            for entry in priorQA.suffix(5) {
                prompt += "Q: \(entry.question)\nA: \(entry.answer)\n\n"
            }
            prompt += "---\n\n"
        }

        prompt += "Question: \(question)\n\n"
        prompt += "Answer directly and concisely based on the conversation and any background context provided above. "
        prompt += "If the answer isn't clear from the available information, say so."

        return try await call(prompt: prompt)
    }

    func generateSuggestion(
        messages: [Message],
        context: String? = nil,
        fileContent: String? = nil,
        stylePrompt: String = "Based on this conversation, suggest a thoughtful and appropriate response. Keep it concise and natural. Only return the response text, no preamble or explanation."
    ) async throws -> (String, TokenUsage?) {
        var prompt = ""

        if let fileContent, !fileContent.isEmpty {
            prompt += "Background context (conversation from another app or notes):\n\n"
            prompt += fileContent
            prompt += "\n\n---\n\n"
        }

        prompt += "CONTEXT: You are helping Kurt write his text messages. In the conversation below, \"Me\" is always Kurt. Your job is always to suggest what Kurt should send next — even if Kurt sent the last message (in that case, suggest a natural follow-up). Never write from the other person's perspective.\n\n"
        prompt += "Here is the recent conversation:\n\n"
        for message in messages {
            prompt += "[\(message.messageDate)] \(message.sender): \(message.content)\n"
        }
        prompt += "\n"

        if let context = context, !context.isEmpty {
            prompt += "Context: \(context)\n\n"
        }

        prompt += stylePrompt

        return try await call(prompt: prompt)
    }
}
