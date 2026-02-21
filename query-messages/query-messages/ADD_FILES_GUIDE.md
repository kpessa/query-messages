# Adding New Files to Xcode Project

## 🆕 New Files Created

I've created these files to complete your MVP:

1. **ModelsGeminiConversation.swift** - AI conversation management
2. **ServicesExternalFileService.swift** - External message file parsing

## 📝 How to Add Them to Your Xcode Project

### Option 1: Drag & Drop (Easiest)

1. Locate the files in your project directory
2. Drag them into Xcode's Project Navigator (left sidebar)
3. In the dialog that appears:
   - ✅ Check "Copy items if needed"
   - ✅ Check "Add to targets: query-messages"
   - Click "Finish"

### Option 2: File Menu

1. In Xcode menu: **File → Add Files to "query-messages"...**
2. Navigate to and select the new files
3. Make sure "Add to targets" has your app target checked
4. Click "Add"

### Option 3: They Might Already Be There!

If you're working in a properly configured project, Xcode may have already detected these files. Check your Project Navigator for:

```
query-messages/
├── Models/
│   ├── Chat.swift
│   ├── Message.swift
│   └── GeminiConversation.swift        ← NEW
└── Services/
    ├── DatabaseService.swift
    ├── ContactService.swift
    ├── GeminiService.swift
    └── ExternalFileService.swift        ← NEW
```

## ✅ Verification

After adding the files, verify they're included:

1. Click on your project in Project Navigator (top item)
2. Select your app target
3. Go to "Build Phases" tab
4. Expand "Compile Sources"
5. Look for:
   - `GeminiConversation.swift`
   - `ExternalFileService.swift`

If they're listed there with checkmarks, you're good to go!

## 🔨 Build & Run

Once files are added:

1. Clean build folder: **⌘⇧K** (Command-Shift-K)
2. Build: **⌘B** (Command-B)
3. Run: **⌘R** (Command-R)

You should see no build errors! 🎉

## 🐛 If You Still See Errors

**"Cannot find type 'GeminiConversation'"**
- Make sure `GeminiConversation.swift` is added to your target
- Check it's in the "Compile Sources" build phase

**"Cannot find type 'ExternalFileService'"**
- Make sure `ExternalFileService.swift` is added to your target
- Check it's in the "Compile Sources" build phase

**"No such module 'UniformTypeIdentifiers'"**
- This should auto-import, but if not:
- Project → Target → Build Phases → Link Binary With Libraries
- Add "UniformTypeIdentifiers.framework"
