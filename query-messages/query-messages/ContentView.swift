//
//  ContentView.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    
    var body: some View {
        NavigationSplitView {
            // Left pane: Chat list
            ChatListView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } content: {
            // Center pane: Message thread
            MessageThreadView()
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        } detail: {
            // Right pane: AI suggestions
            AIPanelView()
                .navigationSplitViewColumnWidth(min: 350, ideal: 450)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .overlay(alignment: .top) {
            if viewModel.showFullDiskAccessBanner {
                fullDiskAccessBanner
            }
        }
    }
    
    private var fullDiskAccessBanner: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Disk Access Required")
                        .fontWeight(.semibold)
                    Text("Grant Full Disk Access to read iMessage database")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Open Settings") {
                    viewModel.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    viewModel.showFullDiskAccessBanner = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(.ultraThickMaterial)
            .cornerRadius(12)
            .shadow(radius: 4)
            .padding()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
        .frame(width: 1400, height: 800)
}
