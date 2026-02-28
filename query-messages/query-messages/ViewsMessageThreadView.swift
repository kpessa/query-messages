//
//  MessageThreadView.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct MessageThreadView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var showingNotesEditor = false
    @State private var notesDraft = ""
    @State private var showingDebugPrompt = false
    @State private var debugPromptText = ""

    @ViewBuilder
    private var contactAvatar: some View {
        if let photo = viewModel.currentContactPhoto {
            Image(nsImage: photo)
                .resizable().scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(viewModel.selectedChat?.displayName.prefix(1).uppercased() ?? "?")
                        .font(.headline).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.selectedChat == nil {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("Select a conversation")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Contact header bar
                HStack(spacing: 12) {
                    contactAvatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedChat?.displayName ?? "")
                            .font(.headline).fontWeight(.semibold)
                        if viewModel.hasMoreMessages {
                            Text("Showing \(viewModel.messages.count) of \(viewModel.selectedChat?.messageCount ?? 0)")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(viewModel.messages.count) messages")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    // Context file attachment indicator / button
                    if let chatID = viewModel.selectedChat?.id,
                       let attached = viewModel.chatContextFiles[chatID] {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.caption)
                            Text(attached.url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Button {
                                viewModel.detachContextFile()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    } else {
                        Button {
                            openContextFilePanel()
                        } label: {
                            Label("Attach context", systemImage: "paperclip")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }

                    // Notes indicator / button
                    if let chatID = viewModel.selectedChat?.id,
                       viewModel.chatNotes[chatID] != nil {
                        HStack(spacing: 4) {
                            Button {
                                notesDraft = viewModel.chatNotes[chatID] ?? ""
                                showingNotesEditor = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "note.text")
                                        .font(.caption)
                                    Text("Date notes")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.borderless)
                            Button {
                                viewModel.saveNotes("", for: chatID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    } else {
                        Button {
                            notesDraft = viewModel.chatNotes[viewModel.selectedChat?.id ?? 0] ?? ""
                            showingNotesEditor = true
                        } label: {
                            Label("Add notes", systemImage: "note.text")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

                Divider()

                // Message thread
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                // Load More / Load All banner
                                if viewModel.hasMoreMessages {
                                    VStack(spacing: 6) {
                                        if viewModel.isLoadingMoreMessages {
                                            ProgressView("Loading older messages…")
                                                .font(.caption)
                                        } else {
                                            HStack(spacing: 12) {
                                                Button("Load More") {
                                                    Task { await viewModel.loadMoreMessages() }
                                                }
                                                Button("Load All Messages") {
                                                    Task { await viewModel.loadAllMessages() }
                                                }
                                                .foregroundStyle(.secondary)
                                            }
                                            .font(.caption)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(.quaternary)
                                    .cornerRadius(8)
                                }

                                // Messages
                                ForEach(viewModel.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if !viewModel.isLoadingMoreMessages, let last = viewModel.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onChange(of: viewModel.scrollTargetAfterLoad) { _, targetID in
                            if let id = targetID {
                                proxy.scrollTo(id, anchor: .top)
                                viewModel.scrollTargetAfterLoad = nil
                            }
                        }
                    }
                    
                    // Loading overlay
                    if viewModel.isLoadingMessages {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                    }
                }
                
                // Bottom toolbar
                Divider()
                
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.refreshMessages()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingMessages)

                    Button {
                        viewModel.exportConversationToClipboard()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.messages.isEmpty)
                    .help("Copy all messages (and attached context) to clipboard")

                    Button {
                        debugPromptText = viewModel.buildDebugPrompt()
                        showingDebugPrompt = true
                    } label: {
                        Image(systemName: "ladybug")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(viewModel.messages.isEmpty)
                    .help("Preview what would be sent to the AI")

                    Spacer()

                    Button {
                        Task {
                            await viewModel.getAISuggestion()
                        }
                    } label: {
                        Label("Get AI Suggestion", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.messages.isEmpty || viewModel.isLoadingAI)
                }
                .padding()
            }
        }
        .navigationTitle(viewModel.selectedChat?.displayName ?? "Messages")
        .sheet(isPresented: $showingDebugPrompt) {
            VStack(spacing: 0) {
                HStack {
                    Label("AI Prompt Preview", systemImage: "ladybug")
                        .font(.headline)
                    Spacer()
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(debugPromptText, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button("Done") { showingDebugPrompt = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                Divider()
                ScrollView {
                    Text(debugPromptText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .frame(width: 640, height: 500)
        }
        .sheet(isPresented: $showingNotesEditor) {
            VStack(spacing: 0) {
                HStack {
                    Text("Date Notes")
                        .font(.headline)
                    Spacer()
                    Button("Cancel") { showingNotesEditor = false }
                    Button("Save") {
                        if let chatID = viewModel.selectedChat?.id {
                            viewModel.saveNotes(notesDraft, for: chatID)
                        }
                        showingNotesEditor = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                Divider()
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $notesDraft)
                        .font(.body)
                        .padding(6)
                    if notesDraft.isEmpty {
                        Text("How did it go? What did you talk about? Anything you want to remember...")
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: 520, height: 380)
        }
    }

    private func openContextFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        panel.message = "Choose a context file for this conversation"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewModel.attachContextFile(url)
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer()
            }
            
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                // Sender name (if not from me)
                if !message.isFromMe {
                    Text(message.sender)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                
                // Message content
                Text(message.content)
                    .padding(10)
                    .background(message.isFromMe ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(message.isFromMe ? .white : .primary)
                    .cornerRadius(16)
                    .textSelection(.enabled)
                
                // Timestamp
                Text(message.messageDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 400, alignment: message.isFromMe ? .trailing : .leading)
            
            if !message.isFromMe {
                Spacer()
            }
        }
    }
}

#Preview {
    MessageThreadView()
        .environment(AppViewModel())
        .frame(width: 600, height: 800)
}
