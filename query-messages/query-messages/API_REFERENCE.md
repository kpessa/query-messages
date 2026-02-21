# API Reference

Quick reference for the main APIs and patterns used in this app.

## AppViewModel - Main State Container

```swift
@Observable @MainActor
class AppViewModel {
    // MARK: State Properties (all observed by SwiftUI)
    
    var allChats: [Chat]              // All loaded chats
    var selectedChat: Chat?           // Currently selected chat
    var messages: [Message]           // Messages for selected chat
    var aiSuggestion: String          // Latest AI suggestion
    var searchText: String            // Search filter text
    var errorMessage: String?         // Current error (if any)
    
    // MARK: Loading States
    
    var isLoadingChats: Bool
    var isLoadingMessages: Bool
    var isLoadingAI: Bool
    
    // MARK: Computed Properties
    
    var filteredChats: [Chat]         // Chats matching searchText
    var recentChats: [Chat]           // Top 10 by date
    var activeChats: [Chat]           // Top 10 by message count
    
    // MARK: Actions
    
    func loadChats() async
    func selectChat(_ chat: Chat) async
    func loadMessages(for chatID: Int64) async
    func refreshMessages() async
    func loadExternalFile(_ url: URL) async
    
    func getAISuggestion() async
    func sendFollowUp() async
    func quickAction(_ action: String) async
    
    func copyToClipboard(_ text: String)
    func openSystemSettings()
}
```

## Usage in Views

### Environment Injection

```swift
// In App
@main
struct query_messagesApp: App {
    @State private var viewModel = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)  // ✅ Inject here
        }
    }
}

// In Views
struct MyView: View {
    @Environment(AppViewModel.self) private var viewModel  // ✅ Receive here
    
    var body: some View {
        @Bindable var vm = viewModel  // ✅ For two-way bindings
        
        TextField("Search", text: $vm.searchText)
    }
}
```

## DatabaseService API

```swift
actor DatabaseService {
    // Get all chats from iMessage database
    func getAvailableChats() async throws -> [Chat]
    
    // Get messages for a specific chat
    func fetchMessages(for chatID: Int64, limit: Int = 100) async throws -> [Message]
    
    // Check if database is accessible
    func checkDatabaseAccess() async -> Bool
}
```

### Usage

```swift
let db = DatabaseService()

// Load chats
let chats = try await db.getAvailableChats()

// Load messages
let messages = try await db.fetchMessages(for: chatID, limit: 50)

// Check access
let hasAccess = await db.checkDatabaseAccess()
if !hasAccess {
    // Show Full Disk Access banner
}
```

## ContactService API

```swift
actor ContactService {
    // Request Contacts permission
    func requestAuthorization() async -> Bool
    
    // Resolve a phone number or email to contact name
    func resolve(_ identifier: String) async -> String
    
    // Resolve multiple identifiers at once
    func resolveMultiple(_ identifiers: [String]) async -> [String: String]
}
```

### Usage

```swift
let contacts = ContactService()

// Request permission (call once at launch)
let granted = await contacts.requestAuthorization()

// Resolve individual contact
let name = await contacts.resolve("+1234567890")
// Returns: "John Smith" or formatted number

// Resolve multiple
let names = await contacts.resolveMultiple(["+1234567890", "jane@example.com"])
// Returns: ["+1234567890": "John Smith", "jane@example.com": "Jane Doe"]
```

## GeminiService API

```swift
actor GeminiService {
    init() throws  // Throws if API key not found
    
    // Make API call with conversation history
    func call(conversation: GeminiConversation) async throws -> String
    
    // High-level convenience method
    func generateSuggestion(messages: [Message], context: String?) async throws -> String
}
```

### Usage

```swift
// Initialize (provide API key via env var or ~/.gemini_api_key)
let gemini = try GeminiService()

// Simple suggestion
let suggestion = try await gemini.generateSuggestion(
    messages: messages,
    context: "Keep it professional"
)

// Conversation with follow-ups
let conversation = GeminiConversation()
conversation.addUserMessage("Suggest a response to these messages...")

let response1 = try await gemini.call(conversation: conversation)
conversation.addModelResponse(response1)

conversation.addUserMessage("Make it shorter")
let response2 = try await gemini.call(conversation: conversation)
```

