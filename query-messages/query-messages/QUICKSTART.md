# Quick Start Guide

## 🎯 Getting Started in 10 Minutes

### Step 1: Organize Files in Xcode (3 min)

The files were created with flattened names. In Xcode, you'll need to organize them into groups:

**Current state (flat):**
```
ModelsChat.swift
ModelsMessage.swift
ModelsGeminiConversation.swift
ServicesDatabaseService.swift
ServicesContactService.swift
ServicesGeminiService.swift
ServicesExternalFileService.swift
ViewModelsAppViewModel.swift
ViewsChatListView.swift
ViewsMessageThreadView.swift
ViewsAIPanelView.swift
```

**What to do:**

1. **Create Groups in Xcode:**
   - Right-click project → New Group → "Models"
   - Right-click project → New Group → "Services"
   - Right-click project → New Group → "ViewModels"
   - Right-click project → New Group → "Views"

2. **Rename and Move Files:**

   In Xcode Project Navigator:
   
   - Select `ModelsChat.swift` → Rename to `Chat.swift` → Drag into Models group
   - Select `ModelsMessage.swift` → Rename to `Message.swift` → Drag into Models group
   - Select `ModelsGeminiConversation.swift` → Rename to `GeminiConversation.swift` → Drag into Models group
   
   - Select `ServicesDatabaseService.swift` → Rename to `DatabaseService.swift` → Drag into Services group
   - Select `ServicesContactService.swift` → Rename to `ContactService.swift` → Drag into Services group
   - Select `ServicesGeminiService.swift` → Rename to `GeminiService.swift` → Drag into Services group
   - Select `ServicesExternalFileService.swift` → Rename to `ExternalFileService.swift` → Drag into Services group
   
   - Select `ViewModelsAppViewModel.swift` → Rename to `AppViewModel.swift` → Drag into ViewModels group
   
   - Select `ViewsChatListView.swift` → Rename to `ChatListView.swift` → Drag into Views group
   - Select `ViewsMessageThreadView.swift` → Rename to `MessageThreadView.swift` → Drag into Views group
   - Select `ViewsAIPanelView.swift` → Rename to `AIPanelView.swift` → Drag into Views group

**OR - Quick Method:**
Just add all the files to your target (they'll work even with flat names). Xcode doesn't care about folder organization for compilation.

### Step 2: Configure Target (2 min)

1. **Select your target** in Xcode
2. **Build Settings** tab:
   - Search "Code Signing Entitlements"
   - Set to: `query-messages.entitlements`

3. **Info.plist** - Add this key:
   ```xml
   <key>NSContactsUsageDescription</key>
   <string>Access contacts to display names in conversations.</string>
   ```

4. **Verify all Swift files are in "Compile Sources"**:
   - Target → Build Phases → Compile Sources
   - All .swift files should be listed

### Step 3: Link SQLite3 (30 seconds)

1. Target → "Frameworks and Libraries"
2. Click + button
3. Search "sqlite3"
4. Add `libsqlite3.tbd`

### Step 4: Set Gemini API Key (1 min)

Get a free key from: https://aistudio.google.com/app/apikey

Then choose one:

```bash
# Method 1: Config file (recommended)
echo "your-api-key-here" > ~/.gemini_api_key

# Method 2: Environment variable
# Edit Scheme → Run → Arguments → Environment Variables
# Add: GEMINI_API_KEY = your-api-key-here
```

### Step 5: Build (1 min)

```bash
Cmd+Shift+K  # Clean
Cmd+B        # Build
```

Fix any errors (usually just "add to target" checkboxes)

### Step 6: Run & Grant Access (3 min)

```bash
Cmd+R  # Run
```

1. **Grant Contacts Access** when prompted
2. **Grant Full Disk Access**:
   - Open System Settings → Privacy & Security → Full Disk Access
   - Click + → Navigate to your app in DerivedData
   - Add it
   - Restart app

**App location:**
```
~/Library/Developer/Xcode/DerivedData/query-messages-{hash}/Build/Products/Debug/query-messages.app
```

## 🎉 You're Done!

You should now see:
- Chat list on the left
- Message thread in the center
- AI panel on the right

## 🐛 Quick Troubleshooting

### "Cannot find 'Chat' in scope"
**Fix:** Right-click file → Show File Inspector → Check "Target Membership"

### "Cannot open database"
**Fix:** Grant Full Disk Access in System Settings

### "Gemini API is not configured"
**Fix:** Set GEMINI_API_KEY or create ~/.gemini_api_key file

### Blank chat list
**Fix:** Either no Full Disk Access, or no iMessage conversations exist

### Build errors about SQLite
**Fix:** Add libsqlite3.tbd in "Frameworks and Libraries"

## 📱 Test Workflow

1. Launch app
2. See chat list populate
3. Search for a contact
4. Click a chat → messages appear
5. Click "Get AI Suggestion"
6. Review suggestion
7. Click "Shorter" → see refined suggestion
8. Click copy icon → paste somewhere to verify

## 🎨 Customization Ideas

Once it's working, you might want to:

1. **Change Colors:**
   - Edit `MessageBubble` in MessageThreadView.swift
   - Change `.blue` to your preferred color

2. **Adjust Message Limit:**
   - Edit `DatabaseService.fetchMessages(for:limit:)`
   - Default is 100 messages

3. **Modify AI Prompts:**
   - Edit `GeminiService.generateSuggestion()`
   - Customize the system prompt

4. **Add Quick Actions:**
   - Edit `quickActionButtons` in AIPanelView.swift
   - Add new buttons with custom prompts

## 📚 Next Steps

- Read README.md for full feature documentation
- Check API_REFERENCE.md to understand the codebase
- Review XCODE_SETUP.md for detailed configuration

## 🚀 You're Ready!

The app is now fully functional with:
✅ iMessage database reading
✅ Contact name resolution
✅ AI-powered suggestions
✅ Follow-up conversations
✅ External file loading
✅ Beautiful three-pane UI

Enjoy your new iMessage Query app!
