import SwiftUI

/// DM-style conversation with one person: their mail on the left, mine on the right.
struct ThreadView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let person: Person

    var body: some View {
        let messages = store.conversation(with: person)
        ScrollView {
            LazyVStack(spacing: RM.Space.s) {
                ForEach(messages) { email in
                    Bubble(email: email, summary: store.post(for: email)?.summary)
                        .onTapGesture {
                            if !email.isFromMe { router.open(.email(email.id)) }
                        }
                }
            }
            .padding(RM.Space.l)
        }
        .defaultScrollAnchor(.bottom)
        .background(RM.Palette.sheet)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let latest = store.posts(from: person).first {
                Button { router.draftPostID = latest.id } label: {
                    Label("Draft reply", systemImage: "arrowshape.turn.up.left.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(RMButtonStyle(kind: .ghostLight))
                .background(Color.white)
                .rmCorner(RM.Radius.button)
                .padding(RM.Space.l)
            }
        }
    }
}

private struct Bubble: View {
    let email: Email
    let summary: EmailSummary?

    var body: some View {
        HStack {
            if email.isFromMe { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 4) {
                if let summary, !email.isFromMe {
                    Text(summary.headline).font(RM.Typo.callout.weight(.semibold))
                }
                Text(email.isFromMe ? email.body : (summary?.sensitive == true ? "Private details hidden" : (summary?.blurb ?? email.body)))
                    .font(RM.Typo.callout)
                Text(email.date.formatted(date: .omitted, time: .shortened))
                    .font(RM.Typo.micro).opacity(0.6)
            }
            .foregroundStyle(email.isFromMe ? RM.Palette.ink : .white)
            .padding(RM.Space.m)
            .background(email.isFromMe ? Color.white : RM.Palette.surface)
            .rmCorner(RM.Radius.card)
            .overlay(alignment: .topTrailing) {
                if summary?.needsReply == true {
                    Circle().fill(RM.Palette.violet).frame(width: 8, height: 8).offset(x: -8, y: 8)
                }
            }
            if !email.isFromMe { Spacer(minLength: 48) }
        }
    }
}
