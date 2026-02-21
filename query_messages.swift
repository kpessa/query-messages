#!/usr/bin/env swift

import Foundation
import SQLite3
import AppKit
import Contacts
import Darwin

// MARK: - ANSI Colors & Terminal UI Helpers

enum ANSI {
    static let reset       = "\u{1B}[0m"
    static let bold        = "\u{1B}[1m"
    static let dim         = "\u{1B}[2m"
    static let red         = "\u{1B}[31m"
    static let green       = "\u{1B}[32m"
    static let yellow      = "\u{1B}[33m"
    static let cyan        = "\u{1B}[36m"
    static let magenta     = "\u{1B}[35m"
    static let brightBlue  = "\u{1B}[94m"
    static let brightWhite = "\u{1B}[97m"
    static let darkGray    = "\u{1B}[38;5;240m"

    static func cursorUp(_ n: Int) -> String { "\u{1B}[\(n)A" }
    static func clearLine() -> String { "\u{1B}[2K\r" }

    static func error(_ s: String) -> String        { "\(bold)\(red)\(s)\(reset)" }
    static func success(_ s: String) -> String      { "\(green)\(s)\(reset)" }
    static func header(_ s: String) -> String       { "\(bold)\(cyan)\(s)\(reset)" }
    static func sectionTitle(_ s: String) -> String { "\(bold)\(yellow)\(s)\(reset)" }
    static func dimText(_ s: String) -> String      { "\(dim)\(darkGray)\(s)\(reset)" }

    static func separator(count: Int = 50) -> String {
        "\(darkGray)\(String(repeating: "─", count: count))\(reset)"
    }

    static func geminiBox(_ text: String, width: Int = 48) -> String {
        // Box structure: │  content  │
        // Visible cols:  1 + 2 + content + 2 + 1 = content + 6
        let innerWidth = max(width - 6, 10)
        let borderLine = String(repeating: "─", count: width - 2)
        let top        = "\(magenta)┌\(borderLine)┐\(reset)"
        let bottom     = "\(magenta)└\(borderLine)┘\(reset)"
        var body = ""
        for line in text.components(separatedBy: "\n") {
            var remaining = line.isEmpty ? " " : line
            while !remaining.isEmpty {
                let chunk     = String(remaining.prefix(innerWidth))
                remaining     = remaining.count > innerWidth
                    ? String(remaining.dropFirst(innerWidth)) : ""
                let pad       = String(repeating: " ", count: max(0, innerWidth - chunk.count))
                body += "\(magenta)│\(reset)  \(brightWhite)\(chunk)\(pad)\(reset)  \(magenta)│\(reset)\n"
            }
        }
        return "\(top)\n\(body)\(bottom)"
    }

    static func visibleLength(_ s: String) -> Int { stripANSI(s).count }

    static var terminalWidth: Int {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0 {
            return Int(ws.ws_col)
        }
        return 80
    }
}

func stripANSI(_ s: String) -> String {
    var result = ""
    var i = s.startIndex
    while i < s.endIndex {
        if s[i] == "\u{1B}" {
            var j = s.index(after: i)
            while j < s.endIndex && s[j] != "m" { j = s.index(after: j) }
            if j < s.endIndex { j = s.index(after: j) }
            i = j
        } else {
            result.append(s[i])
            i = s.index(after: i)
        }
    }
    return result
}

// MARK: - Raw Mode & Key Reading

enum KeyPress { case up, down, enter, character(Character), escape, unknown }

func withRawMode<T>(_ body: () -> T) -> T {
    guard isatty(STDIN_FILENO) != 0 else { return body() }
    var old = termios()
    tcgetattr(STDIN_FILENO, &old)
    var raw = old
    raw.c_lflag &= ~(tcflag_t(ICANON) | tcflag_t(ECHO))
    withUnsafeMutableBytes(of: &raw.c_cc) { ptr in
        ptr[Int(VMIN)]  = UInt8(1)
        ptr[Int(VTIME)] = UInt8(0)
    }
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    defer { tcsetattr(STDIN_FILENO, TCSANOW, &old) }
    return body()
}

func readKeyPress() -> KeyPress {
    guard isatty(STDIN_FILENO) != 0 else { return .unknown }
    var buf = [UInt8](repeating: 0, count: 3)
    let n = read(STDIN_FILENO, &buf, 3)
    guard n > 0 else { return .unknown }
    // Arrow key sequences: ESC [ A/B
    if n >= 3, buf[0] == 0x1B, buf[1] == 0x5B {
        switch buf[2] {
        case 0x41: return .up
        case 0x42: return .down
        default: break
        }
    }
    switch buf[0] {
    case 0x03:        return .escape             // Ctrl+C
    case 0x1B:        return .escape             // ESC alone
    case 0x0A, 0x0D: return .enter              // LF / CR
    default:
        return .character(Character(Unicode.Scalar(buf[0])))
    }
}

// MARK: - Interactive Arrow-Key Picker

