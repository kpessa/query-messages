//
//
//  ChatListView.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ChatListView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Search field
            TextField("Search conversations", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            // Chat list
            if viewModel.isLoadingChats {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.allChats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No conversations found")
                        .foregroundStyle(.secondary)
                    Button("Load Chats") {
                        Task {
                            await viewModel.loadChats()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Sort toggle
                Picker("Sort", selection: $vm.sortMode) {
                    Text("Recent").tag(SortMode.recent)
                    Text("Popular").tag(SortMode.popular)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 6)

                List(selection: $vm.selectedChat) {
                    if !viewModel.pinnedChats.isEmpty {
                        Section {
                            ForEach(viewModel.pinnedChats) { chat in
                                ChatRow(chat: chat)
                                    .tag(chat)
                                    .contextMenu { pinContextMenu(chat) }
                            }
                        } header: {
                            Label("Pinned", systemImage: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section(viewModel.sortMode == .recent ? "Most Recent" : "Most Active") {
                        ForEach(viewModel.unpinnedChats) { chat in
                            ChatRow(chat: chat)
                                .tag(chat)
                                .contextMenu { pinContextMenu(chat) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: viewModel.selectedChat) { oldValue, newValue in
                    if let chat = newValue {
                        Task {
                            await viewModel.selectChat(chat)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.loadChats()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingChats)
            }

            ToolbarItem {
                Button {
                    openExternalFile()
                } label: {
                    Label("Load External File", systemImage: "doc.text")
                }
            }
        }
        .task {
            if viewModel.allChats.isEmpty {
                await viewModel.loadChats()
            }
        }
    }

    @ViewBuilder
    private func pinContextMenu(_ chat: Chat) -> some View {
        Button {
            viewModel.togglePin(chat)
        } label: {
            Label(chat.isPinned ? "Unpin" : "Pin", systemImage: chat.isPinned ? "pin.slash" : "pin")
        }
    }

    private func openExternalFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.plainText]
        panel.message = "Choose a message export file"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await viewModel.loadExternalFile(url)
                }
            }
        }
    }
}

struct ChatRow: View {
    @Environment(AppViewModel.self) private var viewModel
    let chat: Chat

    var body: some View {
        HStack(spacing: 10) {
            chatAvatar

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(chat.displayName)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Spacer()

                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if chat.lastMessageDateRaw > recentThreshold {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack {
                    Text("\(chat.messageCount) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(chat.lastMessageDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .task(id: chat.id) {
            await viewModel.loadChatPhoto(for: chat)
        }
    }

    @ViewBuilder
    private var chatAvatar: some View {
        if let photo = viewModel.chatPhotos[chat.id] {
            Image(nsImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(chat.displayName.prefix(1).uppercased())
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    private var recentThreshold: Int64 {
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let appleEpoch = Date(timeIntervalSinceReferenceDate: 0)
        let interval = oneDayAgo.timeIntervalSince(appleEpoch)
        return Int64(interval * 1_000_000_000)
    }
}

#Preview {
    ChatListView()
        .environment(AppViewModel())
        .frame(width: 300, height: 600)
}
