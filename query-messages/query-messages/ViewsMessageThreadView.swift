//
//  MessageThreadView.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import SwiftUI

struct MessageThreadView: View {
    @Environment(AppViewModel.self) private var viewModel

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
                        Text("\(viewModel.messages.count) messages")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
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
                                // Truncation banner
                                if viewModel.messagesTruncated {
                                    HStack {
                                        Image(systemName: "info.circle")
                                        Text("Showing last \(viewModel.truncatedCount) messages")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding()
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
                        .onChange(of: viewModel.messages.count) { oldValue, newValue in
                            if let lastMessage = viewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
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