struct PickerItem {
    let label: String
    let chatIndex: Int   // -1 = non-selectable (header / divider)
}

func runPicker(title: String, items: [PickerItem]) -> Int? {
    guard isatty(STDIN_FILENO) != 0 else { return nil }
    let width    = min(ANSI.terminalWidth, 80)
    var selected = items.firstIndex(where: { $0.chatIndex >= 0 }) ?? 0
    var result: Int? = nil
    var done = false

    // totalRows = title + separator + items + instruction line
    let totalRows = items.count + 3

    func render(initial: Bool) {
        if !initial {
            print(ANSI.cursorUp(totalRows), terminator: "")
        }
        print(ANSI.clearLine() + ANSI.header(title))
        print(ANSI.clearLine() + ANSI.separator(count: width))
        for (i, item) in items.enumerated() {
            let nonSelectable = item.chatIndex == -1
            let highlighted   = (i == selected) && !nonSelectable
            let row: String
            if nonSelectable {
                if item.label.isEmpty {
                    row = ANSI.separator(count: width)
                } else {
                    row = "  " + ANSI.sectionTitle(item.label)
                }
            } else if highlighted {
                let plain  = stripANSI(item.label)
                let prefix = "▶ "
                let pad    = max(0, width - prefix.count - plain.count)
                row = "\u{1B}[46m\u{1B}[30m\u{1B}[1m\(prefix)\(plain)"
                    + String(repeating: " ", count: pad) + "\u{1B}[0m"
            } else {
                row = "  " + item.label
            }
            print(ANSI.clearLine() + row)
        }
        print(ANSI.clearLine() + ANSI.dimText("[↑↓] move   [Enter] select   [q] cancel"))
        fflush(stdout)
    }

    // Hide cursor while picker is active
    print("\u{1B}[?25l", terminator: "")
    fflush(stdout)
    render(initial: true)

    withRawMode {
        while !done {
            switch readKeyPress() {
            case .up:
                var prev = selected - 1
                while prev >= 0 && items[prev].chatIndex == -1 { prev -= 1 }
                if prev >= 0 { selected = prev }
                render(initial: false)
            case .down:
                var next = selected + 1
                while next < items.count && items[next].chatIndex == -1 { next += 1 }
                if next < items.count { selected = next }
                render(initial: false)
            case .enter:
                result = items[selected].chatIndex
                done = true
            case .character(let c) where c == "q" || c == "Q":
                done = true
            case .escape:
                done = true
            default:
                break
            }
        }
    }

    print("\u{1B}[?25h")   // restore cursor (includes trailing newline)
    fflush(stdout)
    return result
}

// MARK: - Number Formatting

func formattedCount(_ n: Int64) -> String {
    let fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    return fmt.string(from: NSNumber(value: n)) ?? "\(n)"
}

// MARK: - Paths & Configuration

let chatDBPath = NSHomeDirectory() + "/Library/Messages/chat.db"
let cacheFilePath = "./contactNameCache.plist"
let geminiAPIKeyPath = "./.gemini_api_key"
let geminiSystemPrompt = """
You are a texting assistant. You help craft text message responses that sound like a real person, not an AI. \
The user is a man who texts in a masculine, concise, and thoughtful way. \
Study how "Me" writes in the conversation history — match that tone, vocabulary, and energy. \
Use an emoji occasionally and naturally, like a real person would — never more than one per message, and only when it genuinely fits. \
Most replies should have no emoji at all. \
Do not use filler phrases, overly enthusiastic language, or anything that sounds like AI-generated text. \
When asked, suggest a response the user ("Me") should send next. \
Only provide the suggested message text — no explanations unless explicitly asked.
"""

// MARK: - Cache I/O

func saveCacheToFile(_ cache: [String: (chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String, lastMessageDateRaw: Int64)]) {
    let cacheArray = cache.map { (key, value) in
        return [
            "key": key,
            "chatID": value.chatID,
            "participants": value.participants,
            "messageCount": value.messageCount,
            "lastMessageDate": value.lastMessageDate,
            "lastMessageDateRaw": value.lastMessageDateRaw
        ] as [String: Any]
    }
    (cacheArray as NSArray).write(toFile: cacheFilePath, atomically: true)
}

func loadCacheFromFile() -> [String: (chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String, lastMessageDateRaw: Int64)] {
    guard let cacheArray = NSArray(contentsOfFile: cacheFilePath) as? [[String: Any]] else {
        return [:]
    }
    var cache: [String: (chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String, lastMessageDateRaw: Int64)] = [:]
    for item in cacheArray {
        if let key = item["key"] as? String,
           let chatID = item["chatID"] as? Int64,
           let participants = item["participants"] as? [String],
           let messageCount = item["messageCount"] as? Int64,
           let lastMessageDate = item["lastMessageDate"] as? String,
           let lastMessageDateRaw = item["lastMessageDateRaw"] as? Int64 {
            cache[key] = (chatID, participants, messageCount, lastMessageDate, lastMessageDateRaw)
        }
    }
    return cache
}

