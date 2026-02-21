//
//  AppViewModel.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation
import AppKit

struct ResponseStyle: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let stylePrompt: String
}

enum SortMode: String { case recent, popular }

@Observable
@MainActor
class AppViewModel {
    // Services
    private let databaseService = DatabaseService()
    private let contactService = ContactService()
    private var geminiService: GeminiService?
    private let externalFileService = ExternalFileService()

    // Chat list state
    var allChats: [Chat] = []
    var searchText: String = ""
    var selectedChat: Chat? = nil
    var isLoadingChats = false
    var sortMode: SortMode = .recent

    // Message state
    var messages: [Message] = []
    var isLoadingMessages = false
    var externalFilePath: URL? = nil
    var messagesTruncated = false
    var truncatedCount = 0

    // AI state
    var aiSuggestions: [String: String] = [:]  // style id → suggestion text
    var isLoadingAI = false
    var geminiConversation = GeminiConversation()
    var followUpStyleID: String? = nil
    var followUpText = ""
    var reactionContext = ""
    var showCopiedToast = false

    // Contact photo state (thread header — single selected chat)
    var currentContactPhoto: NSImage? = nil

    // Sidebar avatar cache — keyed by chat ID
    var chatPhotos: [Int64: NSImage] = [:]
    private var loadedChatPhotoIDs: Set<Int64> = []

    let responseStyles: [ResponseStyle] = [
        ResponseStyle(id: "normal", name: "Normal", emoji: "💬",
            stylePrompt: "Write a casual, genuine text message response. Sound like a real person texting a friend — use contractions, relaxed phrasing, and natural flow. Avoid filler AI phrases like 'That's so interesting!', 'Absolutely!', or 'I love that!'. Don't be overly polished or enthusiastic. Short like a real text. Only return the message text, nothing else."),
        ResponseStyle(id: "keepgoing", name: "Keep it Going", emoji: "🔥",
            stylePrompt: "Write a genuine, human-sounding text that keeps the conversation going. React naturally to what they said, then weave in one casual question that flows organically — not an interview question, just something a curious person would actually wonder. Sound warm and interested without being try-hard. Avoid AI phrases like 'That's fascinating!' or 'I'd love to hear more about that!'. Use contractions, be a little imperfect, sound real. Conversational length. Only return the message text, nothing else."),
        ResponseStyle(id: "witty", name: "Witty", emoji: "🧠",
            stylePrompt: "Write a witty, clever text. Land a sharp observation or well-timed joke — smart without trying too hard. Sound like a funny real person, not a comedian doing a bit. Avoid generic humor or AI-sounding setups. Short and punchy. Only return the message text, nothing else."),
        ResponseStyle(id: "playful", name: "Fun & Playful", emoji: "🎉",
            stylePrompt: "Write a fun, playful text. Keep the energy light and a little cheeky if it fits. Sound like someone genuinely enjoying the conversation, not performing enthusiasm. Avoid over-the-top exclamation points or AI-isms like 'How fun!' or 'That's amazing!'. Only return the message text, nothing else."),
        ResponseStyle(id: "emoji", name: "Short & Emoji", emoji: "✨",
            stylePrompt: "Write a very short text response — 1-2 sentences max. Use emojis the way a real person would while texting, naturally placed. Don't sound like a bot. Only return the message text, nothing else."),
        ResponseStyle(id: "pirate", name: "Cap'n Kurt", emoji: "🏴‍☠️",
            stylePrompt: "Respond as Cap'n Kurt, a bold and charming pirate. Always open with a pirate exclamation like 'ARRGH!', 'AVAST!', 'BLIMEY!', or 'SHIVER ME TIMBERS!' in all caps. Use pirate speak throughout (ye, matey, aye, landlubber, me hearty, etc.) while keeping the message on-topic. Use a small number of well-placed emojis for flair — not constantly, just where they add character. Sign off with Cap'n Kurt and include pirate-themed emojis like 🦜🏴‍☠️🪝⚓ at the end. Only return the message text, nothing else.")
    ]

    // Error state
    var errorMessage: String? = nil
    var showFullDiskAccessBanner = false

    // MARK: - Custom Pinning (UserDefaults)

