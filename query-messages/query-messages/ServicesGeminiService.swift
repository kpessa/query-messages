//
//  GeminiService.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

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

    private func call(prompt: String) async throws -> String {
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
    
    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.invalidResponse
        }
        
        return text
    }
    
    // MARK: - Convenience Methods

    func generateSuggestion(
        messages: [Message],
        context: String? = nil,
        stylePrompt: String = "Based on this conversation, suggest a thoughtful and appropriate response. Keep it concise and natural. Only return the response text, no preamble or explanation."
    ) async throws -> String {
        var prompt = "Here is the recent conversation:\n\n"
        for message in messages.suffix(20) {
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