let contactNameCache = NSCache<NSString, NSString>()

// MARK: - External Messages

struct ExternalMessage {
    let date: Date
    let sender: String
    let content: String

    static func parse(from line: String) -> ExternalMessage? {
        let components = line.components(separatedBy: " - ")
        guard components.count >= 2 else { return nil }
        let dateString = components[0]
        let remainingText = components[1]
        let senderContentComponents = remainingText.components(separatedBy: ": ")
        guard senderContentComponents.count >= 2 else { return nil }
        let sender = senderContentComponents[0]
        let content = senderContentComponents[1...].joined(separator: ": ")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = dateFormatter.date(from: dateString) else { return nil }
        return ExternalMessage(date: date, sender: sender, content: content)
    }
}

func loadExternalMessages(from path: String) -> [Message]? {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print(ANSI.error("Could not read external file at path: \(path)"))
        return nil
    }
    let lines = content.components(separatedBy: .newlines)
    var messages: [Message] = []
    for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        if let ext = ExternalMessage.parse(from: line) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            messages.append(Message(messageDate: df.string(from: ext.date),
                                    sender: ext.sender,
                                    content: ext.content))
        }
    }
    return messages
}

// MARK: - SQL Helpers

func executeSQLQuery(dbPath: String, query: String, parameters: [Any] = []) -> [[String: Any]]? {
    var db: OpaquePointer?
    var stmt: OpaquePointer?
    var results: [[String: Any]] = []
    defer {
        sqlite3_finalize(stmt)
        sqlite3_close(db)
    }
    if sqlite3_open(dbPath, &db) != SQLITE_OK {
        print(ANSI.error("Unable to open database at path: \(dbPath)"))
        return nil
    }
    if sqlite3_prepare_v2(db, query, -1, &stmt, nil) != SQLITE_OK {
        let errmsg = String(cString: sqlite3_errmsg(db)!)
        print(ANSI.error("Error preparing statement: \(errmsg)"))
        return nil
    }
    for (index, param) in parameters.enumerated() {
        let idx = Int32(index + 1)
        if let v = param as? Int64 { sqlite3_bind_int64(stmt, idx, v) }
        else if let v = param as? Int { sqlite3_bind_int(stmt, idx, Int32(v)) }
        else if let v = param as? String { sqlite3_bind_text(stmt, idx, v, -1, nil) }
    }
    while sqlite3_step(stmt) == SQLITE_ROW {
        var row: [String: Any] = [:]
        let columnCount = sqlite3_column_count(stmt)
        for i in 0..<columnCount {
            let name = String(cString: sqlite3_column_name(stmt, i))
            let type = sqlite3_column_type(stmt, i)
            var value: Any
            switch type {
            case SQLITE_INTEGER: value = sqlite3_column_int64(stmt, i)
            case SQLITE_FLOAT:   value = sqlite3_column_double(stmt, i)
            case SQLITE_TEXT:    value = String(cString: sqlite3_column_text(stmt, i))
            case SQLITE_BLOB:
                let data = sqlite3_column_blob(stmt, i)
                let size = sqlite3_column_bytes(stmt, i)
                value = Data(bytes: data!, count: Int(size))
            default:             value = NSNull()
            }
            row[name] = value
        }
        results.append(row)
    }
    return results
}

// MARK: - Contact Lookup

let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    return f
}()

func getContactName(phoneNumber: String) -> String? {
    if let cached = contactNameCache.object(forKey: phoneNumber as NSString) {
        return cached as String
    }
    let semaphore = DispatchSemaphore(value: 0)
    var contactName: String?
    let store = CNContactStore()
    store.requestAccess(for: .contacts) { granted, _ in
        if granted {
            let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey,
                               CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let digits = phoneNumber.filter("0123456789".contains)
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: digits))
            do {
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                if let c = contacts.first {
                    contactName = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
                    if let name = contactName {
                        contactNameCache.setObject(name as NSString, forKey: phoneNumber as NSString)
                    }
                }
            } catch {
                print(ANSI.error("Error fetching contacts"))
            }
        } else {
            print(ANSI.error("Access to contacts was denied."))
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 2)
    if contactName == nil {
        contactNameCache.setObject(phoneNumber as NSString, forKey: phoneNumber as NSString)
    }
    return contactName
}

// MARK: - Data Models

struct Message {
    let messageDate: String
    let sender: String
    let content: String
}

struct GeminiMessage {
    let role: String
    let text: String
    func toDict() -> [String: Any] { ["role": role, "parts": [["text": text]]] }
}

class GeminiConversation {
    private var history: [GeminiMessage] = []
    func addUserMessage(_ text: String)  { history.append(GeminiMessage(role: "user",  text: text)) }
    func addModelMessage(_ text: String) { history.append(GeminiMessage(role: "model", text: text)) }
    func toContentsArray() -> [[String: Any]] { history.map { $0.toDict() } }
}

// MARK: - Gemini API

