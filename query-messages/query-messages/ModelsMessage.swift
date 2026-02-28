//
//  Message.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation

struct Message: Identifiable {
    let id = UUID()
    let dateRaw: Int64       // Apple Core Data timestamp; 0 for externally-loaded messages
    let messageDate: String
    let sender: String
    let content: String

    var isFromMe: Bool {
        sender == "Me"
    }
}
