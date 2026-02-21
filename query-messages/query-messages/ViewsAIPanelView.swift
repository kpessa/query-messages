//
//  AIPanelView.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import SwiftUI

// MARK: - Accent color per style
// Named `styleAccentColor` to avoid conflict with the View.accentColor(_:) instance method.
private func styleAccentColor(for styleID: String) -> Color {
    switch styleID {
    case "normal":       return .blue
    case "keepgoing":    return .orange
    case "witty":        return .purple
    case "playful":      return .green
    case "emoji":        return Color(red: 0.85, green: 0.70, blue: 0.0)
    case "pirate":       return Color(red: 0.72, green: 0.10, blue: 0.10)
    case "connect_dots": return Color(red: 0.0,  green: 0.60, blue: 0.65)   // teal
    case "real_talk":    return Color(red: 0.30, green: 0.30, blue: 0.80)   // indigo
    case "pull_thread":  return Color(red: 0.20, green: 0.55, blue: 0.35)   // forest green
    default:             return .accentColor
    }
}

struct AIPanelView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            if viewModel.aiSuggestions.isEmpty && !viewModel.isLoadingAI {
                emptyStateView
            } else {
                // Scrollable content: context input + card grid
                ScrollView {
                    VStack(spacing: 16) {
                        contextInputView(text: $vm.reactionContext)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 12) {
                            ForEach(viewModel.responseStyles) { style in
                                StyleCard(style: style)
                            }
                        }
                    }
                    .padding()
                }

                // Regenerate button pinned at bottom
                Divider()
                regenerateButton
            }

            if viewModel.showCopiedToast {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Copied to clipboard!")
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showCopiedToast)
    }

    // MARK: - Context input (shared between empty + populated states)
    @ViewBuilder
    private func contextInputView(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your reaction or context", systemImage: "text.bubble")
                .font(.subheadline)
                .fontWeight(.semibold)

            TextField(
                "e.g., 'I love that she said that' or 'be a little flirty'",
                text: text
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                Task { await viewModel.getAISuggestion() }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Regenerate button
    private var regenerateButton: some View {
        Group {
            if viewModel.isLoadingAI {
                Button {} label: {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
            } else {
                Button {
                    Task { await viewModel.getAISuggestion() }
                } label: {
                    Label("Regenerate All", systemImage: "arrow.clockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.messages.isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Empty state
    private var emptyStateView: some View {
        @Bindable var vm = viewModel

        return ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                // Sparkles icon with gradient backdrop
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)
                    Image(systemName: "sparkles")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 6) {
                    Text("AI Response Suggestions")
                        .font(.title2).fontWeight(.semibold)
                    Text("Get 6 style variations to respond to your conversation")
                        .font(.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                // Prominent context input — same treatment as populated state
                contextInputView(text: $vm.reactionContext)
                    .padding(.horizontal)

                // Style preview chips in adaptive grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                    ForEach(viewModel.responseStyles) { style in
                        HStack(spacing: 6) {
                            Text(style.emoji).font(.body)
                            Text(style.name)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(styleAccentColor(for: style.id).opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(styleAccentColor(for: style.id).opacity(0.3), lineWidth: 1))
                    }
                }
                .padding(.horizontal)

                Button {
                    Task { await viewModel.getAISuggestion() }
                } label: {
                    Label("Get AI Suggestions", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.messages.isEmpty || viewModel.isLoadingAI)
                .padding(.horizontal)

                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Style Card
struct StyleCard: View {
    @Environment(AppViewModel.self) private var viewModel
    let style: ResponseStyle

    var isFollowingUp: Bool { viewModel.followUpStyleID == style.id }
    var text: String? { viewModel.aiSuggestions[style.id] }
    var accent: Color { styleAccentColor(for: style.id) }

    var body: some View {
        @Bindable var vm = viewModel

        HStack(spacing: 0) {
            // 3pt left accent bar
            Rectangle()
                .fill(accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                // Header: tinted background, larger emoji, semibold name, always-visible copy
                HStack(alignment: .center, spacing: 8) {
                    Text(style.emoji)
                        .font(.title3)
                    Text(style.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    if let t = text, !t.hasPrefix("⚠️") {
                        Button {
                            viewModel.copyToClipboard(t)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy to clipboard")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(accent.opacity(0.10))

                // Body content
                VStack(alignment: .leading, spacing: 10) {
                    if let t = text {
                        Text(t)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)

                        if !isFollowingUp {
                            Button {
                                vm.followUpStyleID = style.id
                                vm.followUpText = ""
                            } label: {
                                Label("Refine this", systemImage: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        // Loading state in accent color
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(accent)
                            Text("Generating…")
                                .font(.caption)
                                .foregroundStyle(accent)
                        }
                    }

                    // Inline follow-up
                    if isFollowingUp {
                        Divider()
                        HStack(spacing: 8) {
                            TextField(
                                "e.g., 'Make it shorter' or 'Add a question'",
                                text: $vm.followUpText
                            )
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await viewModel.sendFollowUp(for: style.id) }
                            }
                            Button {
                                Task { await viewModel.sendFollowUp(for: style.id) }
                            } label: {
                                Image(systemName: "paperplane.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.followUpText.isEmpty || viewModel.isLoadingAI)

                            Button {
                                vm.followUpStyleID = nil
                                vm.followUpText = ""
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.25), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    AIPanelView()
        .environment(AppViewModel())
        .frame(width: 400, height: 800)
}