func loadGeminiAPIKey() -> String? {
    if let key = try? String(contentsOfFile: geminiAPIKeyPath, encoding: .utf8) {
        let t = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
    }
    return ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
}

func callGeminiAPI(conversation: GeminiConversation) -> String? {
    guard let apiKey = loadGeminiAPIKey() else {
        print(ANSI.error("Error: No Gemini API key found. Add it to .gemini_api_key or set GEMINI_API_KEY."))
        return nil
    }
    let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else {
        print(ANSI.error("Error: Invalid Gemini API URL."))
        return nil
    }
    let requestBody: [String: Any] = [
        "system_instruction": ["parts": [["text": geminiSystemPrompt]]],
        "contents": conversation.toContentsArray()
    ]
    guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
        print(ANSI.error("Error: Failed to serialize Gemini request."))
        return nil
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    request.timeoutInterval = 30

    let semaphore = DispatchSemaphore(value: 0)
    var responseText: String?
    var apiError: String?

    URLSession.shared.dataTask(with: request) { data, _, error in
        defer { semaphore.signal() }
        if let error = error { apiError = "Network error: \(error.localizedDescription)"; return }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            apiError = "Failed to parse Gemini response."; return
        }
        if let errObj = json["error"] as? [String: Any], let msg = errObj["message"] as? String {
            apiError = "Gemini API error: \(msg)"; return
        }
        if let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            responseText = text
        } else {
            apiError = "Unexpected Gemini response format."
        }
    }.resume()

    _ = semaphore.wait(timeout: .now() + 35)
    if let e = apiError { print(ANSI.error(e)); return nil }
    return responseText
}

// MARK: - Gemini Session

func startGeminiSession(messages: [Message],
                        chat: (chatID: Int64, participants: [String], messageCount: Int64,
                               lastMessageDate: String, lastMessageDateRaw: Int64)) {
    let conversation = GeminiConversation()
    let pasteboard = NSPasteboard.general
    let contextLimit = 50
    let contextMessages = messages.count > contextLimit ? Array(messages.suffix(contextLimit)) : messages
    let contextNote = messages.count > contextLimit ? " (most recent \(contextLimit) of \(messages.count))" : ""
    var lastKnownMessageDate = messages.last?.messageDate ?? ""

    func printGeminiResponse(_ response: String) {
        let boxWidth = min(ANSI.terminalWidth - 4, 76)
        print("\n" + ANSI.geminiBox(response, width: boxWidth))
        pasteboard.clearContents()
        pasteboard.setString(response, forType: .string)
        print(ANSI.success("✓ Copied to clipboard"))
    }

    func askReactionAndQuery(historyText: String, isRefresh: Bool) -> Bool {
        let label = isRefresh
            ? "Your reaction to the new messages? (press Enter to skip): "
            : "What's your reaction or thought to emphasize? (press Enter to skip): "
        print("\n" + ANSI.bold + ANSI.brightWhite + label + ANSI.reset, terminator: "")
        let userContext = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var prompt = isRefresh
            ? "New messages received:\n\n\(historyText)\n\n"
            : "Here is my recent iMessage conversation\(contextNote):\n\n\(historyText)\n\n"
        if !userContext.isEmpty { prompt += "My reaction/thought: \(userContext)\n\n" }
        prompt += "Suggest a response I (\"Me\") should send next."
        conversation.addUserMessage(prompt)

        print("\n" + ANSI.separator())
        print(ANSI.cyan + "  Asking Gemini..." + ANSI.reset)
        print(ANSI.separator())

        guard let response = callGeminiAPI(conversation: conversation) else {
            print(ANSI.error("Failed to get a suggestion from Gemini."))
            return false
        }
        conversation.addModelMessage(response)
        printGeminiResponse(response)
        return true
    }

    let initialHistory = contextMessages
        .map { "\($0.messageDate) - \($0.sender): \($0.content)" }
        .joined(separator: "\n")
    _ = askReactionAndQuery(historyText: initialHistory, isRefresh: false)

    while true {
        print("\n" + ANSI.bold + ANSI.brightWhite + "Follow-up" + ANSI.reset
              + "  " + ANSI.dimText("shorter · more casual · refresh · quit"))
        print(ANSI.bold + ANSI.brightWhite + "> " + ANSI.reset, terminator: "")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else { continue }
        if ["quit", "q", "exit"].contains(input.lowercased()) { break }

        if input.lowercased() == "refresh" {
            print(ANSI.dimText("Re-fetching messages from chat.db..."))
            guard let freshMessages = fetchMessagesForChat(chatID: chat.chatID,
                                                           participants: chat.participants,
                                                           limit: nil,
                                                           additionalMessages: nil) else {
                print(ANSI.error("Failed to re-fetch messages."))
                continue
            }
            let sorted = freshMessages.sorted { $0.messageDate < $1.messageDate }
            let newMessages = sorted.filter { $0.messageDate > lastKnownMessageDate }

            if newMessages.isEmpty {
                print(ANSI.dimText("No new messages since last check."))
                continue
            }

            print("\n" + ANSI.success("\(newMessages.count)") + " new message(s):")
            for msg in newMessages {
                let truncated = msg.content.split(separator: "\n").first ?? Substring(msg.content)
                let senderStr = msg.sender == "Me"
                    ? ANSI.bold + ANSI.brightWhite + msg.sender + ANSI.reset
                    : ANSI.bold + ANSI.brightBlue  + msg.sender + ANSI.reset
                print("  " + ANSI.dimText(msg.messageDate) + " - " + senderStr + ": \(truncated)")
            }
            lastKnownMessageDate = sorted.last?.messageDate ?? lastKnownMessageDate

            let deltaHistory = newMessages
                .map { "\($0.messageDate) - \($0.sender): \($0.content)" }
                .joined(separator: "\n")
            _ = askReactionAndQuery(historyText: deltaHistory, isRefresh: true)
            continue
        }

        conversation.addUserMessage(input)
        print(ANSI.cyan + "  Asking Gemini..." + ANSI.reset)

        guard let response = callGeminiAPI(conversation: conversation) else {
            print(ANSI.error("Failed to get a response. Try again."))
            continue
        }
        conversation.addModelMessage(response)
        printGeminiResponse(response)
    }
}

