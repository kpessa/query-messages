//
//  ServicesCloudSyncService.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/28/26.
//

import Foundation

struct CloudSyncService {
    static let shared = CloudSyncService()

    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let migrationSentinelKey = "ud_migrated_to_icloud"

    // MARK: - Directory Resolution

    var dataDir: URL {
        let iCloudBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/QueryMessages")
        if fm.fileExists(atPath: iCloudBase.path) {
            return iCloudBase
        }
        if (try? fm.createDirectory(at: iCloudBase, withIntermediateDirectories: true)) != nil {
            return iCloudBase
        }
        // Fallback to ~/Documents/QueryMessages
        let docsBase = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QueryMessages")
        try? fm.createDirectory(at: docsBase, withIntermediateDirectories: true)
        return docsBase
    }

    var notesDir: URL { makeDir(dataDir.appendingPathComponent("notes")) }
    var qaDir: URL { makeDir(dataDir.appendingPathComponent("qa")) }
    var contextDir: URL { makeDir(dataDir.appendingPathComponent("context-files")) }

    private func makeDir(_ url: URL) -> URL {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Pins

    func savePins(_ ids: Set<Int64>) {
        let url = dataDir.appendingPathComponent("pins.json")
        let array = Array(ids)
        guard let data = try? encoder.encode(array) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadPins() -> Set<Int64> {
        let url = dataDir.appendingPathComponent("pins.json")
        guard let data = try? Data(contentsOf: url),
              let array = try? decoder.decode([Int64].self, from: data) else { return [] }
        return Set(array)
    }

    // MARK: - Notes

    func saveNote(_ text: String, for chatID: Int64) {
        let url = notesDir.appendingPathComponent("\(chatID).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadNote(for chatID: Int64) -> String? {
        let url = notesDir.appendingPathComponent("\(chatID).txt")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func deleteNote(for chatID: Int64) {
        let url = notesDir.appendingPathComponent("\(chatID).txt")
        try? fm.removeItem(at: url)
    }

    // MARK: - QA History

    func saveQAHistory(_ entries: [QAEntry], for chatID: Int64) {
        let url = qaDir.appendingPathComponent("\(chatID).json")
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadQAHistory(for chatID: Int64) -> [QAEntry] {
        let url = qaDir.appendingPathComponent("\(chatID).json")
        guard let data = try? Data(contentsOf: url),
              let entries = try? decoder.decode([QAEntry].self, from: data) else { return [] }
        return entries
    }

    func deleteQAHistory(for chatID: Int64) {
        let url = qaDir.appendingPathComponent("\(chatID).json")
        try? fm.removeItem(at: url)
    }

    // MARK: - Context Files

    /// Copies the source file into iCloud (or Documents fallback), returns the synced URL.
    func saveContextFile(from sourceURL: URL, for chatID: Int64) throws -> URL {
        let chatContextDir = makeDir(contextDir.appendingPathComponent("\(chatID)"))
        let destURL = chatContextDir.appendingPathComponent(sourceURL.lastPathComponent)
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    func loadContextFile(for chatID: Int64) -> (url: URL, content: String)? {
        let chatContextDir = contextDir.appendingPathComponent("\(chatID)")
        guard let files = try? fm.contentsOfDirectory(at: chatContextDir,
                                                       includingPropertiesForKeys: nil),
              let fileURL = files.first,
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return (fileURL, content)
    }

    func deleteContextFile(for chatID: Int64) {
        let chatContextDir = contextDir.appendingPathComponent("\(chatID)")
        try? fm.removeItem(at: chatContextDir)
    }

    // MARK: - Migration from UserDefaults

    func migrateFromUserDefaultsIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: Self.migrationSentinelKey) else { return }

        // Migrate pins
        if let stored = ud.array(forKey: "pinnedChatIDs") {
            let ids = Set(stored.compactMap { ($0 as? NSNumber)?.int64Value })
            if !ids.isEmpty { savePins(ids) }
        }

        // Scan all UserDefaults keys for chat-specific data
        let allKeys = ud.dictionaryRepresentation().keys

        for key in allKeys {
            if key.hasPrefix("chatNotes_"), let chatIDStr = key.split(separator: "_").last,
               let chatID = Int64(chatIDStr),
               let text = ud.string(forKey: key), !text.isEmpty {
                saveNote(text, for: chatID)
            } else if key.hasPrefix("qaHistory_"), let chatIDStr = key.split(separator: "_").last,
                      let chatID = Int64(chatIDStr),
                      let data = ud.data(forKey: key),
                      let entries = try? JSONDecoder().decode([QAEntry].self, from: data) {
                saveQAHistory(entries, for: chatID)
            } else if key.hasPrefix("contextFile_"), let chatIDStr = key.split(separator: "_").last,
                      let chatID = Int64(chatIDStr),
                      let path = ud.string(forKey: key) {
                let sourceURL = URL(fileURLWithPath: path)
                if fm.fileExists(atPath: sourceURL.path) {
                    _ = try? saveContextFile(from: sourceURL, for: chatID)
                }
            }
        }

        ud.set(true, forKey: Self.migrationSentinelKey)
    }
}
