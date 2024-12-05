#!/usr/bin/env swift

import Foundation
import SQLite3
import AppKit
import Contacts

// Paths to databases
let chatDBPath = NSHomeDirectory() + "/Library/Messages/chat.db"

// Add this at the top of the file with other global variables
let contactNameCache = NSCache<NSString, NSString>()

// Helper function to execute a SQL query
func executeSQLQuery(dbPath: String, query: String, parameters: [Any] = []) -> [[String: Any]]? {
    var db: OpaquePointer?
    var stmt: OpaquePointer?
    var results: [[String: Any]] = []

    defer {
        sqlite3_finalize(stmt)
        sqlite3_close(db)
    }

    if sqlite3_open(dbPath, &db) != SQLITE_OK {
        print("Unable to open database at path: \(dbPath)")
        return nil
    }

    if sqlite3_prepare_v2(db, query, -1, &stmt, nil) != SQLITE_OK {
        let errmsg = String(cString: sqlite3_errmsg(db)!)
        print("Error preparing statement: \(errmsg)")
        return nil
    }

    // Bind parameters
    for (index, param) in parameters.enumerated() {
        let idx = Int32(index + 1)
        if let intParam = param as? Int64 {
            sqlite3_bind_int64(stmt, idx, intParam)
        } else if let intParam = param as? Int {
            sqlite3_bind_int(stmt, idx, Int32(intParam))
        } else if let stringParam = param as? String {
            sqlite3_bind_text(stmt, idx, stringParam, -1, nil)
        }
    }

    while sqlite3_step(stmt) == SQLITE_ROW {
        var row: [String: Any] = [:]
        let columnCount = sqlite3_column_count(stmt)
        for i in 0..<columnCount {
            let columnName = String(cString: sqlite3_column_name(stmt, i))
            let columnType = sqlite3_column_type(stmt, i)
            var value: Any
            switch columnType {
            case SQLITE_INTEGER:
                value = sqlite3_column_int64(stmt, i)
            case SQLITE_FLOAT:
                value = sqlite3_column_double(stmt, i)
            case SQLITE_TEXT:
                value = String(cString: sqlite3_column_text(stmt, i))
            case SQLITE_BLOB:
                let data = sqlite3_column_blob(stmt, i)
                let size = sqlite3_column_bytes(stmt, i)
                value = Data(bytes: data!, count: Int(size))
            case SQLITE_NULL:
                value = NSNull()
            default:
                value = NSNull()
            }
            row[columnName] = value
        }
        results.append(row)
    }

    return results
}

func getAvailableChatsGroupedByContact() -> [String: [(chatID: Int64, contactID: String, messageCount: Int64, lastMessageDate: String)]] {
    let query = """
    SELECT
        c.ROWID AS chat_id,
        h.id AS handle_id,
        (SELECT COUNT(*) 
         FROM chat_message_join cmj2 
         WHERE cmj2.chat_id = c.ROWID) AS message_count,
        (SELECT MAX(m2.date) 
         FROM chat_message_join cmj2 
         JOIN message m2 ON cmj2.message_id = m2.ROWID 
         WHERE cmj2.chat_id = c.ROWID) AS last_message_date
    FROM chat c
    JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
    JOIN handle h ON chj.handle_id = h.ROWID
    WHERE EXISTS (
        SELECT 1 
        FROM chat_message_join cmj 
        WHERE cmj.chat_id = c.ROWID
    )
    GROUP BY c.ROWID, h.id
    ORDER BY last_message_date DESC
    """

    // Add query execution time logging
    let startTime = CFAbsoluteTimeGetCurrent()
    guard let results = executeSQLQuery(dbPath: chatDBPath, query: query) else {
        return [:]
    }
    let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
    print("Query execution time: \(String(format: "%.2f", timeElapsed)) seconds")

    var chatsGroupedByContact: [String: [(chatID: Int64, contactID: String, messageCount: Int64, lastMessageDate: String)]] = [:]
    
    // Process results using a dispatch group for parallel processing
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
                let dateInSeconds = Double(last_message_date) / 1000000000 + 978307200
                let date = Date(timeIntervalSince1970: dateInSeconds)
                let formattedDate = dateFormatter.string(from: date)

                syncQueue.async {
                    if chatsGroupedByContact[contactName] == nil {
                        chatsGroupedByContact[contactName] = []
                    }
                    chatsGroupedByContact[contactName]?.append((chat_id, handle_id, message_count, formattedDate))
                }
            }
            group.leave()
        }
    }
    
    // Wait for all processing to complete
    group.wait()

    return chatsGroupedByContact
}