// MARK: - Message Decoding

func decodeAttributedBody(data: Data) -> String? {
    if #available(macOS 10.13, *) {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            if let s = try unarchiver.decodeTopLevelObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString {
                return s.string
            }
        } catch {}
    }
    return String(data: data, encoding: .utf8)
}

// MARK: - Chat Queries

func getAvailableChatsGroupedByContact() -> [String: [(chatID: Int64, contactID: String, messageCount: Int64, lastMessageDate: String)]] {
    let query = """
    SELECT
        c.ROWID AS chat_id,
        h.id AS handle_id,
        (SELECT COUNT(*) FROM chat_message_join cmj2 WHERE cmj2.chat_id = c.ROWID) AS message_count,
        (SELECT MAX(m2.date) FROM chat_message_join cmj2 JOIN message m2 ON cmj2.message_id = m2.ROWID WHERE cmj2.chat_id = c.ROWID) AS last_message_date
    FROM chat c
    JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
    JOIN handle h ON chj.handle_id = h.ROWID
    WHERE EXISTS (SELECT 1 FROM chat_message_join cmj WHERE cmj.chat_id = c.ROWID)
    GROUP BY c.ROWID, h.id
    ORDER BY last_message_date DESC
    """
    let startTime = CFAbsoluteTimeGetCurrent()
    guard let results = executeSQLQuery(dbPath: chatDBPath, query: query) else { return [:] }
    let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
    print(ANSI.dimText("Query execution time: \(String(format: "%.2f", timeElapsed)) seconds"))

    var grouped: [String: [(chatID: Int64, contactID: String, messageCount: Int64, lastMessageDate: String)]] = [:]
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "com.chat.processing", attributes: .concurrent)
    let syncQueue = DispatchQueue(label: "com.chat.sync")

    for row in results {
        group.enter()
        queue.async {
            if let chat_id = row["chat_id"] as? Int64,
               let handle_id = row["handle_id"] as? String,
               let message_count = row["message_count"] as? Int64,
               let last_message_date = row["last_message_date"] as? Int64 {
                let contactName = getContactName(phoneNumber: handle_id) ?? handle_id
                let dateInSeconds = Double(last_message_date) / 1_000_000_000 + 978_307_200
                let formatted = dateFormatter.string(from: Date(timeIntervalSince1970: dateInSeconds))
                syncQueue.async {
                    grouped[contactName, default: []].append((chat_id, handle_id, message_count, formatted))
                }
            }
            group.leave()
        }
    }
    group.wait()
    return grouped
}

func getAvailableChats() -> [(chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String, lastMessageDateRaw: Int64)] {
    let query = """
    SELECT
        c.ROWID AS chat_id,
        c.display_name,
        (SELECT COUNT(*) FROM chat_message_join cmj2 WHERE cmj2.chat_id = c.ROWID) AS message_count,
        (SELECT MAX(m2.date) FROM chat_message_join cmj2 JOIN message m2 ON cmj2.message_id = m2.ROWID WHERE cmj2.chat_id = c.ROWID) AS last_message_date
    FROM chat c
    WHERE EXISTS (SELECT 1 FROM chat_message_join cmj WHERE cmj.chat_id = c.ROWID)
    """
    guard let results = executeSQLQuery(dbPath: chatDBPath, query: query) else { return [] }
    var availableChats: [(chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String, lastMessageDateRaw: Int64)] = []
    for row in results {
        if let chat_id = row["chat_id"] as? Int64,
           let message_count = row["message_count"] as? Int64,
           let last_message_date = row["last_message_date"] as? Int64 {
            let participants = getParticipantsForChat(chatID: chat_id)
            let dateInSeconds = Double(last_message_date) / 1_000_000_000 + 978_307_200
            let formatted = dateFormatter.string(from: Date(timeIntervalSince1970: dateInSeconds))
            availableChats.append((chat_id, participants, message_count, formatted, last_message_date))
        }
    }
    return availableChats
}

