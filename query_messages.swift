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

// Function to get available chats
func getAvailableChats() -> [(chatID: Int64, contactID: String, messageCount: Int64, lastMessageDate: String, contactName: String?)] {
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
        return []
    }
    let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
    print("Query execution time: \(String(format: "%.2f", timeElapsed)) seconds")

    var chats: [(chatID: Int64, contactID: String, messageCount: Int64, lastMessageDate: String, contactName: String?)] = []
    
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

                let contactName = getContactName(phoneNumber: handle_id)
                let dateInSeconds = Double(last_message_date) / 1000000000 + 978307200
                let date = Date(timeIntervalSince1970: dateInSeconds)
                let formattedDate = dateFormatter.string(from: date)

                syncQueue.async {
                    chats.append((chat_id, handle_id, message_count, formattedDate, contactName))
                }
            }
            group.leave()
        }
    }
    
    // Wait for all processing to complete
    group.wait()

    return chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
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

// Function to decode attributed body
func decodeAttributedBody(data: Data) -> String? {
    if let unarchiver = NSUnarchiver(forReadingWith: data) {
        if let attributedString = unarchiver.decodeObject() as? NSAttributedString {
            return attributedString.string
        }
    }

    if let plainText = String(data: data, encoding: .utf8) {
        return plainText
    }

    let nsStringMarker = "NSString".data(using: .ascii)!
    if let range = data.range(of: nsStringMarker) {
        let startIndex = range.upperBound + 3
        if startIndex < data.count {
            let textData = data.suffix(from: startIndex)
            if let text = String(data: textData, encoding: .utf8) {
                return text.components(separatedBy: .controlCharacters).joined()
            }
        }
    }

    return nil
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

// Define a Message struct to hold the message data
struct Message {
    let messageDate: String
    let sender: String
    let content: String
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

    // Check if a contact name or phone number is passed as an argument
    if args.count > 1 {
        searchContact = args[1] // The first argument is the executable name, so use the second one
        print("Searching for contact: \(searchContact!)")
    }

    let chats = getAvailableChats()

    if chats.isEmpty {
        print("No chats found or unable to access the database.")
        return
    }

    // Declare filteredChats
    var filteredChats: [(Int64, String, Int64, String, String?)] = []

    // Filter chats based on searchContact
    if let searchContact = searchContact {
        filteredChats = chats.filter {
            let (_, contactID, _, _, contactName) = $0
            return contactID.lowercased().contains(searchContact.lowercased()) ||
                   (contactName?.lowercased().contains(searchContact.lowercased()) ?? false)
        }
    } else {
        filteredChats = chats
    }

    if filteredChats.isEmpty {
        print("No chats found for the specified contact.")
        return
    }

    // Display available chats
    print("\nAvailable chats:")
    print(String(repeating: "-", count: 50))
    for (index, chat) in filteredChats.enumerated() {
        let (_, contactID, count, lastMessageDate, name) = chat
        if let name = name {
            print("\(index + 1). \(name) (\(contactID)) - \(count) messages - Last message on \(lastMessageDate)")
        } else {
            print("\(index + 1). \(contactID) - \(count) messages - Last message on \(lastMessageDate)")
        }
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
    let selectedChatID = selectedChat.0
    let selectedContactID = selectedChat.1
    let contactName = selectedChat.4 ?? selectedContactID // Use the contact name if available, otherwise use the contact ID

    queryMessages(chatID: selectedChatID, contactID: selectedContactID, limit: limit, additionalMessages: nil)
}

main()
