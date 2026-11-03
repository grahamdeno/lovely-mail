import SwiftUI

/// "Later": a menu of quick times plus a date picker. Local to this phone; Gmail is not changed.
struct LaterMenu<Content: View>: View {
    @Environment(FeedStore.self) private var store
    let post: Post
    var onPut: () -> Void = {}
    @ViewBuilder let content: () -> Content
    @State private var picking = false

    var body: some View {
        let now = Date()
        Menu {
            ForEach(LaterSchedule.options(now: now)) { option in
                Button(option.title + " · " + LaterSchedule.label(option.date, now: now)) {
                    store.putOff(post, until: option.date); onPut()
                }
            }
            Button("Pick a time…") { picking = true }
        } label: { content() }
        .accessibilityLabel("Later")
        .sheet(isPresented: $picking) {
            LaterPicker { date in store.putOff(post, until: date); onPut() }
                .presentationDetents([.large])
        }
    }
}

/// A date and time at least one hour away.
struct LaterPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Date) -> Void
    @State private var date = LaterSchedule.earliestCustom(now: Date())

    var body: some View {
        NavigationStack {
            DatePicker("Bring it back", selection: $date, in: LaterSchedule.earliestCustom(now: Date())...,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical).padding(.horizontal, 16)
                .navigationTitle("Later").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Later") { onPick(date); dismiss() } }
                }
            Spacer(minLength: 0)
        }
        .tint(CalmStyle.blue)
    }
}
