//
//  ExternalFileService.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

actor ExternalFileService {
    
    func loadMessages(from url: URL) throws -> [Message] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseMessages(content)
    }
    
    private func parseMessages(_ content: String) -> [Message] {
        var messages: [Message] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentDate = ""
        var currentSender = ""
        var currentText = ""
        
        for line in lines {
            // Skip empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            // Check if line starts with timestamp pattern
            if let match = line.firstMatch(of: /^\[(.+?)\] (.+?): (.*)/) {
                // Save previous message if exists
                if !currentSender.isEmpty && !currentText.isEmpty {
                    messages.append(Message(
                        messageDate: currentDate,
                        sender: currentSender,
                        content: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
                
                // Start new message
                currentDate = String(match.1)
                currentSender = String(match.2)
                currentText = String(match.3)
            } else {
                // Continuation of previous message
                currentText += "\n" + line
            }
        }
        
        // Add last message
        if !currentSender.isEmpty && !currentText.isEmpty {
            messages.append(Message(
                messageDate: currentDate,
                sender: currentSender,
                content: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        
        return messages
    }
}
