//
//  TickbyteApp.swift
//  Tickbyte
//
//  Created by Luke Mao on 5/2/2025.
//

import SwiftUI

@main
struct TickbyteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
