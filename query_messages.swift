#!/usr/bin/env swift

import Foundation
import SQLite3
import AppKit
import Contacts

// Paths to databases
let chatDBPath = NSHomeDirectory() + "/Library/Messages/chat.db"

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
        COUNT(m.ROWID) AS message_count,
        MAX(m.date) AS last_message_date
    FROM chat c
    JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
    JOIN handle h ON chj.handle_id = h.ROWID
    JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
    JOIN message m ON cmj.message_id = m.ROWID
    GROUP BY c.ROWID, h.id
    ORDER BY last_message_date DESC
    LIMIT 100
    """

    guard let results = executeSQLQuery(dbPath: chatDBPath, query: query) else {
        return []
    }

    var chats: [(Int64, String, Int64, String, String?)] = []
    for row in results {
        if let chat_id = row["chat_id"] as? Int64,
           let handle_id = row["handle_id"] as? String,
           let message_count = row["message_count"] as? Int64,
           let last_message_date = row["last_message_date"] as? Int64 {

            let contactName = getContactName(phoneNumber: handle_id)
            // Convert date
            let dateInSeconds = Double(last_message_date) / 1000000000 + 978307200
            let date = Date(timeIntervalSince1970: dateInSeconds)
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let formattedDate = formatter.string(from: date)

            chats.append((chat_id, handle_id, message_count, formattedDate, contactName))
        }
    }
    return chats
}

// Function to get contact name using Contacts framework
func getContactName(phoneNumber: String) -> String? {
    let semaphore = DispatchSemaphore(value: 0)
    var contactName: String?

    let store = CNContactStore()

    store.requestAccess(for: .contacts) { granted, error in
        if granted {
            let keysToFetch = [
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactPhoneNumbersKey
            ] as [CNKeyDescriptor]

            let request = CNContactFetchRequest(keysToFetch: keysToFetch)

            do {
                try store.enumerateContacts(with: request) { (contact, stop) in
                    for phone in contact.phoneNumbers {
                        let phoneNumberDigits = phone.value.stringValue.filter("0123456789".contains)
                        let inputDigits = phoneNumber.filter("0123456789".contains)
                        if phoneNumberDigits.contains(inputDigits) || inputDigits.contains(phoneNumberDigits) {
                            contactName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                            stop.pointee = true
                            break
                        }
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

    _ = semaphore.wait(timeout: .now() + 5)
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

    guard let messageRows = executeSQLQuery(dbPath: chatDBPath, query: baseQuery, parameters: [contactName, chatID]) else {
        print("No messages found.")
        return
    }

    var messages: [Message] = []

    // Process messages from the database
    for msg in messageRows {
        guard let isFromMe = msg["is_from_me"] as? Int64,
              let messageDate = msg["message_date"] as? String else { continue }

        var content: String?

        if let attributedBodyData = msg["attributedBody"] as? Data {
            content = decodeAttributedBody(data: attributedBodyData)
        } else if let text = msg["text"] as? String {
            content = text
        }

        guard let messageContent = content else { continue }

        let sender = isFromMe == 1 ? "Me" : contactName
        let message = Message(messageDate: messageDate, sender: sender, content: messageContent)
        messages.append(message)
    }

    // Add the additional messages, if any
    if let extraMessages = additionalMessages {
        messages.insert(contentsOf: extraMessages, at: 0)
    }

    // Now, format and print the messages
    var formattedOutput = ""
    print("\nMessages with \(contactName):")
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
