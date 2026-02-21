# iMessage Query - macOS App

A native macOS application that helps you browse your iMessage conversations and get AI-powered response suggestions using Google's Gemini API.

## Features

- **Three-Pane Interface**: Browse chats, view message threads, and get AI suggestions all in one window
- **Contact Integration**: Automatically resolves phone numbers to contact names
- **AI-Powered Suggestions**: Get thoughtful response suggestions using Gemini AI
- **External File Support**: Import message archives from text files
- **Full-Text Search**: Quickly find conversations
- **Native macOS Design**: Built with SwiftUI for a modern, native experience

## Architecture

```
query-messages/
├── Models/
│   ├── Chat.swift                  # Chat data structure
│   ├── Message.swift               # Message data structure
│   └── GeminiConversation.swift    # AI conversation state
├── Services/
│   ├── DatabaseService.swift       # SQLite queries for chat.db
│   ├── ContactService.swift        # Contact resolution & caching
│   ├── GeminiService.swift         # Gemini API integration
│   └── ExternalFileService.swift   # External message file parsing
├── ViewModels/
│   └── AppViewModel.swift          # Centralized app state (@Observable)
├── Views/
│   ├── ChatListView.swift          # Left pane: chat list
│   ├── MessageThreadView.swift     # Center pane: messages
│   └── AIPanelView.swift           # Right pane: AI suggestions
├── ContentView.swift               # NavigationSplitView container
├── query_messagesApp.swift         # App entry point
└── query-messages.entitlements     # Permissions configuration
```

## Setup

### 1. Xcode Configuration

1. Open the project in Xcode
2. Select your target and go to "Signing & Capabilities"
3. Add the entitlements file: `query-messages.entitlements`
4. Ensure these settings:
   - **App Sandbox**: `false` (disabled)
   - **Contacts**: `true` (enabled)

### 2. Full Disk Access

Since the app needs to read `~/Library/Messages/chat.db`, you must grant Full Disk Access:

1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Navigate to your built app and add it
4. Restart the app

The app will show a banner if Full Disk Access is not granted.

### 3. Gemini API Key

To use AI suggestions, you need a Gemini API key:

1. Get a free API key from [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Choose one of these methods to provide the key:

   **Option A: Environment Variable**
   ```bash
   export GEMINI_API_KEY="your-api-key-here"
   ```

   **Option B: Configuration File**
   ```bash
   echo "your-api-key-here" > ~/.gemini_api_key
   ```

### 4. Build & Run

```bash
# From Xcode
Cmd+B to build
Cmd+R to run

# From command line
xcodebuild -scheme query-messages -configuration Debug
```

## Usage

### Basic Workflow

1. **Launch the app** - Chats will automatically load from your iMessage database
2. **Search** - Use the search field to filter conversations
3. **Select a chat** - Click any conversation to view messages
4. **Get AI suggestion** - Click "Get AI Suggestion" to receive a response suggestion
5. **Refine** - Use quick actions (Shorter, More Casual) or ask follow-up questions
6. **Copy** - Click the copy button to add the suggestion to your clipboard

### External Files

You can import message archives in this format:

```
[2/21/26, 2:30 PM] John Doe: Hey, how are you?
[2/21/26, 2:31 PM] Me: I'm doing great, thanks!
[2/21/26, 2:32 PM] John Doe: Want to grab coffee later?
```

1. Click **Load External File** in the toolbar
2. Select your `.txt` file
3. Messages will merge with the current conversation

### Keyboard Shortcuts

- `Cmd+R` - Refresh chat list
- `Cmd+Shift+G` - Get AI suggestion

## Project Structure Details

### Models

- **Chat**: Represents a conversation with participants, message count, and last message date
- **Message**: Individual message with sender, content, and timestamp
- **GeminiConversation**: Maintains conversation history with AI for follow-up questions

### Services (All using async/await)

- **DatabaseService**: 
  - Reads from `~/Library/Messages/chat.db` using SQLite3
  - Converts Apple's Core Data timestamps
  - Decodes attributed string messages
  
- **ContactService**: 
  - Uses CNContactStore for contact lookups
  - In-memory caching to avoid repeated queries
  - Phone number and email resolution
  
- **GeminiService**: 
  - REST API integration with Gemini
  - URLSession-based async networking
  - Structured conversation management
  
- **ExternalFileService**: 
  - Parses text files in message export format
  - Regex-based message parsing

### ViewModel Pattern

`AppViewModel` is the single source of truth, marked with `@Observable` and `@MainActor`:

- All UI state lives here
- All async operations coordinated here
- Services are private implementation details
- Views observe and trigger actions

## Troubleshooting

### "Cannot open database" Error

**Cause**: App doesn't have Full Disk Access

**Solution**: 
1. Open System Settings → Privacy & Security → Full Disk Access
2. Add your app to the list
3. Restart the app

### "Gemini API is not configured" Error

**Cause**: API key not found

**Solution**:
```bash
# Set environment variable
export GEMINI_API_KEY="your-key"

# OR create config file
echo "your-key" > ~/.gemini_api_key
```

### Contacts Not Resolving

**Cause**: Contacts permission not granted

**Solution**: 
1. Open System Settings → Privacy & Security → Contacts
2. Enable access for your app
3. Restart the app

### No Chats Appearing

**Possible causes**:
1. No iMessage conversations exist
2. Full Disk Access not granted
3. Database path is incorrect (non-standard Messages location)

## Development Notes

### Threading Model

- All database and network operations use Swift Concurrency (async/await)
- No DispatchSemaphore or blocking calls
- UI updates are guaranteed to run on main actor
- Services are implemented as `actor` for thread safety

### Sandbox Disabled

This is a **personal development tool** not intended for App Store distribution. The sandbox is disabled to allow direct file system access to the Messages database without requiring file picker dialogs on every launch.

### SwiftData Removed

The original template used SwiftData, but this app doesn't persist its own data—it reads from the iMessage database directly. The `Item.swift` model can be safely deleted.

## Future Enhancements

Potential improvements:

- [ ] Message export functionality
- [ ] Advanced search (by date, sender, content)
- [ ] Multiple AI provider support (OpenAI, Claude, etc.)
- [ ] Custom AI prompt templates
- [ ] Attachment preview support
- [ ] Group chat participant avatars
- [ ] Message statistics and analytics
- [ ] Dark mode refinements
- [ ] Configurable message limit

## License

This is a personal development tool. Use at your own risk. Ensure you comply with Apple's terms of service regarding access to iMessage data.

## Privacy

- All data stays local on your Mac
- API calls to Gemini include only message content (no metadata)
- Contact information is cached in memory only (not persisted)
- No analytics or telemetry

---

**Built with SwiftUI, Swift Concurrency, and modern macOS development practices.**
