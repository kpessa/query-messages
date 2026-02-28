//
//  ViewsInsightsChatView.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/26/26.
//

import SwiftUI

struct InsightsChatView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var useFullContext: Bool = false

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Insights", systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundStyle(Color.indigo)
                Spacer()
                if !viewModel.currentQAHistory.isEmpty {
                    Button {
                        viewModel.clearQAHistory()
                    } label: {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Chat history
            if viewModel.currentQAHistory.isEmpty && !viewModel.isLoadingQuestion {
                insightsEmptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.currentQAHistory) { entry in
                                QABubblePair(entry: entry)
                                    .id(entry.id)
                            }

                            if viewModel.isLoadingQuestion {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small).tint(Color.indigo)
                                    Text("Thinking…")
                                        .font(.caption)
                                        .foregroundStyle(Color.indigo)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .id("loading")
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: viewModel.currentQAHistory.count) { _, _ in
                        withAnimation {
                            if let last = viewModel.currentQAHistory.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isLoadingQuestion) { _, isLoading in
                        if isLoading {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Pinned input bar
            questionInputBar(questionText: $vm.conversationQuestion, useFullContext: $useFullContext)
        }
    }

    // MARK: - Empty state

    private var insightsEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lightbulb")
                .font(.system(size: 44))
                .foregroundStyle(Color.indigo.opacity(0.5))
            VStack(spacing: 6) {
                Text("Ask anything about this conversation")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Your questions and answers are saved per chat.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Input bar

    @ViewBuilder
    private func questionInputBar(questionText: Binding<String>, useFullContext: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            if viewModel.hasMoreMessages {
                HStack {
                    Spacer()
                    Toggle(isOn: useFullContext) {
                        let total = viewModel.selectedChat?.messageCount ?? 0
                        let loaded = viewModel.messages.count
                        Text(useFullContext.wrappedValue
                             ? "Full thread (\(total) msgs)"
                             : "Loaded only (\(loaded) msgs)")
                            .font(.caption2)
                            .foregroundStyle(useFullContext.wrappedValue ? Color.indigo : .secondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Color.indigo)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "Ask about this conversation…",
                    text: questionText,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit {
                    guard !viewModel.isLoadingQuestion else { return }
                    Task { await viewModel.askConversationQuestion(useFullContext: useFullContext.wrappedValue) }
                }

                Button {
                    Task { await viewModel.askConversationQuestion(useFullContext: useFullContext.wrappedValue) }
                } label: {
                    if viewModel.isLoadingQuestion {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.indigo)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(questionText.wrappedValue.isEmpty || viewModel.isLoadingQuestion || viewModel.messages.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - QA Bubble Pair

private struct QABubblePair: View {
    @Environment(AppViewModel.self) private var viewModel
    let entry: QAEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Question — right-aligned, solid indigo
            HStack {
                Spacer(minLength: 48)
                Text(entry.question)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)

            // Answer — left-aligned, tinted material
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(Color.indigo)
                    .padding(.top, 2)

                markdownText(entry.answer)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.indigo.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 12)

            if let usage = entry.tokenUsage {
                Text(formatTokenBadge(usage))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }
        }
        .contextMenu {
            Button {
                viewModel.copyToClipboard("Q: \(entry.question)\nA: \(entry.answer)")
            } label: {
                Label("Copy Q&A", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                viewModel.deleteQAEntry(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    InsightsChatView()
        .environment(AppViewModel())
        .frame(width: 380, height: 600)
}
