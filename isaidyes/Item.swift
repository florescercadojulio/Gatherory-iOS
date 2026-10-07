//
//  Item.swift
//  isaidyes
//
//  Created by Julio C on 10/7/26.
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
