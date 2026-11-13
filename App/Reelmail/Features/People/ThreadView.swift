import SwiftUI

struct ThreadView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let person: Person
    @State private var showingInfo = false
    @State private var dismissedAsk: String?
    /// Swipe left anywhere to show each message's time, sender address and read state (like Messages).
    @State private var reveal: CGFloat = 0
    static let revealWidth: CGFloat = 92
    var body: some View {
        let messages = store.conversation(with: person)
        let latestIncoming = messages.last { !$0.isFromMe }.flatMap { store.post(for: $0) }
        ScrollView {
            LazyVStack(spacing: 10) {
                PersonHeader(person: person, profile: store.profile(for: person), waiting: store.needsReply(person),
                             addresses: store.addresses(of: person), onSeparate: { store.separate(address: $0) })
                    .padding(.bottom, 8)
                Text(store.mode == .sample ? "Demo · fictional conversation" : "Recent mail with \(person.firstName)")
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).padding(.bottom, 4)
                ForEach(store.waitingOnThem.filter { $0.recipient.lowercased() == person.email.lowercased() }) { item in
                    ThreadAskRow(item: item) { dismissedAsk = item.id }
                }
                if messages.isEmpty { Text("No loaded messages with this person.").padding(.vertical, 24) }
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, email in
                    let previous: Email? = index > 0 ? messages[index - 1] : nil
                    let summary = store.post(for: email)?.summary
                    if previous.map({ !Calendar.current.isDate(email.date, inSameDayAs: $0.date) }) ?? true {
                        Text(email.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).padding(.vertical, 8)
                    }
                    if previous?.threadId != email.threadId {
                        Text(ConversationPresentation.isSensitive(email, summary: summary) ? "Private topic" : email.subject)
                            .font(.lovely(.caption, .medium)).foregroundStyle(CalmStyle.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 4)
                    }
                    ZStack(alignment: .trailing) {
                        ConversationBubble(email: email, mine: Set([store.account ?? ""] + store.otherAddresses).subtracting([""]), summary: summary,
                            later: store.post(for: email).flatMap { post in
                                store.laterUntil[post.id].flatMap { LaterSchedule.isPending($0, now: Date()) ? "Later \u{00B7} " + LaterSchedule.label($0, now: Date()) : nil }
                            },
                            grouped: ConversationPresentation.groups(email, after: previous))
                        .offset(x: reveal)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(email.date.formatted(date: .omitted, time: .shortened)).font(.lovely(.caption2, .semibold))
                            Text(Self.revealCaption(email)).font(.lovely(.caption2)).lineLimit(3).multilineTextAlignment(.trailing)
                        }
                        .foregroundStyle(CalmStyle.secondary)
                        .frame(width: Self.revealWidth - 6, alignment: .trailing)
                        .offset(x: Self.revealWidth + reveal)
                        .opacity(Double(-reveal / Self.revealWidth))
                        .accessibilityHidden(true)
                    }
                }
            }.padding(16)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    reveal = max(-Self.revealWidth, min(0, v.translation.width))
                }
                .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { reveal = 0 } }
        )
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .safeAreaInset(edge: .bottom) {
            if let latestIncoming {
                HStack {
                    Text("Draft a reply here").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer()
                    Button { router.draftPostID = latestIncoming.id } label: { Label("Draft reply", systemImage: "arrowshape.turn.up.left") }
                        .buttonStyle(CalmActionStyle(prominent: true)).lineLimit(1).fixedSize()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                // Opaque, full width: scrolled messages never show around or under the bar.
                .frame(maxWidth: .infinity)
                .background(CalmStyle.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .overlay(alignment: .bottom) {
            if let id = dismissedAsk {
                UndoBar(text: "Removed from Waiting on them") { store.restoreWaiting(id); dismissedAsk = nil }
                    .padding(.horizontal, 20).padding(.bottom, 80)
                    .task(id: id) { try? await Task.sleep(for: .seconds(6)); if dismissedAsk == id { dismissedAsk = nil } }
            }
        }
        .navigationTitle(person.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showingInfo = true } label: {
                    HStack(spacing: 8) {
                        CalmAvatar(person: person, size: 28)
                        Text(person.name).font(.lovely(.headline)).foregroundStyle(CalmStyle.ink).lineLimit(1)
                        Image(systemName: "chevron.down").font(.lovely(.caption2)).foregroundStyle(CalmStyle.secondary)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("Conversation details for \(person.name)")
            }
        }
        .toolbarBackground(CalmStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        
        .sheet(isPresented: $showingInfo) {
            ConversationInfoSheet(person: person, mode: store.mode)
        }
    }
}

extension ThreadView {
    /// Under the time: who it came from (the address, since a person can have several), how many it went to, and read state.
    static func revealCaption(_ email: Email) -> String {
        var parts: [String] = []
        parts.append(email.isFromMe ? "You sent" : email.from.email)
        if email.recipients.count > 1 { parts.append("to \(email.recipients.count)") }
        if !email.isFromMe { parts.append(email.isUnread ? "Unread" : "Read") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

private struct ConversationBubble: View {
    let email: Email
    let mine: Set<String>
    let summary: EmailSummary?
    var later: String? = nil
    let grouped: Bool
    @State private var showingDetails = false
    private var secondaryInk: Color { CalmStyle.secondary }
    var body: some View {
        let preview = ConversationPresentation.preview(email, summary: summary)
        HStack(alignment: .bottom, spacing: 0) {
            if email.isFromMe { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 6) {
                if let caption = ReplyRecipients.caption(email, mine: mine) ?? (email.to.count > 1 ? "Additional recipients \u{00B7} see source" : nil) {
                    Label(caption, systemImage: "person.2")
                        .font(.lovely(.caption)).foregroundStyle(secondaryInk)
                }
                if let later {
                    Label(later, systemImage: "clock").font(.lovely(.caption)).foregroundStyle(secondaryInk)
                }
                if let label = preview.label {
                    Text(label).font(.lovely(.caption, .semibold)).foregroundStyle(secondaryInk)
                }
                if preview.concealed {
                    Label(preview.text, systemImage: "lock").font(.lovely(.body))
                } else {
                    Text(preview.text).font(.lovely(.body)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                HStack(spacing: 12) {
                    if !grouped { Text(email.date.formatted(date: .omitted, time: .shortened)).font(.lovely(.caption2)) }
                    Button { showingDetails = true } label: {
                        Text("Source").font(.lovely(.caption)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Show original email and details")
                }.foregroundStyle(secondaryInk)
            }
            .foregroundStyle(CalmStyle.ink)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            .background(email.isFromMe ? CalmStyle.card : CalmStyle.bubble, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(email.isFromMe ? "Your email" : "Email from \(email.from.name)")
            if !email.isFromMe { Spacer(minLength: 36) }
        }
        .padding(.top, grouped ? 0 : 6)
        .sheet(isPresented: $showingDetails) { EmailSourceSheet(email: email) }
    }
}

private struct ConversationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let person: Person
    let mode: DataMode
    var body: some View { sheetBody.lifeSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(person.name).font(.lovely(.title2, .semibold))
                    Text(person.email).textSelection(.enabled)
                    Text(mode == .sample ? "Fictional incoming and outgoing demo mail." : "Recent Primary inbox mail and your sent replies from the last 90 days. Older history stays in Gmail.")
                    Text("Short messages show original imported text. Longer messages show a labeled summary or excerpt when available. Generated summaries can be imperfect; verify details in the source.")
                    Text("Read-only. Nothing can be sent from this screen.")
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
            .navigationTitle("Conversation details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CalmStyle.blue)
    }
}

private struct EmailSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let email: Email
    var body: some View { sheetBody.lifeSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(email.subject).font(.lovely(.headline))
                    Text("From: \(email.from.email)")
                    Text("To: \(email.to.joined(separator: ", "))")
                    Text(email.date.formatted(date: .abbreviated, time: .shortened))
                    if !email.cc.isEmpty { Text("Cc: \(email.cc.joined(separator: ", "))") }
                    Divider()
                    Text(email.body.isEmpty ? "No readable body was imported." : email.body).font(.lovely(.body))
                }.font(.lovely(.subheadline)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
            .navigationTitle("Source email").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CalmStyle.blue)
    }
}

/// Who this is and where things stand, in a few blunt lines, above the conversation.
private struct PersonHeader: View {
    let person: Person
    let profile: PersonProfile
    let waiting: Bool
    var addresses: [String] = []
    var onSeparate: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CalmAvatar(person: person, size: 56, waiting: waiting)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(.lovely(.title2, .bold)).lineLimit(2)
                    Text(person.email).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(1).textSelection(.enabled)
                    // Same name from other addresses: shown together, with a way to undo it.
                    ForEach(addresses.filter { $0.lowercased() != person.email.lowercased() }, id: \.self) { other in
                        Menu {
                            Button("Not the same person") { onSeparate(other) }
                        } label: {
                            Text("Also " + other).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                        }
                        .accessibilityHint("Shows the option to keep this address separate")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("THE SHORT VERSION").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                Text(profile.shortVersion).font(.lovely(.body)).fixedSize(horizontal: false, vertical: true)
                Text("From the mail loaded on this iPhone").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 8) {
                stat("\(profile.total)", profile.since.map { "emails since " + $0.formatted(.dateTime.month(.abbreviated)) } ?? "emails")
                stat("\(profile.fromYou)", "from you")
                if let usual = profile.usualReply {
                    stat(PersonProfile.duration(usual), "your usual reply")
                } else {
                    stat("–", profile.fromYou == 0 ? "no replies yet" : "your usual reply")
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if !profile.open.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OPEN WITH \(person.firstName.uppercased())").font(.lovely(.caption, .semibold)).tracking(0.8)
                        .foregroundStyle(CalmStyle.roseInk)
                    ForEach(profile.open) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(item.theirs ? CalmStyle.rose : CalmStyle.secondary).frame(width: 8, height: 8).padding(.top, 6)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text).font(.lovely(.subheadline)).fixedSize(horizontal: false, vertical: true)
                                Text(item.detail).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            if !profile.topics.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(profile.topics, id: \.self) { topic in
                            Text(topic).font(.lovely(.footnote)).lineLimit(1).fixedSize(horizontal: true, vertical: false).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(CalmStyle.bubble, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.lovely(.title3, .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(2)
        }
        // Every tile fills the row's height so the three line up even when one label wraps.
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