    private var pinnedChatIDs: Set<Int64> {
        get {
            guard let stored = UserDefaults.standard.array(forKey: "pinnedChatIDs") else { return [] }
            return Set(stored.compactMap { ($0 as? NSNumber)?.int64Value })
        }
        set {
            UserDefaults.standard.set(newValue.map { NSNumber(value: $0) }, forKey: "pinnedChatIDs")
        }
    }

    func togglePin(_ chat: Chat) {
        var ids = pinnedChatIDs
        if ids.contains(chat.id) { ids.remove(chat.id) } else { ids.insert(chat.id) }
        pinnedChatIDs = ids
        allChats = allChats.map { c in
            var copy = c; copy.isPinnedByUser = ids.contains(c.id); return copy
        }
    }

    // MARK: - Computed Properties

    var filteredChats: [Chat] {
        guard !searchText.isEmpty else { return allChats }
        let lowercased = searchText.lowercased()
        return allChats.filter { chat in
            chat.displayName.lowercased().contains(lowercased)
        }
    }

    var pinnedChats: [Chat] {
        filteredChats.filter { $0.isPinned }
            .sorted { $0.lastMessageDateRaw > $1.lastMessageDateRaw }
    }

    var unpinnedChats: [Chat] {
        let pinnedIDs = Set(pinnedChats.map { $0.id })
        let base = filteredChats.filter { !pinnedIDs.contains($0.id) }
        return sortMode == .popular
            ? base.sorted { $0.messageCount > $1.messageCount }
            : base  // already sorted by lastMessageDate DESC from DB query
    }

    // MARK: - Initialization

    init() {
        // Try to initialize Gemini service
        do {
            geminiService = try GeminiService()
        } catch {
            print("⚠️ Gemini service unavailable: \(error)")
        }

        Task {
            await checkPermissions()
        }
    }

    // MARK: - Permissions

