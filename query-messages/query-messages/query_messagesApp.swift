//
//  query_messagesApp.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import SwiftUI

@main
struct query_messagesApp: App {
    @State private var viewModel = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 1200, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Chats") {
                    Task {
                        await viewModel.loadChats()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Get AI Suggestion") {
                    Task {
                        await viewModel.getAISuggestion()
                    }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}
