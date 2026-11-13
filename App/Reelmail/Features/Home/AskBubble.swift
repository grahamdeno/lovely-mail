import SwiftUI

/// A small floating button on the Money, Energy and Kids pages that opens Ask Lovely about that page (owner, Nov 9).
struct AskBubble: View {
    let topic: PageFacts.Topic
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "sparkles").font(.lovely(.title3, .semibold)).foregroundStyle(CalmStyle.onBlue)
                .frame(width: 56, height: 56)
                .background(CalmStyle.blue, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20).padding(.bottom, 16)
        .accessibilityLabel("Ask Lovely about \(topic.title)")
        .accessibilityIdentifier("ask.bubble.\(topic.rawValue)")
        .sheet(isPresented: $open) {
            NavigationStack {
                AskLovelyView(topic: topic)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { open = false } } }
            }
            .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    /// Adds the Ask Lovely bubble in the bottom-right corner.
    func askBubble(_ topic: PageFacts.Topic) -> some View {
        overlay(alignment: .bottomTrailing) { AskBubble(topic: topic) }
    }
}
