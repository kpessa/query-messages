//
//  ViewsSharedHelpers.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/26/26.
//

import SwiftUI

/// Renders a string as markdown if possible, falling back to plain text.
func markdownText(_ string: String) -> Text {
    if let attributed = try? AttributedString(markdown: string) {
        return Text(attributed)
    }
    return Text(string)
}

/// "45" for small counts, "1.2K" for thousands.
func formatTokenCount(_ n: Int) -> String {
    guard n >= 1000 else { return "\(n)" }
    let k = Double(n) / 1000.0
    if k.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(k))K"
    }
    return String(format: "%.1fK", k)
}

/// "~$0.0002", "~$0.003", "~$0.05", or "<$0.0001".
func formatCost(_ cost: Double) -> String {
    guard cost >= 0.0001 else { return "<$0.0001" }
    if cost >= 0.01 { return String(format: "~$%.2f", cost) }
    if cost >= 0.001 { return String(format: "~$%.3f", cost) }
    return String(format: "~$%.4f", cost)
}

/// "1.2K tokens · ~$0.0002"
func formatTokenBadge(_ usage: TokenUsage) -> String {
    "\(formatTokenCount(usage.totalTokens)) tokens · \(formatCost(usage.estimatedCost))"
}
