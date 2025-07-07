//
//  Item.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
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
