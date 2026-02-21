//
//  Item.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