func getParticipantsForChat(chatID: Int64) -> [String] {
    let query = """
    SELECT h.id AS handle_id
    FROM chat_handle_join chj
    JOIN handle h ON chj.handle_id = h.ROWID
    WHERE chj.chat_id = ?
    """
    guard let results = executeSQLQuery(dbPath: chatDBPath, query: query, parameters: [chatID]) else { return [] }
    return results.compactMap { row in
        guard let handle_id = row["handle_id"] as? String else { return nil }
        return getContactName(phoneNumber: handle_id) ?? handle_id
    }
}

func fetchMessagesForChat(chatID: Int64, participants: [String], limit: Int?, additionalMessages: [Message]?) -> [Message]? {
    var query = """
    SELECT
        m.ROWID AS message_id,
        m.date,
        datetime(m.date / 1000000000 + 978307200, 'unixepoch', 'localtime') AS message_date,
        m.is_from_me,
        h.id AS handle_id,
        m.text,
        m.attributedBody
    FROM message m
    LEFT JOIN handle h ON m.handle_id = h.ROWID
    JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
    WHERE cmj.chat_id = ?
    ORDER BY m.date DESC
    """
    if let lim = limit { query += " LIMIT \(lim)" }
    guard let messageRows = executeSQLQuery(dbPath: chatDBPath, query: query, parameters: [chatID]) else {
        print(ANSI.error("No messages found."))
        return nil
    }
    var messages: [Message] = []
    for msg in messageRows {
        if let isFromMe = msg["is_from_me"] as? Int64,
           let messageDate = msg["message_date"] as? String {
            var content: String?
            if let data = msg["attributedBody"] as? Data { content = decodeAttributedBody(data: data) }
            else if let text = msg["text"] as? String { content = text }
            if let c = content {
                let sender: String
                if isFromMe == 1 { sender = "Me" }
                else if let handle_id = msg["handle_id"] as? String {
                    sender = getContactName(phoneNumber: handle_id) ?? handle_id
                } else { sender = "Unknown" }
                messages.append(Message(messageDate: messageDate, sender: sender, content: c))
            }
        }
    }
    if let extra = additionalMessages { messages.insert(contentsOf: extra, at: 0) }
    return messages
}

// MARK: - queryMessages (kept for completeness; main uses fetchAndDisplayMessages)

func parseReactionType(text: String?) -> String? {
    guard let text = text else { return nil }
    let reactions: [String: String] = [
        "Loved ": "Loved", "Liked ": "Liked", "Emphasized ": "Emphasized",
        "Laughed at ": "Laughed at", "Disliked ": "Disliked", "Questioned ": "Questioned"
    ]
    for (pattern, reaction) in reactions { if text.hasPrefix(pattern) { return reaction } }
    return "[reaction]"
}

func queryMessages(chatID: Int64, contactID: String, limit: Int?, additionalMessages: [Message]?) {
    let contactName = getContactName(phoneNumber: contactID) ?? contactID
    var baseQuery = """
    SELECT
        m.ROWID AS message_id,
        m.date,
        datetime(m.date / 1000000000 + 978307200, 'unixepoch', 'localtime') AS message_date,
        CASE m.is_from_me WHEN 1 THEN 'Me' ELSE ? END AS sender,
        m.text,
        m.attributedBody,
        m.is_from_me
    FROM message m
    JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
    WHERE cmj.chat_id = ?
    ORDER BY m.date ASC
    """
    if let lim = limit { baseQuery += " LIMIT \(lim)" }

    let startTime = CFAbsoluteTimeGetCurrent()
    guard let messageRows = executeSQLQuery(dbPath: chatDBPath, query: baseQuery, parameters: [contactName, chatID]) else {
        print(ANSI.error("No messages found."))
        return
    }
    let queryTime = CFAbsoluteTimeGetCurrent() - startTime
    print(ANSI.dimText("Message query execution time: \(String(format: "%.2f", queryTime)) seconds"))

    let processStart = CFAbsoluteTimeGetCurrent()
    var messages: [Message] = []
    let dg = DispatchGroup()
    let queue = DispatchQueue(label: "com.messages.processing", attributes: .concurrent)
    let syncQ = DispatchQueue(label: "com.messages.sync")

    for msg in messageRows {
        dg.enter()
        queue.async {
            if let isFromMe = msg["is_from_me"] as? Int64,
               let messageDate = msg["message_date"] as? String {
                var content: String?
                if let data = msg["attributedBody"] as? Data { content = decodeAttributedBody(data: data) }
                else if let text = msg["text"] as? String { content = text }
                if let c = content {
                    let sender = isFromMe == 1 ? "Me" : contactName
                    let m = Message(messageDate: messageDate, sender: sender, content: c)
                    syncQ.async { messages.append(m) }
                }
            }
            dg.leave()
        }
    }
    dg.wait()
    if let extra = additionalMessages { messages.insert(contentsOf: extra, at: 0) }

    let processTime = CFAbsoluteTimeGetCurrent() - processStart
    print(ANSI.dimText("Message processing time: \(String(format: "%.2f", processTime)) seconds"))
    print(ANSI.dimText("Total execution time: \(String(format: "%.2f", queryTime + processTime)) seconds"))

    print("\n" + ANSI.header("Messages with \(contactName):"))
    print(ANSI.separator())
    var formattedOutput = ""
    for message in messages.sorted(by: { $0.messageDate < $1.messageDate }) {
        let truncated = message.content.split(separator: "\n").first.map(String.init) ?? message.content
        let dateStr   = ANSI.dimText(message.messageDate)
        let senderStr = message.sender == "Me"
            ? ANSI.bold + ANSI.brightWhite + "Me" + ANSI.reset
            : ANSI.bold + ANSI.brightBlue  + message.sender + ANSI.reset
        print(dateStr + "  " + senderStr + ": " + truncated)
        formattedOutput += "\(message.messageDate) - \(message.sender): \(message.content)\n"
    }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(formattedOutput, forType: .string)
    print("\n" + ANSI.success("✓ Messages copied to clipboard"))
}

