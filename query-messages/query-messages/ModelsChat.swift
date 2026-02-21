//
//  Chat.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

struct Chat: Identifiable, Hashable {
    let id: Int64          // chatID (ROWID)
    let participants: [String]
    let messageCount: Int64
    let lastMessageDate: String
    let lastMessageDateRaw: Int64
    var pinnedDate: Int64 = 0        // non-zero = pinned in Messages.app
    var isPinnedByUser: Bool = false  // custom pin stored in UserDefaults

    var isPinned: Bool { pinnedDate != 0 || isPinnedByUser }
    var displayName: String {
        participants.isEmpty ? "Unknown" : participants.joined(separator: ", ")
    }
}