// Add this helper function to improve date formatting performance
let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

// Updated getContactName function with caching
func getContactName(phoneNumber: String) -> String? {
    // Check cache first
    if let cachedName = contactNameCache.object(forKey: phoneNumber as NSString) {
        return cachedName as String
    }
    
    let semaphore = DispatchSemaphore(value: 0)
    var contactName: String?

    let store = CNContactStore()
    
    // Only request access if we haven't cached the result
    store.requestAccess(for: .contacts) { granted, error in
        if granted {
            let keysToFetch = [
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactPhoneNumbersKey
            ] as [CNKeyDescriptor]
            
            // Create a predicate to search for phone numbers
            let phoneNumberDigits = phoneNumber.filter("0123456789".contains)
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phoneNumberDigits))
            
            do {
                // Use find instead of enumerate for better performance
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                if let contact = contacts.first {
                    contactName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                    // Cache the result
                    if let name = contactName {
                        contactNameCache.setObject(name as NSString, forKey: phoneNumber as NSString)
                    }
                }
            } catch {
                print("Error fetching contacts")
            }
        } else {
            print("Access to contacts was denied.")
        }
        semaphore.signal()
    }

    _ = semaphore.wait(timeout: .now() + 2) // Reduced timeout to 2 seconds
    
    // Cache nil results as well to avoid repeated lookups
    if contactName == nil {
        contactNameCache.setObject(phoneNumber as NSString, forKey: phoneNumber as NSString)
    }
    
    return contactName
}

// Define a Message struct to hold the message data
struct Message {
    let messageDate: String
    let sender: String
    let content: String
}

// Function to decode attributed body
func decodeAttributedBody(data: Data) -> String? {
    // Try to unarchive using NSKeyedUnarchiver
    if #available(macOS 10.13, *) {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            if let attributedString = try unarchiver.decodeTopLevelObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString {
                return attributedString.string
            }
        } catch {
            // Handle error
            print("Failed to decode attributed body: \(error)")
        }
    }

    // Fallback to NSUnarchiver for non-keyed archives
    if let attributedString = deprecated_unarchiver(data: data) {
        return attributedString.string
    }

    // Fallback to plain text decoding
    if let plainText = String(data: data, encoding: .utf8) {
        return plainText
    }

    return nil
}

// Suppress deprecation warning for NSUnarchiver
@available(macOS, deprecated: 10.13)
func deprecated_unarchiver(data: Data) -> NSAttributedString? {
    if let attributedString = NSUnarchiver.unarchiveObject(with: data) as? NSAttributedString {
        return attributedString
    }
    return nil
}

// Function to get available chats with participants
func getAvailableChats() -> [(chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String)] {
    let query = """
    SELECT
        c.ROWID AS chat_id,
        c.display_name,
        (SELECT COUNT(*) 
         FROM chat_message_join cmj2 
         WHERE cmj2.chat_id = c.ROWID) AS message_count,
        (SELECT MAX(m2.date) 
         FROM chat_message_join cmj2 
         JOIN message m2 ON cmj2.message_id = m2.ROWID 
         WHERE cmj2.chat_id = c.ROWID) AS last_message_date
    FROM chat c
    WHERE EXISTS (
        SELECT 1 
        FROM chat_message_join cmj 
        WHERE cmj.chat_id = c.ROWID
    )
    ORDER BY last_message_date DESC
    """

    // Execute the query
    guard let results = executeSQLQuery(dbPath: chatDBPath, query: query) else {
        return []
    }

    var availableChats: [(chatID: Int64, participants: [String], messageCount: Int64, lastMessageDate: String)] = []

    for row in results {
        if let chat_id = row["chat_id"] as? Int64,
           let message_count = row["message_count"] as? Int64,
           let last_message_date = row["last_message_date"] as? Int64 {

            // Get participants for this chat
            let participants = getParticipantsForChat(chatID: chat_id)

            let dateInSeconds = Double(last_message_date) / 1000000000 + 978307200
            let date = Date(timeIntervalSince1970: dateInSeconds)
            let formattedDate = dateFormatter.string(from: date)

            availableChats.append((
                chatID: chat_id,
                participants: participants,
                messageCount: message_count,
                lastMessageDate: formattedDate
            ))
        }
    }

    return availableChats
}

