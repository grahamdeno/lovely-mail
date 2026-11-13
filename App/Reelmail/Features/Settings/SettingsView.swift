import SwiftUI

/// Settings, top level: one screen of rows, each showing its current value, each opening one topic (Nov 9 redesign).
/// Things you act on (Later, clean-ups) live where you work; this page is only for setting things.
struct SettingsView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @AppStorage(BriefSettings.enabledKey) private var briefOn = false
    @AppStorage(BriefSettings.minutesKey) private var briefMinutes = BriefSettings.defaultMinutes
    @AppStorage(SettingsView.testingKey) private var showTesting = false
    @State private var versionTaps = 0

    static let testingKey = "lovely.settings.showTesting"

    var body: some View {
        // LifeOS settings (Nov 13, 2026): a centered profile, then grouped cards under small section labels.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsProfileHeader { router.open(.settingsAccount) }
                AccountAttention()
                LifeSectionLabel(title: "Account")
                LifeGroup {
                    LifeGroupRow(icon: "envelope", title: "Account", badge: store.mode == .gmail ? "Gmail" : "Demo") { router.open(.settingsAccount) }
                    LifeGroupRow(icon: "line.3.horizontal.decrease", title: "Your rules", value: Self.rulesValue(store)) { router.open(.settingsRules) }
                    LifeGroupRow(icon: "tray.2", title: "Categories", value: "\(CategorySettings.current.visible.count) shown") { router.open(.settingsCategories) }
                    LifeGroupRow(icon: "house", title: "Households and kids", value: Self.householdsValue()) { router.open(.insightSettings) }
                }
                LifeSectionLabel(title: "App")
                LifeGroup {
                    LifeGroupRow(icon: "sun.horizon", title: "Morning brief", value: briefOn ? Self.timeLabel(briefMinutes) : "Off") { router.open(.settingsBrief) }
                    LifeGroupRow(icon: "paintpalette", title: "Look and feel", value: appearance.title) { router.open(.settingsLook) }
                    LifeGroupRow(icon: "cpu", title: "AI", value: "On this iPhone") { router.open(.settingsAI) }
                    LifeGroupRow(icon: "lock", title: "Privacy and activity") { router.open(.settingsPrivacy) }
                    if store.mode == .gmail { LifeGroupRow(icon: "sparkles", title: "Clean up", value: "Old login emails") { router.open(.cleanup) } }
                    if showTesting { LifeGroupRow(icon: "wrench.and.screwdriver", title: "Testing tools") { router.open(.testingTools) } }
                }
                Text(Self.versionLabel)
                    .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    .onTapGesture {
                        // Five taps show Testing tools (and five more hide them): not an everyday setting.
                        versionTaps += 1
                        if versionTaps >= 5 { showTesting.toggle(); versionTaps = 0 }
                    }
                    .accessibilityIdentifier("settings.version")
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.large)
    }

    static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "Lovely \(v) (\(b))"
    }

    static func timeLabel(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, m, h < 12 ? "AM" : "PM")
    }

    @MainActor static func rulesValue(_ store: FeedStore) -> String {
        let filtered = Set(store.filteredPosts.map(\.email.from.email)).count
        return filtered == 0 ? "" : (filtered == 1 ? "1 sender" : "\(filtered) senders")
    }

    static func householdsValue() -> String {
        let d = InsightSettings().load()
        var parts: [String] = []
        if !d.households.isEmpty { parts.append("\(d.households.count) home\(d.households.count == 1 ? "" : "s")") }
        if !d.kids.isEmpty { parts.append("\(d.kids.count) kid\(d.kids.count == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

/// The top of Settings, LifeOS style: a big circle with the account's initial and a black mail badge, then the address.
struct SettingsProfileHeader: View {
    @Environment(FeedStore.self) private var store
    let open: () -> Void
    var body: some View {
        let address = store.mode == .gmail ? (store.account ?? "Gmail") : "Demo mail"
        Button(action: open) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Text(String(address.prefix(1)).uppercased())
                        .font(.lovely(size: 38, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(LifeColor.orange, in: Circle())
                        .overlay(Circle().strokeBorder(CalmStyle.card, lineWidth: 4))
                    Image(systemName: "envelope").font(.footnote.weight(.semibold)).foregroundStyle(CalmStyle.onBlue)
                        .frame(width: 34, height: 34).lifeBlack(corner: 11)
                        .offset(x: 4, y: 2)
                }
                Text(store.mode == .gmail ? "Your Gmail" : "Demo mail").font(.lovely(size: 24, weight: .semibold)).padding(.top, 8)
                Text(detail).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("settings.account")
    }
    private var detail: String {
        guard store.mode == .gmail else { return "Connect Gmail to see your own mail" }
        return store.account ?? "Gmail"
    }
}

/// The account at the top of Settings: who is connected and when mail last loaded. Opens the Account page.
struct AccountHeaderCard: View {
    @Environment(FeedStore.self) private var store
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: store.mode == .gmail ? "envelope.fill" : "envelope")
                    .foregroundStyle(CalmStyle.onBlue).frame(width: 44, height: 44)
                    .background(CalmStyle.blue, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.mode == .gmail ? (store.account ?? "Gmail") : "Demo mail").font(.lovely(.headline)).lineLimit(1).truncationMode(.middle)
                    Text(detail).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.lovely(.caption, .bold)).foregroundStyle(CalmStyle.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("settings.account")
    }
    private var detail: String {
        guard store.mode == .gmail else { return "Connect Gmail to see your own mail" }
        if let fetched = store.lastFetched { return "Gmail · updated " + MailTime.label(fetched).lowercased() }
        return "Gmail"
    }
}

/// Sign-in problems and Connect, shown on the top level so they are never buried.
struct AccountAttention: View {
    @Environment(FeedStore.self) private var store
    var body: some View {
        if store.needsReconnect {
            Text(store.needsMailAccess
                 ? "Google didn't give Lovely access to your mail. Tap Reconnect, and on Google's screen tick the Gmail box (or Select all) before Continue."
                 : "Google signed you out. While Lovely is in testing this happens every 7 days. Your loaded mail is still here.")
                .font(.lovely(.subheadline)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(CalmStyle.warning, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CalmStyle.warningInk)
        }
        if store.gmailConfigured, !(store.mode == .gmail && !store.needsReconnect) {
            Button { Task { await store.connectGmail() } } label: {
                Label(store.needsReconnect ? "Reconnect Gmail" : "Connect Gmail", systemImage: "envelope.badge.shield.half.filled").frame(maxWidth: .infinity)
            }.buttonStyle(CalmActionStyle(prominent: true)).accessibilityIdentifier("settings.connect")
        }
        if let error = store.errorMessage, !store.needsReconnect {
            Text(error).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
    }
}

/// Account: the connected Gmail, your other addresses, iCloud backup, and Disconnect.
struct SettingsAccountView: View {
    @Environment(FeedStore.self) private var store
    @State private var confirmDisconnect = false

    private var sourceDetail: String {
        switch (store.mode, store.gmailConfigured) {
        case (.gmail, _):
            var parts = [store.account ?? ""]
            parts.append("\(store.posts.count) inbox messages, \(store.sentByMe.count) sent")
            if let fetched = store.lastFetched { parts.append("updated " + MailTime.label(fetched).lowercased()) }
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        case (.sample, true): return "Fictional mail. Connect Gmail to see your own."
        case (.sample, false): return "This build has no Gmail configuration, so it shows fictional mail."
        }
    }

    var body: some View {
        SettingsPage(title: "Account") {
            ProfileCard(title: "Mail source", value: store.mode == .gmail ? "Gmail" : "Demo", detail: sourceDetail)
            AccountAttention()
            SettingsHeader(text: "Your other addresses")
            OtherAddressesCard()
            SettingsHeader(text: "Backup")
            ICloudBackupCard()
            if store.gmailConfigured, store.mode == .gmail, !store.needsReconnect {
                // Quiet on purpose, and last: it clears the mail kept on this phone.
                Button(role: .destructive) { confirmDisconnect = true } label: {
                    Label("Disconnect Gmail", systemImage: "envelope.badge.shield.half.filled")
                        .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.roseInk)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.top, 18).accessibilityIdentifier("settings.disconnect")
                .confirmationDialog("Disconnect Gmail?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                    Button("Disconnect", role: .destructive) { Task { await store.disconnectGmail() } }
                } message: {
                    Text("Mail kept on this iPhone is cleared. Households, kids and your addresses stay. You can connect again any time.")
                }
            }
        }
    }
}

/// Your rules: everything that decides where mail goes, in Lovely and in Gmail, in one place.
struct SettingsRulesView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showingFiltered = false

    var body: some View {
        SettingsPage(title: "Your rules") {
            SettingsHeader(text: "In Lovely only", first: true)
            ProfileCard(title: "Filtered senders", value: filteredSummary,
                        detail: "Long-press a message to filter a sender or move it to Reading. These change Lovely only, not Gmail.")
            Button { showingFiltered = true } label: { Label("Review filtered senders", systemImage: "line.3.horizontal.decrease.circle").frame(maxWidth: .infinity) }
                .buttonStyle(CalmActionStyle())
            if !store.hiddenPosts.isEmpty {
                Button { store.restoreAll() } label: { Label("Show hidden mail (\(store.hiddenPosts.count))", systemImage: "eye").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
            }
            SettingsHeader(text: "In Gmail too")
            VStack(spacing: 8) {
                SettingsRow(title: "Gmail filters", value: "Always put away, screen out") { router.open(.gmailFilters) }
                if store.actions != nil { SettingsRow(title: "New senders", value: "Screen out first-timers") { router.open(.screenedOut) } }
                if store.mode == .gmail { SettingsRow(title: "Short-term mail", value: "Trash after 2 weeks") { router.open(.shortTermCleanup) } }
            }
        }
        .sheet(isPresented: $showingFiltered) { FilteredMailReview() }
    }

    private var filteredSummary: String {
        let filtered = Set(store.filteredPosts.map(\.email.from.email)).count
        return filtered == 0 ? "No senders filtered" : (filtered == 1 ? "1 sender filtered" : "\(filtered) senders filtered")
    }
}

/// Morning brief on its own page.
struct SettingsBriefView: View {
    var body: some View { SettingsPage(title: "Morning brief") { MorningBriefCard() } }
}

/// Look and feel: appearance, the opening animation, and pictures.
struct SettingsLookView: View {
    var body: some View {
        SettingsPage(title: "Look and feel") {
            SettingsHeader(text: "Appearance", first: true)
            AppearanceCard()
            OpeningAnimationToggle()
            SplitPillToggle()
            SettingsHeader(text: "Pictures")
            PicturesCard()
        }
    }
}

/// AI: which engine talks with you in the inbox session, and whether Apple Intelligence is ready.
struct SettingsAIView: View {
    @Environment(Router.self) private var router
    var body: some View {
        SettingsPage(title: "AI") {
            SettingsRow(title: "Conversation engine", value: "Apple Intelligence") { router.open(.engineSettings) }
            let status = ModelStatus.current
            ProfileCard(title: "On-device AI", value: status.title, detail: status.detail)
            GrokHandoffSetting()
        }
    }
}

/// Privacy and activity: what Lovely does with mail, what it changed in Gmail, and where it may forward.
struct SettingsPrivacyView: View {
    @Environment(Router.self) private var router
    var body: some View {
        SettingsPage(title: "Privacy and activity") {
            VStack(spacing: 8) {
                SettingsRow(title: "How Lovely handles your mail") { router.open(.aboutPrivacy) }
                SettingsRow(title: "Gmail activity", value: "What Lovely changed") { router.open(.gmailActivity) }
                SettingsRow(title: "Forwarding addresses") { router.open(.forwardingAddresses) }
            }
        }
    }
}

/// Mail you put off with Later, and when each comes back. Opened from Home's "Later" chip.
struct LaterListView: View {
    @Environment(FeedStore.self) private var store
    var body: some View {
        SettingsPage(title: "Later") {
            let later = store.laterPosts
            if later.isEmpty {
                Text("Nothing put off.").font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary)
            }
            ForEach(later, id: \.post.id) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.post.email.from.name).font(.lovely(.subheadline, .semibold)).lineLimit(1)
                        Text(item.post.email.subject).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                        Text("Back " + LaterSchedule.label(item.until, now: Date())).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Bring back now") { store.bringBack(item.post.id) }
                        .font(.lovely(.caption, .semibold)).foregroundStyle(CalmStyle.blue).frame(minHeight: 44)
                }
                .padding(14).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

/// A settings sub-page: a scrolling column with the app's background.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

/// Morning brief: off until switched on. Counts only on the lock screen unless names are turned on.
struct MorningBriefCard: View {
    @Environment(FeedStore.self) private var store
    @AppStorage(BriefSettings.enabledKey) private var enabled = false
    @AppStorage(BriefSettings.minutesKey) private var minutes = BriefSettings.defaultMinutes
    @AppStorage(BriefSettings.namesKey) private var names = false
    @AppStorage(BriefSettings.nudgeKey) private var nudge = false
    @State private var declined = false
    @State private var chosenByHand = BriefSettings().manualMinutes != nil

    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date() },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes = (c.hour ?? 7) * 60 + (c.minute ?? 30) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Send a morning brief", isOn: Binding(get: { enabled }, set: { turn($0) }))
            if declined {
                Text("Notifications are off for Lovely. Turn them on in the Settings app.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            if enabled {
                DatePicker("Time", selection: Binding(get: { time.wrappedValue }, set: { time.wrappedValue = $0; chosenByHand = true }), displayedComponents: .hourAndMinute)
                if chosenByHand {
                    Button("Let Lovely choose the time") {
                        UserDefaults.standard.removeObject(forKey: BriefSettings.minutesKey); chosenByHand = false
                        Task { await MorningBriefScheduler.reschedule(store: store) }
                    }.font(.lovely(.subheadline))
                } else {
                    Text("Lovely chooses: 9:30 on weekdays, 10:00 on weekends, then it adjusts to when you open the app.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                }
                Toggle("Evening check at 7 PM", isOn: $nudge)
                Toggle("Show names in the brief", isOn: $names)
                Text("Names can appear on your lock screen.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            Text("A short note with counts, built on this iPhone from mail already loaded. It skips mornings with nothing to say.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: minutes) { _, _ in Task { await MorningBriefScheduler.reschedule(store: store) } }
        .onChange(of: names) { _, _ in Task { await MorningBriefScheduler.reschedule(store: store) } }
        .onChange(of: nudge) { _, _ in Task { await MorningBriefScheduler.reschedule(store: store) } }
    }

    private func turn(_ on: Bool) {
        guard on else {
            enabled = false; declined = false
            Task { await MorningBriefScheduler.reschedule(store: store) }
            return
        }
        Task {
            let granted = await MorningBriefScheduler.requestPermission()
            enabled = granted; declined = !granted
            UserDefaults.standard.set(true, forKey: BriefSettings.offerSeenKey)
            await MorningBriefScheduler.reschedule(store: store)
        }
    }
}

/// A small-caps group title in Settings.
struct SettingsHeader: View {
    let text: String
    var first = false
    var body: some View {
        Text(text.uppercased()).font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            .padding(.top, first ? 4 : 18)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A full-width row that opens another screen, with its current value on the right (like the iPhone's Settings).
struct SettingsRow: View {
    let title: String
    var value: String = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.lovely(.body))
                Spacer(minLength: 8)
                if !value.isEmpty { Text(value).font(.lovely(.subheadline)).foregroundStyle(CalmStyle.secondary).lineLimit(1) }
                Image(systemName: "chevron.right").font(.lovely(.caption, .bold)).foregroundStyle(CalmStyle.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).frame(minHeight: 48).frame(maxWidth: .infinity, alignment: .leading)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("settings.row." + title)
    }
}

/// Review sorting and Summary Lab: tools for checking Lovely, not everyday settings.
struct TestingToolsView: View {
    @Environment(Router.self) private var router
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button { router.open(.sortingReview) } label: { Label("Review sorting", systemImage: "checkmark.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
                Button { router.open(.summaryLab) } label: { Label("Summary Lab", systemImage: "flask").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
                MorningBriefTestCard()
                ChatSwitchCard()
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Testing tools").navigationBarTitleDisplayMode(.inline)
    }
}

/// Testing tools: see the morning brief now instead of waiting for the morning.
struct MorningBriefTestCard: View {
    @Environment(FeedStore.self) private var store
    @State private var note: String?

    var body: some View {
        let brief = MorningBriefScheduler.preview(store: store)
        VStack(alignment: .leading, spacing: 10) {
            Text("MORNING BRIEF").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            if let brief {
                Text(brief.title).font(.lovely(.subheadline, .semibold))
                Text(brief.body).font(.lovely(.subheadline))
            } else {
                Text("The next brief would be skipped: nothing to say.").font(.lovely(.subheadline))
            }
            Button {
                Task {
                    let sent = await MorningBriefScheduler.sendTest(store: store)
                    note = sent ? "Sent. Leave Lovely now and it arrives in 5 seconds." : "Nothing sent. Notifications may be off for Lovely, or there is nothing to say."
                }
            } label: { Label("Send a test brief", systemImage: "bell").frame(maxWidth: .infinity) }
                .buttonStyle(CalmActionStyle())
            if let note { Text(note).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary) }
            Text("The test does not turn on the real brief.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// The privacy paragraph.
struct AboutPrivacyView: View {
    var body: some View {
        ScrollView {
            Text("Lovely reads your Gmail and writes summaries on this iPhone. Apart from Gmail, the only thing it fetches from the internet is company logos, from each company's own website, and you can turn that off in Settings under Look and feel. It changes Gmail in only two ways, both when you ask and both undoable: moving a message to Trash, and marking a message read when you tap Done. It never sends mail, never deletes anything for good, and never changes other labels. Loaded mail is kept encrypted on this phone and removed when you disconnect.")
                .font(.lovely(.body)).foregroundStyle(CalmStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("How Lovely handles your mail").navigationBarTitleDisplayMode(.inline)
    }
}

/// Light, dark, or follow the iPhone's setting.
struct AppearanceCard: View {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(appearance == .neon ? "Dark mode with neon: electric cyan for what you can tap, hot magenta for people waiting on you, and a glowing stripe."
                 : "Auto follows your iPhone's light and dark setting.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Where avatar pictures come from. Both stay on this phone.
struct PicturesCard: View {
    @State private var images = AvatarImages.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Photos from your Contacts", isOn: Binding(get: { images.useContacts },
                                                             set: { on in Task { await images.setUseContacts(on) } }))
                .font(.lovely(.subheadline))
            Text("Matched by email address on this iPhone. Nothing is uploaded.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            if !images.contactsStatus.isEmpty {
                Text(images.contactsStatus).font(.lovely(.caption)).foregroundStyle(CalmStyle.roseInk)
            }
            Toggle("Company logos", isOn: $images.showLogos).font(.lovely(.subheadline))
            Text("Fetched once from each company's own website and kept on this iPhone. Never for people, never through a third party.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Other addresses of yours. Mail from them is "Notes to self". You declare them; Lovely never guesses from names.
struct OtherAddressesCard: View {
    @Environment(FeedStore.self) private var store
    @State private var newAddress = ""
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mail you send yourself from these shows under Notes to self, not Waiting on you.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            ForEach(store.otherAddresses, id: \.self) { address in
                HStack {
                    Text(address).font(.lovely(.subheadline)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Remove", role: .destructive) { store.removeOtherAddress(address) }
                        .font(.lovely(.subheadline)).foregroundStyle(CalmStyle.roseInk).frame(minWidth: 44, minHeight: 44)
                }
            }
            HStack(spacing: 8) {
                TextField("name@example.com", text: $newAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    .padding(10).background(CalmStyle.background, in: RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.done).onSubmit(add)
                Button("Add", action: add).buttonStyle(CalmActionStyle(prominent: true))
                    .disabled(newAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(newAddress.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }
            ForEach(store.pendingOtherAddresses.sorted(), id: \.self) { address in
                Text("\(address) will be saved when your Gmail finishes loading.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            if let problem { Text(problem).font(.lovely(.caption)).foregroundStyle(CalmStyle.roseInk) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
    private func add() {
        switch store.addOtherAddress(newAddress) {
        case .added, .pending: problem = nil; newAddress = ""
        case .invalid: problem = "That doesn't look like an email address."
        case .notSaved(let reason): problem = reason
        }
    }
}

struct ProfileCard: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            Text(value).font(.lovely(.headline))
            Text(detail).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
}


/// Owner switch for the chat walk-through, with one-tap rollback of everything it did.
struct ChatSwitchCard: View {
    @Environment(FeedStore.self) private var store
    @AppStorage(LearnedRuleStore.chatSwitchKey) private var enabled = false
    @State private var count = LearnedRuleStore().chatRules.count

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Chat walk-through", isOn: $enabled)
            Text("Adds a text box to the walk-through for sorting rules, such as hiding a sender. Rules apply only after you tap Apply.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            Button("Remove rules made in chat (\(count))", role: .destructive) { store.removeChatRules(); count = LearnedRuleStore().chatRules.count }
                .foregroundStyle(count == 0 ? CalmStyle.secondary : CalmStyle.roseInk)
                .disabled(count == 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: enabled) { _, _ in count = LearnedRuleStore().chatRules.count }
    }
}

/// Backs up what you typed to your iCloud. Mail is never backed up.
struct ICloudBackupCard: View {
    @AppStorage(SettingsSync.enabledKey) private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Back up to iCloud", isOn: $enabled)
                .onChange(of: enabled) { _, on in if on { SettingsSync.standard.start() } }
            Text("Households, kids, forwarding addresses and your Shoebox address, so a reinstall or a new iPhone gets them back. Mail and Gmail sign-in are never backed up.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Turns the opening animation (the l writing itself and the dot bouncing into place) on or off.
struct OpeningAnimationToggle: View {
    @AppStorage(LaunchAnimation.settingKey) private var on = true
    var body: some View {
        Toggle("Opening animation", isOn: $on)
            .font(.lovely(.body)).tint(CalmStyle.blue)
            .padding(.horizontal, 14).frame(minHeight: 50)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("settings.openingAnimation")
    }
}

/// Turns the split pill (Home and People pill plus Ask or search) on or off; off brings back the tab bar.
struct SplitPillToggle: View {
    @AppStorage(SplitPillBar.settingKey) private var on = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Split pill", isOn: $on).tint(CalmStyle.blue)
            Text(on ? "Home and People in a small pill, with one Ask or search field. Turn off to get the tab bar back."
                    : "Tab bar with Home, People and Search.")
                .font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("settings.splitPill")
    }
}
