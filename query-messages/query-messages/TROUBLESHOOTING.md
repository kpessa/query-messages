# Troubleshooting Guide

Common issues and their solutions when building and running the iMessage Query app.

## Build Errors

### ❌ "Cannot find 'Chat' / 'Message' / 'AppViewModel' in scope"

**Cause:** Files not added to build target

**Solution:**
1. In Xcode, right-click the file
2. Select "Show File Inspector" (⌥⌘1)
3. Check the box under "Target Membership"
4. Rebuild (⌘B)

**Quick Fix All:**
1. Select all new .swift files
2. File Inspector → Target Membership
3. Check your app target for all

---

### ❌ "Undefined symbol: _sqlite3_open"

**Cause:** SQLite3 library not linked

**Solution:**
1. Select your target
2. "Frameworks and Libraries" section
3. Click + button
4. Search for "sqlite3"
5. Add `libsqlite3.tbd`
6. Clean build folder (⌘⇧K)
7. Rebuild (⌘B)

---

### ❌ Sandbox permission errors

**Cause:** Entitlements not configured correctly

**Solution:**
1. Target → Build Settings
2. Search "Code Signing Entitlements"
3. Set to: `query-messages.entitlements`
4. Verify entitlements file contains:
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

---

### ❌ "Command CodeSign failed with a nonzero exit code"

**Cause:** Code signing issues

**Solution:**
1. Target → Signing & Capabilities
2. Check "Automatically manage signing"
3. Select your team
4. Clean build folder (⌘⇧K)
5. Rebuild (⌘B)

**Alternative:**
- Delete DerivedData: `~/Library/Developer/Xcode/DerivedData`
- Restart Xcode
- Rebuild

---

## Runtime Errors

### ❌ "Cannot open database" / "Full Disk Access Required" banner

**Cause:** App doesn't have permission to read iMessage database

**Solution:**
1. Open **System Settings**
2. **Privacy & Security** → **Full Disk Access**
3. Click the **🔒** lock to make changes
4. Click **+** button
5. Navigate to your built app:
   ```
   ~/Library/Developer/Xcode/DerivedData/query-messages-{random}/Build/Products/Debug/query-messages.app
   ```
6. Select and add it
7. **Quit** and **restart** the app

**Verification:**
```bash
# In Terminal - this should return a number if access granted
sqlite3 ~/Library/Messages/chat.db "SELECT count(*) FROM chat;"
```

---

### ❌ Blank chat list / No conversations appear

**Possible Causes:**

**1. Full Disk Access not granted**
- See above solution

**2. No iMessage conversations exist**
- Send yourself a test message via iMessage
- Refresh the app (⌘R)

**3. Database path incorrect**
- Check Console logs for actual error
- Default path: `~/Library/Messages/chat.db`
- Verify file exists:
  ```bash
  ls -la ~/Library/Messages/chat.db
  ```

---

### ❌ "Gemini API is not configured" error

**Cause:** API key not found

**Solution - Method 1 (Config File):**
```bash
# Create config file
echo "your-actual-api-key" > ~/.gemini_api_key

# Verify it was created
cat ~/.gemini_api_key
```

**Solution - Method 2 (Environment Variable):**
1. In Xcode: Product → Scheme → Edit Scheme (⌘<)
2. Run → Arguments tab
3. Environment Variables section
4. Click + button
5. Add:
   - Name: `GEMINI_API_KEY`
   - Value: `your-actual-api-key`
6. Close and rebuild

**Get API Key:**
https://aistudio.google.com/app/apikey (free)

---

### ❌ Phone numbers showing instead of contact names

**Cause:** Contacts permission not granted

**Solution:**
1. Open **System Settings**
2. **Privacy & Security** → **Contacts**
3. Enable access for your app
4. Restart app

**Also check Info.plist has:**
```xml
<key>NSContactsUsageDescription</key>
<string>Access contacts to display names in conversations.</string>
```

---

### ❌ App crashes on launch

**Check Console Logs:**
1. Open Console.app
2. Select your Mac device
3. Filter by your app name
4. Look for errors

**Common crash causes:**

**1. Missing API key (Gemini):**
- App should handle gracefully, but early versions might crash
- Add API key or comment out Gemini initialization

**2. Database access exception:**
- Grant Full Disk Access

**3. Missing framework:**
- Check all frameworks are linked in Build Phases

---

### ❌ Messages show as "(Media or attachment)"

**This is expected behavior.**

The current implementation doesn't decode image/video attachments. Only text messages are shown.

**Possible enhancement:**
- Add attachment handling in `DatabaseService.getMessageTextSync()`
- Query the `attachment` table
- Display file names or thumbnails

---

### ❌ AI suggestions timeout or fail

**Possible causes:**

**1. No internet connection**
- Gemini API requires internet
- Check network connectivity

**2. Invalid API key**
- Verify key is correct
- Check it hasn't expired
- Generate new key if needed

**3. API quota exceeded**
- Gemini free tier has limits
- Check usage at Google AI Studio
- Wait for quota reset

**4. Messages too long**
- Current implementation sends last 20 messages
- Very long conversations might exceed token limits
- Reduce message count in `AppViewModel.buildPrompt()`

---

## UI Issues

### ❌ Three-pane layout collapsed or narrow

**Cause:** Window too small

**Solution:**
- Resize window wider (minimum 1200px recommended)
- App sets minimum in code but macOS may override
- Check `query_messagesApp.swift`: `.frame(minWidth: 1200, minHeight: 700)`

---

### ❌ Messages not scrolling to bottom

**Cause:** ScrollViewReader timing issue