// Function to get participants for a specific chat
func getParticipantsForChat(chatID: Int64) -> [String] {
    let query = """
    SELECT
        h.id AS handle_id
    FROM chat_handle_join chj
    JOIN handle h ON chj.handle_id = h.ROWID
    WHERE chj.chat_id = ?
    """

    guard let results = executeSQLQuery(dbPath: chatDBPath, query: query, parameters: [chatID]) else {
        return []
    }

    var participants: [String] = []

    for row in results {
        if let handle_id = row["handle_id"] as? String {
            let contactName = getContactName(phoneNumber: handle_id) ?? handle_id
            participants.append(contactName)
        }
    }

    return participants
}

// Updated fetchMessagesForChat function
func fetchMessagesForChat(chatID: Int64, participants: [String], limit: Int?) -> [Message]? {
    let query = """
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
    ORDER BY m.date ASC
    """

    var finalQuery = query
    if let messageLimit = limit {
        finalQuery += " LIMIT \(messageLimit)"
    }

    guard let messageRows = executeSQLQuery(dbPath: chatDBPath, query: finalQuery, parameters: [chatID]) else {
        print("No messages found.")
        return nil
    }

    var messages: [Message] = []

    for msg in messageRows {
        if let isFromMe = msg["is_from_me"] as? Int64,
           let messageDate = msg["message_date"] as? String {

            var content: String?

            if let attributedBodyData = msg["attributedBody"] as? Data {
                content = decodeAttributedBody(data: attributedBodyData)
            } else if let text = msg["text"] as? String {
                content = text
            }

            if let messageContent = content {
                var sender: String
                if isFromMe == 1 {
                    sender = "Me"
                } else if let handle_id = msg["handle_id"] as? String {
                    sender = getContactName(phoneNumber: handle_id) ?? handle_id
                } else {
                    sender = "Unknown"
                }
                let message = Message(messageDate: messageDate, sender: sender, content: messageContent)
                messages.append(message)
            }
        }
    }

    return messages
}

// Function to parse reaction type
func parseReactionType(text: String?) -> String? {
    guard let text = text else { return nil }

    let reactions: [String: String] = [
        "Loved ": "Loved",
        "Liked ": "Liked",
        "Emphasized ": "Emphasized",
        "Laughed at ": "Laughed at",
        "Disliked ": "Disliked",
        "Questioned ": "Questioned"
    ]

    for (pattern, reaction) in reactions {
        if text.hasPrefix(pattern) {
            return reaction
        }
    }
    return "[reaction]"
}

