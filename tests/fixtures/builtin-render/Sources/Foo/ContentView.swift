import AppKit
import SwiftUI
import FooCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(FooCore.greeting(appName: "Foo Bar"))
                .font(.title)
            Text("does x")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 640, minHeight: 400)
    }
}