    private func checkPermissions() async {
        // Request contacts access
        _ = await contactService.requestAuthorization()

        // Check database access
        let hasAccess = await databaseService.checkDatabaseAccess()
        showFullDiskAccessBanner = !hasAccess
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Chat Actions

    // Maps chatID → raw first participant identifier (phone/email before name resolution)
    private var chatPhotoIdentifiers: [Int64: String] = [:]

    func loadChats() async {
        isLoadingChats = true
        errorMessage = nil
        chatPhotos = [:]
        loadedChatPhotoIDs = []

        do {
            let chats = try await databaseService.getAvailableChats()

            // Resolve contact names
            var resolvedChats: [Chat] = []
            for chat in chats {
                // Store raw identifier before resolving, for photo lookups
                chatPhotoIdentifiers[chat.id] = chat.participants.first
                let resolvedParticipants = await resolveParticipants(chat.participants)
                var resolvedChat = Chat(
                    id: chat.id,
                    participants: resolvedParticipants,
                    messageCount: chat.messageCount,
                    lastMessageDate: chat.lastMessageDate,
                    lastMessageDateRaw: chat.lastMessageDateRaw,
                    pinnedDate: chat.pinnedDate
                )
                resolvedChat.isPinnedByUser = pinnedChatIDs.contains(chat.id)
                resolvedChats.append(resolvedChat)
            }

            allChats = resolvedChats
            showFullDiskAccessBanner = false

        } catch {
            errorMessage = error.localizedDescription
            if error is DatabaseError {
                showFullDiskAccessBanner = true
            }
        }

        isLoadingChats = false
    }

    private func resolveParticipants(_ participants: [String]) async -> [String] {
        var resolved: [String] = []
        for participant in participants {
            let name = await contactService.resolve(participant)
            resolved.append(name)
        }
        return resolved
    }

    func selectChat(_ chat: Chat) async {
        selectedChat = chat
        await loadMessages(for: chat.id)
        await loadContactPhoto(for: chat)
    }

    // MARK: - Contact Photo

    func loadContactPhoto(for chat: Chat) async {
        let identifier = chatPhotoIdentifiers[chat.id] ?? chat.participants.first
        guard let id = identifier else { currentContactPhoto = nil; return }
        if let data = await contactService.resolvePhoto(id), let img = NSImage(data: data) {
            currentContactPhoto = img
        } else {
            currentContactPhoto = nil
        }
    }

    /// Lazily loads a sidebar avatar; no-ops if already fetched for this chat.
    func loadChatPhoto(for chat: Chat) async {
        guard !loadedChatPhotoIDs.contains(chat.id) else { return }
        loadedChatPhotoIDs.insert(chat.id)
        let identifier = chatPhotoIdentifiers[chat.id] ?? chat.participants.first
        guard let id = identifier else { return }
        if let data = await contactService.resolvePhoto(id), let img = NSImage(data: data) {
            chatPhotos[chat.id] = img
        }
    }

    // MARK: - Message Actions

    private func loadMessages(for chatID: Int64, limit: Int = 100) async {
        isLoadingMessages = true
        errorMessage = nil
        messagesTruncated = false

        do {
            let loadedMessages = try await databaseService.fetchMessages(for: chatID, limit: limit)

            // Resolve sender names
            var resolvedMessages: [Message] = []
            for message in loadedMessages {
                let resolvedSender = message.isFromMe ? "Me" : await contactService.resolve(message.sender)
                let resolvedMessage = Message(
                    messageDate: message.messageDate,
                    sender: resolvedSender,
                    content: message.content
                )
                resolvedMessages.append(resolvedMessage)
            }

            messages = resolvedMessages

            // Check if truncated
            if messages.count >= limit {
                messagesTruncated = true
                truncatedCount = limit
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMessages = false
    }

    func refreshMessages() async {
        guard let chat = selectedChat else { return }
        await loadMessages(for: chat.id)
    }

    func loadExternalFile(_ url: URL) async {
        externalFilePath = url

        do {
            let externalMessages = try await externalFileService.loadMessages(from: url)

            // Merge with existing messages (deduplicate by content and date)
            var merged = messages
            for message in externalMessages {
                if !merged.contains(where: { $0.content == message.content && $0.messageDate == message.messageDate }) {
                    merged.append(message)
                }
            }

            // Sort by date
            messages = merged.sorted { $0.messageDate < $1.messageDate }

        } catch {
            errorMessage = "Failed to load external file: \(error.localizedDescription)"
        }
    }

    // MARK: - AI Actions

    func getAISuggestion() async {
        guard let geminiService else {
            errorMessage = "Gemini API is not configured"
            return
        }
        guard !messages.isEmpty else {
            errorMessage = "No messages to analyze"
            return
        }

        isLoadingAI = true
        aiSuggestions = [:]
        errorMessage = nil
        geminiConversation.reset()

        let msgSnapshot = messages
        let ctx = reactionContext.isEmpty ? nil : reactionContext
        let styles = responseStyles

        // Fire all styles concurrently — results arrive and display as each finishes
        await withTaskGroup(of: (String, String).self) { group in
            for style in styles {
                group.addTask {
                    do {
                        let text = try await geminiService.generateSuggestion(
                            messages: msgSnapshot,
                            context: ctx,
                            stylePrompt: style.stylePrompt
                        )
                        return (style.id, text)
                    } catch {
                        return (style.id, "⚠️ \(error.localizedDescription)")
                    }
                }
            }
            for await (styleID, text) in group {
                aiSuggestions[styleID] = text
            }
        }

        isLoadingAI = false
    }

    func sendFollowUp(for styleID: String) async {
        guard let geminiService else {
            errorMessage = "Gemini API is not configured"
            return
        }
        guard !followUpText.isEmpty else { return }
        guard let style = responseStyles.first(where: { $0.id == styleID }) else { return }
        guard let currentText = aiSuggestions[styleID] else { return }

        isLoadingAI = true
        errorMessage = nil

        let msgSnapshot = messages
        let ctx = reactionContext.isEmpty ? nil : reactionContext
        let instruction = followUpText
        followUpText = ""
        followUpStyleID = nil

        let refinedPrompt = """
        \(style.stylePrompt)

        Your previous response was: "\(currentText)"
        Refine it with this feedback: \(instruction)
        Only return the revised response text, no explanation.
        """

        do {
            let text = try await geminiService.generateSuggestion(
                messages: msgSnapshot,
                context: ctx,
                stylePrompt: refinedPrompt
            )
            aiSuggestions[styleID] = text
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingAI = false
    }

    // MARK: - Utility

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        showCopiedToast = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopiedToast = false
        }
    }
}