// MARK: - Fetch & Display

func fetchAndDisplayMessages(for chat: (chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String, lastMessageDateRaw: Int64),
                             externalMessages: [Message]?) {
    print(ANSI.dimText("Fetching messages for chat ID: \(chat.chatID)"))

    guard let messages = fetchMessagesForChat(chatID: chat.chatID,
                                              participants: chat.participants,
                                              limit: nil,
                                              additionalMessages: externalMessages) else {
        print(ANSI.error("No messages found for the selected chat."))
        return
    }

    print(ANSI.dimText("Messages fetched successfully."))

    let sortedMessages = messages.sorted { $0.messageDate < $1.messageDate }
    let recentMessages = Array(sortedMessages.suffix(16))

    print("\n" + ANSI.header("Messages:"))
    print(ANSI.separator())

    func printMsg(_ message: Message) {
        let truncated = message.content.split(separator: "\n").first.map(String.init) ?? message.content
        let dateStr   = ANSI.dimText(message.messageDate)
        let senderStr = message.sender == "Me"
            ? ANSI.bold + ANSI.brightWhite + "Me" + ANSI.reset
            : ANSI.bold + ANSI.brightBlue  + message.sender + ANSI.reset
        print(dateStr + "  " + senderStr + ": " + truncated)
    }

    let displayMessages: [Message]
    if recentMessages.count > 10 {
        let firstFive = Array(recentMessages.prefix(5))
        let lastFive  = Array(recentMessages.suffix(5))
        displayMessages = firstFive + lastFive
        let missing = recentMessages.count - displayMessages.count

        for msg in firstFive { printMsg(msg) }
        if missing > 0 {
            print("\n" + ANSI.dimText("... \(missing) messages not shown ...") + "\n")
        }
        for msg in lastFive { printMsg(msg) }
    } else {
        displayMessages = recentMessages
        for msg in displayMessages { printMsg(msg) }
    }

    print(ANSI.separator())

    // Copy all messages to clipboard
    let formattedOutput = sortedMessages
        .map { "\($0.messageDate) - \($0.sender): \($0.content)\n" }
        .joined()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(formattedOutput, forType: .string)
    print("\n" + ANSI.success("✓ Messages copied to clipboard"))

    // AI prompt — single keypress
    print("\n" + ANSI.bold + ANSI.brightWhite + "AI response suggestions?" + ANSI.reset
          + "  " + ANSI.dimText("[Y] Yes  [N] No"), terminator: "  ")
    fflush(stdout)

    let useAI: Bool = withRawMode {
        let key = readKeyPress()
        switch key {
        case .character(let c) where c == "n" || c == "N":
            print("n")
            return false
        case .escape:
            print("n")
            return false
        default:
            print("y")
            return true
        }
    }

    if useAI {
        startGeminiSession(messages: sortedMessages, chat: chat)
    }
}

// MARK: - Main

