//
//  SwiftLumiApp.swift
//  SwiftLumi
//
//  Created by Chris on 26/08/2025.
//

import SwiftUI


@main
struct SwiftLumiApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(iOS 18, *) {
                ContentView()
            }
        }
    }
}