// Modify the queryMessages function
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

    if let messageLimit = limit {
        baseQuery += " LIMIT \(messageLimit)"
    }

    // Add query execution time logging
    let startTime = CFAbsoluteTimeGetCurrent()
    guard let messageRows = executeSQLQuery(dbPath: chatDBPath, query: baseQuery, parameters: [contactName, chatID]) else {
        print("No messages found.")
        return
    }
    let queryTime = CFAbsoluteTimeGetCurrent() - startTime
    print("Message query execution time: \(String(format: "%.2f", queryTime)) seconds")

    // Start timing message processing
    let processStartTime = CFAbsoluteTimeGetCurrent()
    
    var messages: [Message] = []

    // Process messages from the database using parallel processing
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "com.messages.processing", attributes: .concurrent)
    let syncQueue = DispatchQueue(label: "com.messages.sync")
    
    for msg in messageRows {
        group.enter()
        queue.async {
            if let isFromMe = msg["is_from_me"] as? Int64,
               let messageDate = msg["message_date"] as? String {

                var content: String?

                if let attributedBodyData = msg["attributedBody"] as? Data {
                    content = decodeAttributedBody(data: attributedBodyData)
                } else if let text = msg["text"] as? String {
                    content = text
                }

                if let messageContent = content {
                    let sender = isFromMe == 1 ? "Me" : contactName
                    let message = Message(messageDate: messageDate, sender: sender, content: messageContent)
                    syncQueue.async {
                        messages.append(message)
                    }
                }
            }
            group.leave()
        }
    }
    
    group.wait()
    
    // Add the additional messages, if any
    if let extraMessages = additionalMessages {
        messages.insert(contentsOf: extraMessages, at: 0)
    }

    let processTime = CFAbsoluteTimeGetCurrent() - processStartTime
    print("Message processing time: \(String(format: "%.2f", processTime)) seconds")
    let totalTime = queryTime + processTime
    print("Total execution time: \(String(format: "%.2f", totalTime)) seconds")

    // Now, format and print the messages
    var formattedOutput = ""
    print("\nMessages with \(contactName):")
    print(String(repeating: "-", count: 50))

    for message in messages.sorted(by: { $0.messageDate < $1.messageDate }) {
        let formattedMessage = "\(message.messageDate) - \(message.sender): \(message.content)\n"
        formattedOutput += formattedMessage
        print(formattedMessage, terminator: "")
    }

    // Copy to clipboard
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(formattedOutput, forType: .string)
    print("\nMessages copied to clipboard!")
}

func main() {
    let args = CommandLine.arguments
    var searchContact: String? = nil

    if args.count > 1 {
        searchContact = args[1]
        print("Searching for contact: \(searchContact!)")
    }

    let availableChats = getAvailableChats()

    if availableChats.isEmpty {
        print("No chats found or unable to access the database.")
        return
    }

    // Filter based on search contact
    var filteredChats = availableChats

    if let searchContact = searchContact?.lowercased() {
        filteredChats = availableChats.filter { chat in
            chat.participants.contains(where: { $0.lowercased().contains(searchContact) })
        }
    }

    if filteredChats.isEmpty {
        print("No chats found for the specified contact.")
        return
    }

    // Sort chats by lastMessageDate descending
    filteredChats.sort { $0.lastMessageDate > $1.lastMessageDate }

    // Display available chats
    print("\nAvailable chats:")
    print(String(repeating: "-", count: 50))
    for (index, chat) in filteredChats.enumerated() {
        let participantList = chat.participants.joined(separator: ", ")
        print("\(index + 1). Participants: \(participantList) - \(chat.messageCount) messages - Last message on \(chat.lastMessageDate)")
    }

    // Get user selection
    var choice: Int?
    repeat {
        print("\nSelect a chat number: ", terminator: "")
        if let input = readLine(), let num = Int(input), num > 0, num <= filteredChats.count {
            choice = num
        } else {
            print("Invalid selection. Please try again.")
        }
    } while choice == nil

    // Get message limit
    var limit: Int?
    repeat {
        print("How many recent messages to show? (type 'all' for entire history): ", terminator: "")
        if let input = readLine()?.lowercased() {
            if input == "all" {
                limit = nil
                break
            } else if let num = Int(input), num > 0 {
                limit = num
                break
            } else {
                print("Please enter a valid number or 'all'.")
            }
        }
    } while true

    let selectedChat = filteredChats[choice! - 1]

    // Fetch messages for the selected chat
    if let messages = fetchMessagesForChat(chatID: selectedChat.chatID, participants: selectedChat.participants, limit: limit) {
        // Now, format and print the messages
        var formattedOutput = ""
        print("\nMessages:")
        print(String(repeating: "-", count: 50))

        for message in messages {
            let formattedMessage = "\(message.messageDate) - \(message.sender): \(message.content)\n"
            formattedOutput += formattedMessage
            print(formattedMessage, terminator: "")
        }

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formattedOutput, forType: .string)
        print("\nMessages copied to clipboard!")
    } else {
        print("No messages found for the selected chat.")
    }
}

// Call the main function
main()
