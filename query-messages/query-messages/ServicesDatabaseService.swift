//
//  DatabaseService.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation
import SQLite3

enum DatabaseError: Error, LocalizedError {
    case cannotOpenDatabase(String)
    case queryFailed(String)
    case fullDiskAccessRequired
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenDatabase(let path):
            return "Cannot open database at \(path). Full Disk Access may be required."
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .fullDiskAccessRequired:
            return "Full Disk Access required to read iMessage database."
        }
    }
}

actor DatabaseService {
    private let dbPath: String
    
    init(dbPath: String? = nil) {
        self.dbPath = dbPath ?? "\(NSHomeDirectory())/Library/Messages/chat.db"
    }
    
    // MARK: - Chat List
    
    func getAvailableChats() async throws -> [Chat] {
        return try await withCheckedThrowingContinuation { continuation in
            var db: OpaquePointer?
            
            guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                continuation.resume(throwing: DatabaseError.fullDiskAccessRequired)
                return
            }
            
            defer { sqlite3_close(db) }

            // pinned_date was added in a later macOS version — check before selecting it
            let hasPinnedDate = Self.columnExists(db: db, table: "chat", column: "pinned_date")
            let pinnedColumn = hasPinnedDate ? "COALESCE(c.pinned_date, 0)" : "0"

            let query = """
            SELECT
                c.ROWID as chatID,
                COUNT(m.ROWID) as messageCount,
                MAX(m.date) as lastMessageDate,
                \(pinnedColumn) as pinned_date
            FROM chat c
            LEFT JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
            LEFT JOIN message m ON cmj.message_id = m.ROWID
            GROUP BY c.ROWID
            HAVING messageCount > 0
            ORDER BY lastMessageDate DESC
            """
            
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed(error))
                return
            }
            
            defer { sqlite3_finalize(stmt) }
            
            var chats: [Chat] = []
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let chatID = sqlite3_column_int64(stmt, 0)
                let messageCount = sqlite3_column_int64(stmt, 1)
                let lastMessageDateRaw = sqlite3_column_int64(stmt, 2)
                let pinnedDate = sqlite3_column_int64(stmt, 3)

                // Convert Apple's Core Data timestamp (seconds since 2001-01-01) to Date
                let lastMessageDate = Self.formatAppleDate(lastMessageDateRaw)

                // Fetch participants synchronously within the same continuation
                let participants = self.getParticipantsSync(for: chatID, db: db)

                let chat = Chat(
                    id: chatID,
                    participants: participants,
                    messageCount: messageCount,
                    lastMessageDate: lastMessageDate,
                    lastMessageDateRaw: lastMessageDateRaw,
                    pinnedDate: pinnedDate
                )
                chats.append(chat)
            }
            
            continuation.resume(returning: chats)
        }
    }
    
    private func getParticipantsSync(for chatID: Int64, db: OpaquePointer?) -> [String] {
        let query = """
        SELECT h.id
        FROM chat c
        JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
        JOIN handle h ON chj.handle_id = h.ROWID
        WHERE c.ROWID = ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, chatID)
        
        var participants: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                participants.append(String(cString: cString))
            }
        }
        
        return participants
    }
    
    // MARK: - Messages
    
    func fetchMessages(for chatID: Int64, limit: Int = 100) async throws -> [Message] {
        return try await withCheckedThrowingContinuation { continuation in
            var db: OpaquePointer?
            
            guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                continuation.resume(throwing: DatabaseError.fullDiskAccessRequired)
                return
            }
            
            defer { sqlite3_close(db) }
            
            let query = """
            SELECT
                m.date,
                m.is_from_me,
                COALESCE(m.text, '') as text,
                m.attributedBody,
                h.id as sender_id,
                COALESCE(m.associated_message_type, 0) as reaction_type,
                (SELECT a.mime_type FROM message_attachment_join maj
                 JOIN attachment a ON maj.attachment_id = a.ROWID
                 WHERE maj.message_id = m.ROWID LIMIT 1) as mime_type,
                (SELECT a.transfer_name FROM message_attachment_join maj
                 JOIN attachment a ON maj.attachment_id = a.ROWID
                 WHERE maj.message_id = m.ROWID LIMIT 1) as attachment_name
            FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            WHERE cmj.chat_id = ?
            ORDER BY m.date DESC
            LIMIT ?
            """
            
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed(error))
                return
            }
            
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_int64(stmt, 1, chatID)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            
            var messages: [Message] = []
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dateRaw = sqlite3_column_int64(stmt, 0)
                let isFromMe = sqlite3_column_int(stmt, 1) == 1
                let reactionType = sqlite3_column_int64(stmt, 5)

                let messageDate = Self.formatAppleDate(dateRaw)
                let sender = isFromMe ? "Me" : self.getSenderSync(stmt: stmt, isFromMe: isFromMe)

                let content: String
                if reactionType >= 2000 && reactionType < 3000 {
                    // Tapback reaction — skip these, they clutter the thread
                    continue
                } else {
                    content = self.getMessageTextSync(stmt: stmt)
                }

                let message = Message(
                    messageDate: messageDate,
                    sender: sender,
                    content: content
                )
                messages.append(message)
            }
            
            continuation.resume(returning: messages.reversed()) // Oldest first
        }
    }
    
    private func getSenderSync(stmt: OpaquePointer?, isFromMe: Bool) -> String {
        if isFromMe {
            return "Me"
        }
        if let cString = sqlite3_column_text(stmt, 4) {
            return String(cString: cString)
        }
        return "Unknown"
    }
    
    private func getMessageTextSync(stmt: OpaquePointer?) -> String {
        // Try plain text first (strip object replacement characters used for inline attachments)
        if let text = sqlite3_column_text(stmt, 2) {
            let textString = String(cString: text)
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !textString.isEmpty {
                return textString
            }
        }

        // Try attributed body
        if let attributedData = sqlite3_column_blob(stmt, 3) {
            let dataLength = Int(sqlite3_column_bytes(stmt, 3))
            let data = Data(bytes: attributedData, count: dataLength)
            if let decoded = decodeAttributedBody(data) {
                return decoded
            }
        }

        // Use attachment mime type to give a meaningful label
        if let mimeText = sqlite3_column_text(stmt, 6) {
            let mime = String(cString: mimeText)
            return describeAttachment(mimeType: mime, stmt: stmt)
        }

        return "(Attachment)"
    }

    private func describeAttachment(mimeType: String, stmt: OpaquePointer?) -> String {
        // Use filename as hint when available
        let filename: String?
        if let nameText = sqlite3_column_text(stmt, 7) {
            filename = String(cString: nameText)
        } else {
            filename = nil
        }

        if mimeType.hasPrefix("image/") { return "📷 \(filename ?? "Photo")" }
        if mimeType.hasPrefix("video/") { return "🎥 \(filename ?? "Video")" }
        if mimeType.hasPrefix("audio/") { return "🎤 \(filename ?? "Audio message")" }
        if mimeType == "application/pdf" { return "📄 \(filename ?? "PDF")" }
        if mimeType == "text/vcard" || mimeType == "text/x-vcard" { return "👤 Contact card" }
        if mimeType.contains("sticker") { return "🎨 Sticker" }
        if let name = filename, !name.isEmpty { return "📎 \(name)" }
        return "📎 Attachment"
    }
    
    private func decodeAttributedBody(_ data: Data) -> String? {
        guard data.count > 12 else { return nil }

        // iMessage stores attributedBody using the OLD NSArchiver "streamtyped" format
        // (header: 0x04 0x0b "streamtyped"), NOT NSKeyedArchiver.
        // NSUnarchiver is the correct decoder — NSKeyedUnarchiver always fails on this data.
        let decoded: NSAttributedString?
        if data[0] == 0x04 && data[1] == 0x0b {
            decoded = NSUnarchiver.unarchiveObject(with: data) as? NSAttributedString
        } else {
            // Fallback for any newer format that uses NSKeyedArchiver
            let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver?.requiresSecureCoding = false
            decoded = unarchiver?.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString
        }

        let cleaned = (decoded?.string ?? "")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
    
    // MARK: - Schema Helpers

    private static func columnExists(db: OpaquePointer?, table: String, column: String) -> Bool {
        let pragma = "PRAGMA table_info(\(table))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragma, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            // column 1 of PRAGMA table_info is the column name
            if let cName = sqlite3_column_text(stmt, 1), String(cString: cName) == column {
                return true
            }
        }
        return false
    }

    // MARK: - Date Formatting
    
    private static func formatAppleDate(_ timestamp: Int64) -> String {
        // Apple's Core Data timestamp: seconds since 2001-01-01 00:00:00 UTC
        let appleEpoch = Date(timeIntervalSinceReferenceDate: 0)
        let date = appleEpoch.addingTimeInterval(TimeInterval(timestamp) / 1_000_000_000.0)
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Database Check
    
    func checkDatabaseAccess() async -> Bool {
        let fileManager = FileManager.default
        return fileManager.isReadableFile(atPath: dbPath)
    }
}