**Solution:**
- Already implemented in MessageThreadView
- If still occurs, try manually scrolling
- Report specific reproduction steps

---

### ❌ "Copied!" toast not appearing

**Check:**
1. `AppViewModel.showCopiedToast` is being set
2. Toast overlay is in AIPanelView
3. No other views blocking it

**Workaround:**
- Copy still works (check clipboard)
- Toast is just visual feedback

---

## Performance Issues

### ❌ Chat list slow to load

**Possible causes:**

**1. Many conversations**
- Expected for accounts with hundreds of chats
- Database query is synchronous
- Consider adding pagination

**2. Contact resolution overhead**
- Each contact lookup queries CNContactStore
- Caching helps after first load
- Consider pre-loading common contacts

**Solution:**
- Wait for initial load (only once per launch)
- Subsequent loads use cache

---

### ❌ App uses high CPU

**Check:**
- Are you actively using AI suggestions?
- AI calls are expected to use CPU
- Should return to idle after suggestion completes

**If persistent:**
- Check Console for infinite loops
- Verify no repeated database queries
- Report issue with reproduction steps

---

## Data Issues

### ❌ External file not loading

**Verify file format:**
```
[2/21/26, 9:00 AM] Sender Name: Message text
[2/21/26, 9:01 AM] Me: Another message
```

**Requirements:**
- Each message on new line
- Format: `[Date] Sender: Content`
- Date format: `MM/DD/YY, HH:MM AM/PM`

**Test with provided sample:**
- Use `sample_messages.txt` included in repo
- Should load successfully

---

### ❌ Messages in wrong order

**Cause:** External file merge or date parsing issue

**Check:**
- Dates in external file are parseable
- Messages have valid timestamps
- Database query sorts by date DESC

---

## Permission Issues

### ❌ macOS Gatekeeper blocking app

**Cause:** App not notarized (expected for development)

**Solution:**
1. Right-click app
2. Select "Open"
3. Click "Open" in warning dialog
4. Or: System Settings → Privacy & Security → "Open Anyway"

---

### ❌ "App is damaged and can't be opened"

**Cause:** Quarantine attribute on built app

**Solution:**
```bash
# Remove quarantine
xattr -cr /path/to/query-messages.app

# Verify
xattr -l /path/to/query-messages.app
```

---

## Development Issues

### ❌ SwiftUI previews not working

**Expected:** Previews require extensive setup for this app

**Reason:**
- DatabaseService needs real database
- ContactService needs permissions
- GeminiService needs API key

**Workaround:**
- Use mock data in previews
- Or just run the full app (⌘R)

---

### ❌ Can't find built app for Full Disk Access

**Location:**
```bash
# Open DerivedData
open ~/Library/Developer/Xcode/DerivedData

# Find your app folder (starts with "query-messages-")
cd query-messages-{random-string}/Build/Products/Debug

# App is here
ls -la query-messages.app
```

**Quick Command:**
```bash
# Open directly in Finder
open ~/Library/Developer/Xcode/DerivedData/query-messages*/Build/Products/Debug/
```

---

## Testing Checklist

Use this to systematically verify functionality:

- [ ] App builds without errors (⌘B)
- [ ] App launches without crashing (⌘R)
- [ ] Chat list populates with conversations
- [ ] Search filters chats correctly
- [ ] Selecting chat loads messages
- [ ] Messages show in correct order (oldest → newest)
- [ ] Contact names appear (not phone numbers)
- [ ] Message bubbles colored correctly (blue/gray)
- [ ] Timestamps display on all messages
- [ ] "Get AI Suggestion" button enabled
- [ ] AI suggestion appears in right pane
- [ ] "Shorter" quick action works
- [ ] "More Casual" quick action works
- [ ] Follow-up question field works
- [ ] Copy button copies to clipboard
- [ ] "Copied!" toast appears
- [ ] External file picker opens
- [ ] External file loads and merges messages
- [ ] Refresh button reloads messages
- [ ] Full Disk Access banner appears if not granted
- [ ] "Open Settings" button opens System Settings
- [ ] Error alerts show for failures
- [ ] ⌘R keyboard shortcut refreshes
- [ ] ⌘⇧G keyboard shortcut gets AI suggestion

---

## Getting Help

If none of these solutions work:

1. **Check Console Logs:**
   - Console.app → Your Mac → Filter: "query-messages"
   - Look for errors or warnings

2. **Verify Setup:**
   - Review XCODE_SETUP.md checklist
   - Ensure all steps completed

3. **Test Components Individually:**
   - Database access: `sqlite3 ~/Library/Messages/chat.db "SELECT count(*) FROM chat;"`
   - Contacts: Check System Settings permissions
   - Gemini: Test API key with curl

4. **Clean Build:**
   ```bash
   # In Xcode
   Product → Clean Build Folder (⌘⇧K)
   
   # Delete DerivedData
   rm -rf ~/Library/Developer/Xcode/DerivedData
   
   # Rebuild
   ⌘B
   ```

5. **Document the Issue:**
   - Exact error message
   - Steps to reproduce
   - Console logs
   - macOS version
   - Xcode version

---

## Known Limitations (Not Bugs)

These are expected behavior:

✅ **Attachments show as "(Media or attachment)"**
- Only text messages decoded
- Image/video support not implemented

✅ **No live updates**
- Manual refresh required for new messages
- Database polling not implemented

✅ **No message editing history**
- Edited messages show latest version only

✅ **No Tapback reactions**
- Tapbacks not shown
- Could be added in future

✅ **Gemini API required for AI features**
- No offline AI mode
- Requires internet connection

---

**Most issues are related to permissions. Start there!**