func main() {
    let bannerWidth = min(ANSI.terminalWidth, 60)
    print("\n" + ANSI.bold + ANSI.cyan + String(repeating: "═", count: bannerWidth) + ANSI.reset)
    print(ANSI.bold + ANSI.cyan + "  iMessage Query Tool" + ANSI.reset)
    print(ANSI.bold + ANSI.cyan + String(repeating: "═", count: bannerWidth) + ANSI.reset + "\n")

    let args = CommandLine.arguments
    var searchContact: String? = nil
    var externalFilePath: String? = nil

    var i = 1
    var positional: [String] = []
    while i < args.count {
        switch args[i] {
        case "-f", "--file":
            if i + 1 < args.count { externalFilePath = args[i + 1]; i += 2 }
            else { print(ANSI.error("Error: Missing file path after -f/--file")); return }
        default:
            positional.append(args[i]); i += 1
        }
    }
    if positional.count >= 1 { searchContact = positional[0] }
    if positional.count >= 2 && externalFilePath == nil { externalFilePath = positional[1] }

    print(ANSI.dimText("Parsed arguments. Search contact: \(searchContact ?? "None"), External file path: \(externalFilePath ?? "None")"))

    var externalMessages: [Message]? = nil
    if let filePath = externalFilePath {
        let t = CFAbsoluteTimeGetCurrent()
        externalMessages = loadExternalMessages(from: filePath)
        if externalMessages == nil { print(ANSI.yellow + "Warning: Failed to load external messages" + ANSI.reset) }
        print(ANSI.dimText("External messages loaded in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t)) seconds"))
    }

    let cacheT = CFAbsoluteTimeGetCurrent()
    var contactNameCache = loadCacheFromFile()
    print(ANSI.dimText("Contact name cache loaded in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - cacheT)) seconds"))

    if let search = searchContact?.lowercased(), let cachedChat = contactNameCache[search] {
        print(ANSI.dimText("One-to-one match found in cache for contact: \(cachedChat.participants.joined(separator: ", "))"))
        fetchAndDisplayMessages(for: cachedChat, externalMessages: externalMessages)
        return
    }

    let chatsT = CFAbsoluteTimeGetCurrent()
    let availableChats = getAvailableChats()
    print(ANSI.dimText("Available chats retrieved in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - chatsT)) seconds"))

    if availableChats.isEmpty {
        print(ANSI.error("No chats found or unable to access the database."))
        return
    }

    let filterT = CFAbsoluteTimeGetCurrent()
    var filteredChats = availableChats
    if let search = searchContact?.lowercased() {
        filteredChats = availableChats.filter { chat in
            let match = chat.participants.contains(where: { $0.lowercased().contains(search) })
            if match { contactNameCache[chat.participants.joined(separator: ", ").lowercased()] = chat }
            return match
        }
    }
    print(ANSI.dimText("Chats filtered in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - filterT)) seconds"))
    saveCacheToFile(contactNameCache)

    if filteredChats.isEmpty {
        if let msgs = externalMessages, !msgs.isEmpty {
            // No iMessage history, but we have an external file — use it as the full context
            print(ANSI.dimText("No iMessage chat found. Using external messages as conversation context."))
            let contactLabel = searchContact ?? "Contact"
            let dummyChat = (chatID: Int64(0),
                             participants: [contactLabel],
                             messageCount: Int64(msgs.count),
                             lastMessageDate: "",
                             lastMessageDateRaw: Int64(0))
            fetchAndDisplayMessages(for: dummyChat, externalMessages: externalMessages)
            return
        }
        print(ANSI.error("No chats found for the specified contact."))
        return
    }

    if filteredChats.count == 1, let single = filteredChats.first {
        print(ANSI.dimText("One-to-one match found for contact: \(single.participants.joined(separator: ", "))"))
        fetchAndDisplayMessages(for: single, externalMessages: externalMessages)
        return
    }

    // Build two-section picker
    let recentChats = Array(filteredChats.sorted { $0.lastMessageDateRaw > $1.lastMessageDateRaw }.prefix(10))
    let recentIDs   = Set(recentChats.map { $0.chatID })
    let activeChats = Array(filteredChats
        .filter { !recentIDs.contains($0.chatID) }
        .sorted { $0.messageCount > $1.messageCount }
        .prefix(10))

    // Flat array used for index lookup
    let displayChats = recentChats + activeChats

    func chatLabel(_ chat: (chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String, lastMessageDateRaw: Int64)) -> String {
        let name = chat.participants.joined(separator: ", ")
        let meta = "\(formattedCount(chat.messageCount)) msgs · \(chat.lastMessageDate)"
        return ANSI.bold + ANSI.brightWhite + name + ANSI.reset + "  " + ANSI.dimText(meta)
    }

    var pickerItems: [PickerItem] = []
    pickerItems.append(PickerItem(label: "Most Recent", chatIndex: -1))
    for (idx, chat) in recentChats.enumerated() {
        pickerItems.append(PickerItem(label: chatLabel(chat), chatIndex: idx))
    }
    pickerItems.append(PickerItem(label: "", chatIndex: -1))  // divider
    pickerItems.append(PickerItem(label: "Most Active", chatIndex: -1))
    for (idx, chat) in activeChats.enumerated() {
        pickerItems.append(PickerItem(label: chatLabel(chat), chatIndex: recentChats.count + idx))
    }

    guard let choice = runPicker(title: "Select a Chat", items: pickerItems) else {
        print(ANSI.dimText("Selection cancelled."))
        return
    }

    fetchAndDisplayMessages(for: displayChats[choice], externalMessages: externalMessages)
}

// MARK: - Entry Point

main()

print("\n" + ANSI.dimText(String(repeating: "─", count: 40)))
print(ANSI.dimText("End of Script"))
print(ANSI.dimText(String(repeating: "─", count: 40)) + "\n")
