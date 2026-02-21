# Fix: Invalid Redeclaration of 'ExternalFileService'

## Problem

You're seeing this error:
```
error: Invalid redeclaration of 'ExternalFileService'
```

## Root Cause

There are **two declarations** of `ExternalFileService` in your project. This happened because:

1. There's likely an existing file: `Services/ExternalFileService.swift` (possibly empty or stub)
2. I created a new file that may have been added as a duplicate

## Solution: Remove the Duplicate

### Step 1: Find the Duplicate Files

In Xcode Project Navigator, look for:
- `Services/ExternalFileService.swift`
- `ServicesExternalFileService.swift` (incorrect name)
- OR any other file containing `actor ExternalFileService` or `class ExternalFileService`

You should see TWO files that both define `ExternalFileService`.

### Step 2: Keep Only ONE

**Option A: You already have ExternalFileService.swift**

1. Right-click on `ServicesExternalFileService.swift` (the one I just created)
2. Choose "Delete" → "Move to Trash"
3. Open your existing `Services/ExternalFileService.swift`
4. Replace its contents with the code below

**Option B: You only see ServicesExternalFileService.swift**

1. Rename the file properly:
   - Right-click → "Delete" → "Move to Trash"
   - File → New → File → Swift File
   - Name it: `ExternalFileService.swift`
   - Make sure it's in the `Services` group
   - Add the code below

## Complete ExternalFileService Code

Here's the complete implementation to use:

```swift
//
//  ExternalFileService.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

enum ExternalFileError: Error, LocalizedError {
    case cannotReadFile(URL)
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .cannotReadFile(let url):
            return "Cannot read file at \(url.path)"
        case .invalidFormat:
            return "Invalid message file format"
        }
    }
}

actor ExternalFileService {
    
    /// Load messages from an external text file
    /// Expected format: [YYYY-MM-DD HH:MM:SS] SenderName: Message content
    func loadMessages(from url: URL) async throws -> [Message] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw ExternalFileError.cannotReadFile(url)
        }
        
        let lines = content.components(separatedBy: .newlines)
        var messages: [Message] = []
        
        for line in lines {
            guard !line.isEmpty else { continue }
            
            // Try to parse line format: [YYYY-MM-DD HH:MM:SS] SenderName: Message content
            if let message = parseLine(line) {
                messages.append(message)
            }
        }
        
        return messages
    }
    
    private func parseLine(_ line: String) -> Message? {
        // Pattern: [DATE TIME] SENDER: MESSAGE
        let pattern = #"^\[(.+?)\]\s*(.+?):\s*(.+)$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let nsString = line as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        
        guard match.numberOfRanges == 4 else {
            return nil
        }
        
        let dateString = nsString.substring(with: match.range(at: 1))
        let sender = nsString.substring(with: match.range(at: 2))
        let content = nsString.substring(with: match.range(at: 3))
        
        return Message(
            messageDate: dateString,
            sender: sender.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces)
        )
    }
}
```

## Step 3: Clean & Rebuild

After fixing the duplicate:

1. **Clean Build Folder**: ⌘⇧K (Command-Shift-K)
2. **Build**: ⌘B (Command-B)
3. **Run**: ⌘R (Command-R)

## Step 4: Verify Success

You should see:
- ✅ No build errors
- ✅ App launches with three-pane interface
- ✅ Chat list loads (after granting Full Disk Access)

## Additional Check: GeminiConversation

While you're at it, check if you also have a duplicate `GeminiConversation`:

**Look for:**
- `Models/GeminiConversation.swift`
- `ModelsGeminiConversation.swift`

If you see two, keep only the one in proper `Models/` folder structure.

### GeminiConversation Code (if needed)

```swift
//
//  GeminiConversation.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

/// Represents a part of a Gemini message
struct GeminiPart {
    let text: String
}

/// Represents a single message in a Gemini conversation
struct GeminiMessage {
    let role: String  // "user" or "model"
    let parts: [GeminiPart]
}

/// Manages the conversation history for Gemini API calls
@Observable
class GeminiConversation {
    var messages: [GeminiMessage] = []
    
    /// Add a user message to the conversation
    func addUserMessage(_ text: String) {
        let part = GeminiPart(text: text)
        let message = GeminiMessage(role: "user", parts: [part])
        messages.append(message)
    }
    
    /// Add a model response to the conversation
    func addModelResponse(_ text: String) {
        let part = GeminiPart(text: text)
        let message = GeminiMessage(role: "model", parts: [part])
        messages.append(message)
    }
    
    /// Reset the conversation
    func reset() {
        messages.removeAll()
    }
}
```

## Still Having Issues?

If you still see the error after removing duplicates:

1. **Check all Swift files manually**
   - Use Xcode's Find in Project (⌘⇧F)
   - Search for: `actor ExternalFileService`
   - You should find exactly ONE match

2. **Check Build Phases**
   - Select target → Build Phases → Compile Sources
   - Look for duplicate entries
   - Remove any duplicates

3. **Nuclear option: Remove all and re-add**
   - Remove ALL files related to ExternalFileService from project (not disk)
   - Create ONE new file: `ExternalFileService.swift`
   - Add it to Services group
   - Paste the code above
   - Add to target

---

Once fixed, your app should build successfully! 🎉
