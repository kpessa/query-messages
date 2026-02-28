//
//  AppViewModel.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation
import AppKit

enum StyleTier { case quick, thoughtful, deep }

struct ResponseStyle: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let stylePrompt: String
    var tier: StyleTier = .quick
    var usesFullHistory: Bool { tier == .deep }
}

enum SortMode: String { case recent, popular }
enum AITab: String { case suggestions, insights }

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
    var hasMoreMessages: Bool = false
    var isLoadingMoreMessages: Bool = false
    var scrollTargetAfterLoad: UUID? = nil
    private var oldestLoadedDateRaw: Int64 = Int64.max
    private let messagePageSize = 100

    // Per-chat context files — keyed by chat ID; loaded on chat selection
    var chatContextFiles: [Int64: (url: URL, content: String)] = [:]

    // Per-chat in-app notes — keyed by chat ID; persisted to UserDefaults
    var chatNotes: [Int64: String] = [:]

    // AI state
    var aiSuggestions: [String: String] = [:]  // style id → suggestion text
    var suggestionUsage: [String: TokenUsage] = [:]  // style id → token usage
    var sessionPromptTokens: Int = 0
    var sessionCompletionTokens: Int = 0
    var isLoadingAI = false
    var loadingStyleIDs: Set<String> = []
    var isLoadingThoughtful: Bool {
        responseStyles.filter { $0.tier == .thoughtful }.contains { loadingStyleIDs.contains($0.id) }
    }
    var isLoadingDeep: Bool {
        responseStyles.filter { $0.tier == .deep }.contains { loadingStyleIDs.contains($0.id) }
    }
    var geminiConversation = GeminiConversation()
    var followUpStyleID: String? = nil
    var followUpText = ""
    var reactionContext = ""
    var showCopiedToast = false
    var selectedAITab: AITab = .suggestions

    var sessionTotalTokens: Int { sessionPromptTokens + sessionCompletionTokens }
    var sessionEstimatedCost: Double {
        Double(sessionPromptTokens) * TokenUsage.inputCostPerMToken / 1_000_000
        + Double(sessionCompletionTokens) * TokenUsage.outputCostPerMToken / 1_000_000
    }

    // Q&A / Insights state
    var conversationQuestion: String = ""
    var isLoadingQuestion: Bool = false
    var qaHistories: [Int64: [QAEntry]] = [:]

    var currentQAHistory: [QAEntry] {
        guard let id = selectedChat?.id else { return [] }
        return qaHistories[id] ?? []
    }

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
            stylePrompt: "Respond as Cap'n Kurt, a bold and charming pirate. Always open with a pirate exclamation like 'ARRGH!', 'AVAST!', 'BLIMEY!', or 'SHIVER ME TIMBERS!' in all caps. Use pirate speak throughout (ye, matey, aye, landlubber, me hearty, etc.) while keeping the message on-topic. Use a small number of well-placed emojis for flair — not constantly, just where they add character. Sign off with Cap'n Kurt and include pirate-themed emojis like 🦜🏴‍☠️🪝⚓ at the end. Only return the message text, nothing else."),
        ResponseStyle(id: "connect_dots", name: "Connect the Dots", emoji: "🔗",
            stylePrompt: """
            Write a thoughtful text response from a guy who's actually been paying attention — not just to this message, but to the bigger picture of this person's life. Reference something from earlier in the conversation or connect what they just said to something you already know about them, their situation, or a pattern you've noticed. Show you're tracking the whole thread, not just reacting to the latest thing. Sound like someone who genuinely gives a shit, not someone performing attentiveness. Don't announce that you're being thoughtful — just be it. Use contractions, natural phrasing, real voice. A few sentences is right — enough room to land something meaningful without turning it into a speech. Avoid all AI filler phrases. Only return the message text, nothing else.
            """, tier: .deep),
        ResponseStyle(id: "real_talk", name: "Real Talk", emoji: "🫱",
            stylePrompt: """
            Write an honest, genuine text response from a guy who's telling it straight. Share your actual read on what they said — what you really think, feel, or notice — even if it's a little direct or a little personal. This isn't advice and it's not cheerleading. It's just your honest take from someone who knows them and isn't going to blow smoke. Can be a little vulnerable or a little blunt depending on what the moment calls for. Sound real, not coached. Contractions, natural rhythm, comfortable imperfection. Two to four sentences — give it enough space to mean something. Avoid performative language and AI-isms. Only return the message text, nothing else.
            """, tier: .deep),
        ResponseStyle(id: "pull_thread", name: "Pull the Thread", emoji: "🎯",
            stylePrompt: """
            Write a thoughtful text response that goes beneath the surface of what they said. Pick up on the most interesting, emotionally honest, or revealing thing in their message — something they maybe didn't fully unpack — and gently pull on it. Ask a genuinely curious question about their experience or inner take on it, or make an observation that reframes what they said in a way that feels true. Don't just react to the obvious thing. Show you were actually listening and thinking. Sound like a curious, grounded guy — not a therapist, not an interviewer, just someone who finds the person genuinely interesting and wants to go somewhere real with the conversation. Natural phrasing, honest tone, a few sentences. Avoid AI phrases. Only return the message text, nothing else.
            """, tier: .deep),
        ResponseStyle(id: "first_we_feast", name: "First We Feast", emoji: "🌶️",
            stylePrompt: """
            You are channeling the interview energy of Sean Evans from Hot Ones — a guy famous for doing absurdly deep research and asking questions so specific and unexpected that guests stop mid-sentence and say "wow, how did you even find that?"

            Study this conversation like you spent three weeks in a research hole. Find the most specific, overlooked, or telling detail — a particular word choice, a decision buried in something they mentioned earlier, a contradiction, a moment that reveals something about how they actually think. Then ask about *that exact thing* — not the general topic, the specific thing.

            The question should feel like it came from someone who listened to everything they've ever said and picked the one thread nobody else thought to pull. It should be precise, curious, and a little disarming — not confrontational, just unexpectedly sharp.

            Don't do a preamble. Don't compliment the question you're about to ask. Just ask it, the way Sean would: confident, specific, genuinely curious.

            One question. Make it land. Only return the message text, nothing else.
            """, tier: .deep),
        ResponseStyle(id: "momentum", name: "Momentum", emoji: "⚡",
            stylePrompt: """
            Write a genuine text response from someone who's been tracking the energy of this conversation — not just the last message, but the current of where things have been flowing lately. What's the vibe been? Are things picking up, getting more real, staying light? Respond in a way that's aware of and moves with that trajectory. Don't narrate it — just let your awareness of it show up in how you respond. Natural phrasing, real voice. Only return the message text, nothing else.
            """, tier: .thoughtful),
        ResponseStyle(id: "pattern_spotter", name: "Pattern Spotter", emoji: "🔍",
            stylePrompt: """
            Write a text response from someone who's noticed something that keeps showing up in this conversation — a recurring theme, running joke, something they keep circling back to, or a dynamic that's become familiar between you. Reference it or let it quietly inform your response. Not as a callback just for the sake of it — only if there's actually a thread worth pulling. If there is, use it naturally. Sound like someone who actually pays attention over time. Only return the message text, nothing else.
            """, tier: .thoughtful),
        ResponseStyle(id: "tone_match", name: "Tone Match", emoji: "🎚️",
            stylePrompt: """
            Write a text response that deeply matches their communication energy from the recent stretch of conversation. Not just their latest message — the whole texture of how they've been talking lately: their pacing, warmth, how much they're opening up, whether they're being playful or serious. Meet them exactly where they are. Sound like someone genuinely attuned to the person they're talking to. Don't mention what you're doing — just do it. Only return the message text, nothing else.
            """, tier: .thoughtful),
    ]

    // Error state
    var errorMessage: String? = nil
    var showFullDiskAccessBanner = false

    // MARK: - Custom Pinning (CloudSync)

    private var pinnedChatIDs: Set<Int64> {
        get { CloudSyncService.shared.loadPins() }
        set { CloudSyncService.shared.savePins(newValue) }
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

        CloudSyncService.shared.migrateFromUserDefaultsIfNeeded()
        loadChatCache()
    }

    // MARK: - Chat Cache

    private let chatCacheKey = "cachedChatList"

    private func saveChatCache() {
        guard let data = try? JSONEncoder().encode(allChats) else { return }
        UserDefaults.standard.set(data, forKey: chatCacheKey)
    }

    private func loadChatCache() {
        guard let data = UserDefaults.standard.data(forKey: chatCacheKey),
              let chats = try? JSONDecoder().decode([Chat].self, from: data) else { return }
        allChats = chats
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

            // Store raw identifiers before resolving, for photo lookups
            for chat in chats {
                chatPhotoIdentifiers[chat.id] = chat.participants.first
            }

            // Resolve contact names concurrently, preserving original sort order
            let pinnedIDs = pinnedChatIDs
            var resolvedChats: [Chat] = []
            await withTaskGroup(of: (Int, Chat).self) { group in
                for (i, chat) in chats.enumerated() {
                    group.addTask {
                        let resolvedParticipants = await self.resolveParticipants(chat.participants)
                        var resolved = Chat(
                            id: chat.id,
                            participants: resolvedParticipants,
                            messageCount: chat.messageCount,
                            lastMessageDate: chat.lastMessageDate,
                            lastMessageDateRaw: chat.lastMessageDateRaw,
                            pinnedDate: chat.pinnedDate
                        )
                        resolved.isPinnedByUser = pinnedIDs.contains(chat.id)
                        return (i, resolved)
                    }
                }
                var results: [(Int, Chat)] = []
                for await pair in group { results.append(pair) }
                resolvedChats = results.sorted { $0.0 < $1.0 }.map { $0.1 }
            }

            allChats = resolvedChats
            saveChatCache()
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
        await loadInitialMessages(for: chat.id)
        await loadContactPhoto(for: chat)
        loadChatContextFile(for: chat.id)
        loadNotes(for: chat.id)
        loadQAHistory(for: chat.id)
        conversationQuestion = ""
    }

    // MARK: - Context File Actions

    func attachContextFile(_ url: URL) {
        guard let chatID = selectedChat?.id else { return }
        do {
            let syncedURL = try CloudSyncService.shared.saveContextFile(from: url, for: chatID)
            let content = try String(contentsOf: syncedURL, encoding: .utf8)
            chatContextFiles[chatID] = (syncedURL, content)
        } catch {
            errorMessage = "Could not attach file: \(error.localizedDescription)"
        }
    }

    func detachContextFile() {
        guard let chatID = selectedChat?.id else { return }
        chatContextFiles.removeValue(forKey: chatID)
        CloudSyncService.shared.deleteContextFile(for: chatID)
    }

    private func loadChatContextFile(for chatID: Int64) {
        guard let result = CloudSyncService.shared.loadContextFile(for: chatID) else { return }
        chatContextFiles[chatID] = result
    }

    // MARK: - Notes Actions

    func saveNotes(_ text: String, for chatID: Int64) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            chatNotes.removeValue(forKey: chatID)
            CloudSyncService.shared.deleteNote(for: chatID)
        } else {
            chatNotes[chatID] = trimmed
            CloudSyncService.shared.saveNote(trimmed, for: chatID)
        }
    }

    private func loadNotes(for chatID: Int64) {
        guard let text = CloudSyncService.shared.loadNote(for: chatID), !text.isEmpty else { return }
        chatNotes[chatID] = text
    }

    private func combinedContext(for chatID: Int64?) -> String? {
        guard let chatID else { return nil }
        var parts: [String] = []
        if let notes = chatNotes[chatID], !notes.isEmpty {
            parts.append("Date/Relationship Notes:\n\(notes)")
        }
        if let file = chatContextFiles[chatID]?.content, !file.isEmpty {
            parts.append(file)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n---\n\n")
    }

    // MARK: - QA History Persistence

    private func loadQAHistory(for chatID: Int64) {
        let entries = CloudSyncService.shared.loadQAHistory(for: chatID)
        if !entries.isEmpty { qaHistories[chatID] = entries }
    }

    private func saveQAHistory(for chatID: Int64) {
        guard let entries = qaHistories[chatID] else { return }
        CloudSyncService.shared.saveQAHistory(entries, for: chatID)
    }

    func deleteQAEntry(_ entry: QAEntry) {
        guard let chatID = selectedChat?.id else { return }
        qaHistories[chatID]?.removeAll { $0.id == entry.id }
        saveQAHistory(for: chatID)
    }

    func clearQAHistory() {
        guard let chatID = selectedChat?.id else { return }
        qaHistories[chatID] = []
        CloudSyncService.shared.deleteQAHistory(for: chatID)
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

    private func resolveMessages(_ raw: [Message]) async -> [Message] {
        var resolved: [Message] = []
        for message in raw {
            let resolvedSender = message.isFromMe ? "Me" : await contactService.resolve(message.sender)
            resolved.append(Message(
                dateRaw: message.dateRaw,
                messageDate: message.messageDate,
                sender: resolvedSender,
                content: message.content
            ))
        }
        return resolved
    }

    private func loadInitialMessages(for chatID: Int64) async {
        isLoadingMessages = true
        errorMessage = nil
        hasMoreMessages = false
        oldestLoadedDateRaw = Int64.max

        do {
            let loadedMessages = try await databaseService.fetchMessages(for: chatID, limit: messagePageSize, beforeDate: Int64.max)
            messages = await resolveMessages(loadedMessages)
            oldestLoadedDateRaw = messages.first?.dateRaw ?? Int64.max
            hasMoreMessages = loadedMessages.count == messagePageSize
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMessages = false
    }

    func loadMoreMessages() async {
        guard !isLoadingMoreMessages, hasMoreMessages, let chat = selectedChat else { return }
        isLoadingMoreMessages = true
        let anchorID = messages.first?.id
        let batch = try? await databaseService.fetchMessages(for: chat.id, limit: messagePageSize, beforeDate: oldestLoadedDateRaw)
        if let batch {
            let resolved = await resolveMessages(batch)
            if !resolved.isEmpty {
                oldestLoadedDateRaw = resolved.first?.dateRaw ?? oldestLoadedDateRaw
                messages = resolved + messages
                scrollTargetAfterLoad = anchorID
            }
            hasMoreMessages = batch.count == messagePageSize
        }
        isLoadingMoreMessages = false
    }

    func loadAllMessages() async {
        guard let chat = selectedChat else { return }
        isLoadingMessages = true
        let all = try? await databaseService.fetchMessages(for: chat.id, limit: 1_000_000, beforeDate: Int64.max)
        if let all {
            messages = await resolveMessages(all)
            oldestLoadedDateRaw = messages.first?.dateRaw ?? Int64.max
            hasMoreMessages = false
        }
        isLoadingMessages = false
    }

    func refreshMessages() async {
        guard let chat = selectedChat else { return }
        messages = []
        hasMoreMessages = false
        oldestLoadedDateRaw = Int64.max
        await loadInitialMessages(for: chat.id)
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
        suggestionUsage = [:]
        sessionPromptTokens = 0
        sessionCompletionTokens = 0
        loadingStyleIDs = []
        errorMessage = nil
        geminiConversation.reset()

        let msgSnapshot = messages
        let ctx = reactionContext.isEmpty ? nil : reactionContext
        let fileContent = combinedContext(for: selectedChat?.id)
        let styles = responseStyles.filter { $0.tier == .quick }

        loadingStyleIDs = Set(styles.map { $0.id })

        // Fire quick styles concurrently — results arrive and display as each finishes
        await withTaskGroup(of: (String, String, TokenUsage?).self) { group in
            for style in styles {
                group.addTask {
                    do {
                        let (text, usage) = try await geminiService.generateSuggestion(
                            messages: Array(msgSnapshot.suffix(20)),
                            context: ctx,
                            fileContent: fileContent,
                            stylePrompt: style.stylePrompt
                        )
                        return (style.id, text, usage)
                    } catch {
                        return (style.id, "⚠️ \(error.localizedDescription)", nil)
                    }
                }
            }
            for await (styleID, text, usage) in group {
                aiSuggestions[styleID] = text
                loadingStyleIDs.remove(styleID)
                if let usage {
                    suggestionUsage[styleID] = usage
                    sessionPromptTokens += usage.promptTokens
                    sessionCompletionTokens += usage.completionTokens
                }
            }
        }

        isLoadingAI = false
    }

    func getThoughtfulSuggestions() async {
        guard let geminiService else { errorMessage = "Gemini API is not configured"; return }
        let styles = responseStyles.filter { $0.tier == .thoughtful }
        let msgSnapshot = Array(messages.suffix(75))
        let ctx = reactionContext.isEmpty ? nil : reactionContext
        let fileContent = combinedContext(for: selectedChat?.id)
        loadingStyleIDs = loadingStyleIDs.union(Set(styles.map { $0.id }))

        await withTaskGroup(of: (String, String, TokenUsage?).self) { group in
            for style in styles {
                group.addTask {
                    do {
                        let (text, usage) = try await geminiService.generateSuggestion(
                            messages: msgSnapshot, context: ctx, fileContent: fileContent, stylePrompt: style.stylePrompt)
                        return (style.id, text, usage)
                    } catch {
                        return (style.id, "⚠️ \(error.localizedDescription)", nil)
                    }
                }
            }
            for await (styleID, text, usage) in group {
                aiSuggestions[styleID] = text
                loadingStyleIDs.remove(styleID)
                if let usage {
                    suggestionUsage[styleID] = usage
                    sessionPromptTokens += usage.promptTokens
                    sessionCompletionTokens += usage.completionTokens
                }
            }
        }
    }

    func getDeepSuggestions() async {
        guard let geminiService else {
            errorMessage = "Gemini API is not configured"
            return
        }
        let styles = responseStyles.filter { $0.tier == .deep }
        let msgSnapshot = messages
        let ctx = reactionContext.isEmpty ? nil : reactionContext
        let fileContent = combinedContext(for: selectedChat?.id)
        loadingStyleIDs = Set(styles.map { $0.id })

        await withTaskGroup(of: (String, String, TokenUsage?).self) { group in
            for style in styles {
                group.addTask {
                    do {
                        let (text, usage) = try await geminiService.generateSuggestion(
                            messages: msgSnapshot,
                            context: ctx,
                            fileContent: fileContent,
                            stylePrompt: style.stylePrompt
                        )
                        return (style.id, text, usage)
                    } catch {
                        return (style.id, "⚠️ \(error.localizedDescription)", nil)
                    }
                }
            }
            for await (styleID, text, usage) in group {
                aiSuggestions[styleID] = text
                loadingStyleIDs.remove(styleID)
                if let usage {
                    suggestionUsage[styleID] = usage
                    sessionPromptTokens += usage.promptTokens
                    sessionCompletionTokens += usage.completionTokens
                }
            }
        }
    }

    func getSingleOptInSuggestion(for styleID: String) async {
        guard let geminiService,
              let style = responseStyles.first(where: { $0.id == styleID }) else { return }
        let msgSnapshot = style.tier == .thoughtful ? Array(messages.suffix(75)) : messages
        let ctx = reactionContext.isEmpty ? nil : reactionContext
        let fileContent = combinedContext(for: selectedChat?.id)
        loadingStyleIDs.insert(styleID)
        do {
            let (text, usage) = try await geminiService.generateSuggestion(
                messages: msgSnapshot,
                context: ctx,
                fileContent: fileContent,
                stylePrompt: style.stylePrompt
            )
            aiSuggestions[styleID] = text
            if let usage {
                suggestionUsage[styleID] = usage
                sessionPromptTokens += usage.promptTokens
                sessionCompletionTokens += usage.completionTokens
            }
        } catch {
            aiSuggestions[styleID] = "⚠️ \(error.localizedDescription)"
        }
        loadingStyleIDs.remove(styleID)
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
        let fileContent = combinedContext(for: selectedChat?.id)
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
            let (text, usage) = try await geminiService.generateSuggestion(
                messages: msgSnapshot,
                context: ctx,
                fileContent: fileContent,
                stylePrompt: refinedPrompt
            )
            aiSuggestions[styleID] = text
            if let usage {
                suggestionUsage[styleID] = usage
                sessionPromptTokens += usage.promptTokens
                sessionCompletionTokens += usage.completionTokens
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingAI = false
    }

    func askConversationQuestion(useFullContext: Bool = false) async {
        guard let geminiService else { errorMessage = "Gemini API is not configured"; return }
        guard !messages.isEmpty else { errorMessage = "No messages to analyze"; return }
        guard !conversationQuestion.isEmpty else { return }
        guard let chatID = selectedChat?.id else { return }

        isLoadingQuestion = true
        errorMessage = nil

        let msgSnapshot: [Message]
        if useFullContext, let chat = selectedChat {
            let all = try? await databaseService.fetchMessages(
                for: chat.id, limit: 1_000_000, beforeDate: Int64.max)
            msgSnapshot = await resolveMessages(all ?? messages)
        } else {
            msgSnapshot = messages
        }
        let fileContent = combinedContext(for: selectedChat?.id)
        let question = conversationQuestion
        let priorQA = Array((qaHistories[chatID] ?? []).suffix(5))
        conversationQuestion = ""

        do {
            let (answer, usage) = try await geminiService.askQuestion(
                messages: msgSnapshot,
                fileContent: fileContent,
                question: question,
                priorQA: priorQA
            )
            if let usage {
                sessionPromptTokens += usage.promptTokens
                sessionCompletionTokens += usage.completionTokens
            }
            let entry = QAEntry(question: question, answer: answer, tokenUsage: usage)
            if qaHistories[chatID] == nil { qaHistories[chatID] = [] }
            qaHistories[chatID]?.append(entry)
            saveQAHistory(for: chatID)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingQuestion = false
    }

    // MARK: - Debug

    /// Builds the prompt preamble that would be sent for a suggestion call —
    /// identical to GeminiService.generateSuggestion but without the style suffix.
    func buildDebugPrompt() -> String {
        let fileContent = combinedContext(for: selectedChat?.id)
        let ctx = reactionContext.isEmpty ? nil : reactionContext
        var prompt = ""

        if let fileContent, !fileContent.isEmpty {
            prompt += "Background context (conversation from another app or notes):\n\n"
            prompt += fileContent
            prompt += "\n\n---\n\n"
        }

        prompt += "Here is the recent conversation:\n\n"
        for message in messages.suffix(20) {
            prompt += "[\(message.messageDate)] \(message.sender): \(message.content)\n"
        }
        prompt += "\n"

        if let ctx, !ctx.isEmpty {
            prompt += "Context: \(ctx)\n\n"
        }

        prompt += "── [style prompt appended here — one per suggestion style] ──"
        return prompt
    }

    // MARK: - Utility

    func exportConversationToClipboard() {
        var parts: [String] = []

        if let chatID = selectedChat?.id, let context = chatContextFiles[chatID] {
            parts.append("=== Context: \(context.url.lastPathComponent) ===\n\(context.content)")
        }

        if !messages.isEmpty {
            let chatName = selectedChat?.displayName ?? "Conversation"
            var thread = "=== \(chatName) ===\n"
            for message in messages {
                thread += "[\(message.messageDate)] \(message.sender): \(message.content)\n"
            }
            parts.append(thread)
        }

        let history = currentQAHistory
        if !history.isEmpty {
            var qaSection = "=== Insights Q&A ===\n"
            for entry in history {
                qaSection += "Q: \(entry.question)\nA: \(entry.answer)\n\n"
            }
            parts.append(qaSection.trimmingCharacters(in: .newlines))
        }

        copyToClipboard(parts.joined(separator: "\n\n"))
    }

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
