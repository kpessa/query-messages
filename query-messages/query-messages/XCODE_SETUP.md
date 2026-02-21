# Xcode Project Configuration Checklist

Follow these steps to properly configure your Xcode project for the iMessage Query app.

## 1. Add Files to Xcode Project

Make sure all the new files are added to your target:

### Models Group
- [ ] Models/Chat.swift
- [ ] Models/Message.swift
- [ ] Models/GeminiConversation.swift

### Services Group
- [ ] Services/DatabaseService.swift
- [ ] Services/ContactService.swift
- [ ] Services/GeminiService.swift
- [ ] Services/ExternalFileService.swift

### ViewModels Group
- [ ] ViewModels/AppViewModel.swift

### Views Group
- [ ] Views/ChatListView.swift
- [ ] Views/MessageThreadView.swift
- [ ] Views/AIPanelView.swift

### Root Level
- [ ] query-messages.entitlements
- [ ] README.md (optional)

### Files to Remove (from template)
- [ ] Item.swift (not needed - we don't use SwiftData)

## 2. Target Settings

### General Tab

**Identity**
- Display Name: `iMessage Query`
- Bundle Identifier: `com.yourname.query-messages`
- Version: `1.0`
- Build: `1`

**Deployment Info**
- Minimum macOS version: `14.0` (for @Observable support)

### Signing & Capabilities Tab

1. **Disable App Sandbox**
   - If "App Sandbox" capability exists, REMOVE it
   - Or ensure `com.apple.security.app-sandbox` is set to `false`

2. **Add Entitlements File**
   - Click the target
   - Build Settings tab
   - Search for "Code Signing Entitlements"
   - Set to: `query-messages.entitlements`

3. **Verify Entitlements File Contains**:
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <false/>
   <key>com.apple.security.personal-information.contacts</key>
   <true/>
   ```

### Build Settings Tab

Search for and verify these settings:

**Linking**
- [ ] Other Linker Flags: Add `-lsqlite3` if needed (usually automatic)

**Swift Compiler**
- [ ] Swift Language Version: `Swift 5` or later

## 3. Link System Frameworks

Ensure these frameworks are linked:

1. Select your target
2. Go to "Frameworks and Libraries"
3. Verify these are present (add with + button if missing):
   - [x] SwiftUI.framework
   - [x] Foundation.framework
   - [x] AppKit.framework
   - [x] Contacts.framework
   - [x] SQLite3.tbd (for database access)

## 4. Info.plist Additions

Add these keys to your Info.plist (if not already present):

```xml
<key>NSContactsUsageDescription</key>
<string>This app needs access to Contacts to display friendly names for message participants.</string>
```

## 5. Scheme Configuration

For running with environment variables:

1. Click on scheme dropdown → "Edit Scheme"
2. Select "Run" in left sidebar
3. Go to "Arguments" tab
4. Under "Environment Variables", add:
   - Name: `GEMINI_API_KEY`
   - Value: `your-api-key-here`

## 6. Build Phases

Verify "Compile Sources" includes all Swift files:

1. Select target → Build Phases
2. Expand "Compile Sources"
3. Ensure all .swift files are listed (except Item.swift if deleted)

## 7. File Organization (Recommended)

Organize files in Xcode's Project Navigator:

```
query-messages
├── 📁 App
│   ├── query_messagesApp.swift
│   ├── ContentView.swift
│   └── query-messages.entitlements
├── 📁 Models
│   ├── Chat.swift
│   ├── Message.swift
│   └── GeminiConversation.swift
├── 📁 Services
│   ├── DatabaseService.swift
│   ├── ContactService.swift
│   ├── GeminiService.swift
│   └── ExternalFileService.swift
├── 📁 ViewModels
│   └── AppViewModel.swift
└── 📁 Views
    ├── ChatListView.swift
    ├── MessageThreadView.swift
    └── AIPanelView.swift
```

## 8. Clean Build

After configuration:

1. Product → Clean Build Folder (Cmd+Shift+K)
2. Product → Build (Cmd+B)
3. Fix any compilation errors
4. Product → Run (Cmd+R)

## Common Build Issues

### Issue: "Cannot find 'AppViewModel' in scope"

**Solution**: Make sure AppViewModel.swift is added to your target
- Right-click file → Show File Inspector
- Check "Target Membership" checkbox

### Issue: SQLite3 linking errors

**Solution**: Add SQLite3 library
- Target → Build Phases → Link Binary With Libraries
- Click + → Add "libsqlite3.tbd"

### Issue: "App Sandbox" errors

**Solution**: Ensure sandbox is fully disabled
- Delete App Sandbox capability if present
- Verify entitlements file has `<false/>` for sandbox

### Issue: Contacts permission not working

**Solution**: Add usage description to Info.plist
```xml
<key>NSContactsUsageDescription</key>
<string>Access contacts to display names in conversations.</string>
```

## 9. Post-Build Configuration

After first successful build:

### Grant Full Disk Access
1. Build and run the app once
2. System Settings → Privacy & Security → Full Disk Access
3. Click + button
4. Navigate to: `~/Library/Developer/Xcode/DerivedData/query-messages-.../Build/Products/Debug/query-messages.app`
5. Add the app
6. Restart the app

### Set Up Gemini API Key

**Option 1: Environment Variable** (recommended for development)
- Already set in scheme (step 5 above)

**Option 2: Configuration File** (recommended for distribution)
```bash
echo "your-api-key-here" > ~/.gemini_api_key
```

## 10. Verification

Run through this checklist to verify everything works:

- [ ] App builds without errors
- [ ] App launches successfully
- [ ] Chat list appears (or Full Disk Access banner shows)
- [ ] Can select a chat and see messages
- [ ] Can search chats
- [ ] Contact names resolve (not just phone numbers)
- [ ] "Get AI Suggestion" button is enabled
- [ ] AI suggestions appear (if API key configured)
- [ ] Can copy suggestions to clipboard
- [ ] External file picker opens

## Troubleshooting Commands

```bash
# Check if app has Full Disk Access
sqlite3 ~/Library/Messages/chat.db "SELECT count(*) FROM chat;"

# Verify entitlements are applied
codesign -d --entitlements - /path/to/your.app

# Check sandbox status (should show "not sandboxed")
codesign -dvvv /path/to/your.app | grep -i sandbox
```

---

Once all checkboxes are complete, your app should be ready to use!