## GeminiConversation API

```swift
@Observable
class GeminiConversation {
    var messages: [GeminiMessage]
    
    func addUserMessage(_ text: String)
    func addModelResponse(_ text: String)
    func reset()
}
```

### Usage

```swift
let conversation = GeminiConversation()

// Add messages
conversation.addUserMessage("Hello!")
conversation.addModelResponse("Hi there!")

// Clear history
conversation.reset()
```

## ExternalFileService API

```swift
actor ExternalFileService {
    // Parse messages from text file
    func loadMessages(from url: URL) throws -> [Message]
}
```

### Usage

```swift
let fileService = ExternalFileService()

let url = URL(fileURLWithPath: "/path/to/messages.txt")
let messages = try await fileService.loadMessages(from: url)
```

### Expected File Format

```
[MM/DD/YY, HH:MM AM/PM] Sender Name: Message text
[2/21/26, 9:00 AM] John Smith: Hello!
[2/21/26, 9:01 AM] Me: Hi there!
```

## Data Models

### Chat

```swift
struct Chat: Identifiable, Hashable {
    let id: Int64                    // Database ROWID
    let participants: [String]       // Phone numbers or emails (resolved to names)
    let messageCount: Int64          // Total messages in chat
    let lastMessageDate: String      // Formatted date string
    let lastMessageDateRaw: Int64    // Raw timestamp for sorting
    
    var displayName: String          // Computed: joined participant names
}
```

### Message

```swift
struct Message: Identifiable {
    let id: UUID                     // Generated UUID
    let messageDate: String          // Formatted date string
    let sender: String               // "Me" or contact name
    let content: String              // Message text
    
    var isFromMe: Bool               // Computed: sender == "Me"
}
```

## Error Handling

### Standard Pattern

```swift
// In ViewModel
func loadData() async {
    errorMessage = nil
    isLoading = true
    
    do {
        let data = try await service.fetchData()
        // Update state
    } catch {
        errorMessage = error.localizedDescription
    }
    
    isLoading = false
}

// In View
.alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
    Button("OK") {
        viewModel.errorMessage = nil
    }
} message: {
    Text(viewModel.errorMessage ?? "")
}
```

## Common Patterns

### Task-based Async Actions

```swift
Button("Load Chats") {
    Task {
        await viewModel.loadChats()
    }
}
```

### Two-Way Bindings with @Bindable

```swift
struct MyView: View {
    @Environment(AppViewModel.self) private var viewModel
    
    var body: some View {
        @Bindable var vm = viewModel  // Required for $ bindings
        
        TextField("Search", text: $vm.searchText)
        //                         ^ $ binding works
    }
}
```

### Progress Indicators

```swift
ZStack {
    // Content
    MyContentView()
    
    // Loading overlay
    if viewModel.isLoadingMessages {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
    }
}
```

### List Selection Binding

```swift
@Bindable var vm = viewModel

List(selection: $vm.selectedChat) {
    ForEach(chats) { chat in
        ChatRow(chat: chat)
            .tag(chat)
    }
}
.onChange(of: viewModel.selectedChat) { old, new in
    if let chat = new {
        Task {
            await viewModel.selectChat(chat)
        }
    }
}
```

## Threading Notes

- All `@MainActor` code runs on main thread (safe for UI)
- All `actor` code is isolated (thread-safe)
- Use `Task { await ... }` to call async functions from sync context
- SwiftUI automatically handles `@Observable` updates on main thread

## File System Access

### Required for iMessage Database

```swift
// Default path
~/Library/Messages/chat.db

// Check access
FileManager.default.isReadableFile(atPath: dbPath)

// If false, user needs to grant Full Disk Access in System Settings
```

### NSOpenPanel for External Files

```swift
let panel = NSOpenPanel()
panel.allowsMultipleSelection = false
panel.canChooseFiles = true
panel.allowedContentTypes = [.plainText]

panel.begin { response in
    if response == .OK, let url = panel.url {
        // Use url
    }
}
```

---

This API reference covers the main interfaces you'll interact with when extending or maintaining the app.
