import SwiftUI

/// One quiet row on Home that opens the Kids page. Shown once a child has been added in Settings.
struct KidsRow: View {
    @Environment(Router.self) private var router
    let count: Int
    var body: some View {
        Button { router.open(.kids) } label: {
            HStack(spacing: 10) {
                Text("Kids").font(.subheadline.weight(.medium)).foregroundStyle(CalmStyle.ink)
                Spacer()
                Text(count == 0 ? "Nothing new" : "\(count) in mail").font(.caption).foregroundStyle(CalmStyle.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("home.row.kids")
    }
}

/// Every child, with the mail that mentions them.
struct KidsView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let kids = InsightSettings().load().kids
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if kids.isEmpty {
                    Text("Add your children in Settings, then Lovely can gather their school and activity mail here.")
                        .font(.subheadline).foregroundStyle(CalmStyle.secondary)
                }
                ForEach(kids) { kid in
                    let next = KidInsights.next(for: kid, mail: store.kidMail(for: kid), now: Date())
                    Button { router.open(.kid(kid.id)) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kid.name).font(.headline)
                                // What's next instead of a mail count (Nov 9).
                                Text(next.map { "\($0.what) \u{00B7} \($0.when)" } ?? "Nothing coming up")
                                    .font(.subheadline).foregroundStyle(next == nil ? CalmStyle.secondary : CalmStyle.ink).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(CalmStyle.secondary)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 56).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
                Button { router.open(.insightSettings) } label: { Label("Households and kids", systemImage: "person.2").frame(maxWidth: .infinity) }
                    .buttonStyle(CalmActionStyle())
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Kids").navigationBarTitleDisplayMode(.inline)
    }
}

/// One child's page: the mail that mentions them, why it matched, and a summary of any long newsletter.
struct KidView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let kidID: String
    @State private var summaries: [String: [String]] = [:]
    @State private var working: Set<String> = []
    @State private var shoeboxPreview: ActionPreview?
    @State private var shoeboxSender: String?
    @State private var shoeboxIDs: [String] = []
    @State private var shoeboxNote: String?

    var body: some View {
        let kid = InsightSettings().load().kids.first { $0.id == kidID }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let kid {
                    let mail = store.kidMail(for: kid)
                    if mail.isEmpty { Text("No mail about \(kid.name) in your inbox right now.").font(.subheadline).foregroundStyle(CalmStyle.secondary) }
                    ForEach(mail) { item in
                        let date = MailDates.extract(item.post.email, now: Date()).first
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                            Button { router.open(.email(item.post.id)) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    if let date {
                                        Label(ComingUp.label(date, now: Date()), systemImage: "calendar")
                                            .font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.blue)
                                    }
                                    Text(item.post.summary.headline).font(.headline).multilineTextAlignment(.leading)
                                    Text(item.post.email.from.name + " · " + item.post.email.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(CalmStyle.secondary)
                                    Text(KidInsights.plainReasons(item.reasons)).font(.caption).foregroundStyle(CalmStyle.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            // Shoebox moved into a ··· menu: as a button on every card it filled the screen (Nov 9).
                            if store.actions != nil {
                                Menu {
                                    Button { Task { await prepareShoebox(item.post.email.from.email) } } label: {
                                        Label("Send this sender to Shoebox", systemImage: "tray.and.arrow.down")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
                                        .frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel("More actions")
                            }
                            }
                            if item.post.email.body.count > 1_500 {
                                if let list = summaries[item.id] {
                                    ForEach(list, id: \.self) { Text("• " + $0).font(.subheadline) }
                                    if list.isEmpty { Text("Nothing specific found.").font(.caption).foregroundStyle(CalmStyle.secondary) }
                                } else {
                                    Button(working.contains(item.id) ? "Reading…" : "Summarize on this phone") { summarize(item, kid: kid) }
                                        .font(.subheadline).disabled(working.contains(item.id))
                                }
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Text("This child is no longer in Settings.").font(.subheadline).foregroundStyle(CalmStyle.secondary)
                }
            }.padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle(kid?.name ?? "Kid").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shoeboxPreview) { p in
            ActionPreviewSheet(preview: p, confirmTitle: "Create rule") { confirmed in
                if let sender = shoeboxSender, let box = ShoeboxRule.address() { store.sendSenderToShoebox(sender: sender, shoebox: box, ids: shoeboxIDs, confirmed: confirmed) }
            }
        }
        .alert("Shoebox", isPresented: Binding(get: { shoeboxNote != nil }, set: { if !$0 { shoeboxNote = nil } })) { Button("OK") {} } message: { Text(shoeboxNote ?? "") }
    }

    private func prepareShoebox(_ sender: String) async {
        guard let box = ShoeboxRule.address(), ForwardAllowlist().contains(box) else {
            shoeboxNote = "Set your Shoebox address first: Settings, Forwarding addresses."; return
        }
        let ids = await store.shoeboxBackfillIDs(sender: sender)
        shoeboxSender = sender
        shoeboxIDs = ids
        shoeboxPreview = ShoeboxRule.preview(sender: sender, shoebox: box, count: ids.count)
    }

    private func summarize(_ item: KidMail, kid: KidProfile) {
        working.insert(item.id)
        Task {
            let list = await NewsletterSummarizer().items(from: item.post.email.body, childName: kid.name)
            summaries[item.id] = list
            working.remove(item.id)
        }
    }
}

/// Households and children, kept on this phone. Names here never leave it.
struct InsightSettingsView: View {
    @Environment(FeedStore.self) private var store
    @State private var data = InsightSettings().load()
    @State private var newKid = ""
    @State private var newHousehold = ""
    @State private var foundKids: [Discovery.Candidate] = []
    @State private var foundPlaces: [Discovery.Candidate] = []
    @State private var dismissed: Set<String> = []

    var body: some View {
        Form {
            Group {
            if !(foundKids + foundPlaces).filter({ !dismissed.contains($0.id) }).isEmpty {
                Section {
                    ForEach(foundKids.filter { !dismissed.contains($0.id) }) { c in
                        foundRow(c, detail: "Child? Seen in \(c.count) emails") { add(kid: c.name) }
                    }
                    ForEach(foundPlaces.filter { !dismissed.contains($0.id) }) { c in
                        foundRow(c, detail: (c.looksPast ? "Sold or closed? " : "Property? ") + "Seen in \(c.count) emails") {
                            data.households.append(Household(id: UUID().uuidString, name: c.name, endsOn: c.looksPast ? c.lastSeen : nil))
                            dismissed.insert(c.id)
                        }
                    }
                } header: { Text("Found in your mail") } footer: {
                    Text("Lovely only suggests these. Add the ones that are yours; they are used to tag mail and never leave this iPhone.")
                }
            }
            Section("Households") {
                ForEach($data.households) { $h in
                    VStack(alignment: .leading) {
                        TextField("Name", text: $h.name)
                        TextField("Sender domains, comma separated", text: Binding(
                            get: { h.payeeDomains.joined(separator: ", ") },
                            set: { h.payeeDomains = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }))
                            .font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Ends on a date", isOn: Binding(get: { h.endsOn != nil }, set: { h.endsOn = $0 ? (h.endsOn ?? Date()) : nil }))
                        if let end = h.endsOn { DatePicker("Ends", selection: Binding(get: { end }, set: { h.endsOn = $0 }), displayedComponents: .date) }
                    }
                }
                .onDelete { data.households.remove(atOffsets: $0) }
                HStack { TextField("Add a household", text: $newHousehold); Button("Add") { add(household: newHousehold) }.disabled(newHousehold.isEmpty) }
            }
            Section("Kids") {
                ForEach($data.kids) { $k in
                    VStack(alignment: .leading) {
                        TextField("Name", text: $k.name)
                        TextField("School", text: $k.school)
                        TextField("Teachers, comma separated", text: list($k.teacherNames))
                        TextField("Activities, comma separated", text: list($k.activities))
                    }
                }
                .onDelete { data.kids.remove(atOffsets: $0) }
                HStack { TextField("Add a child", text: $newKid); Button("Add") { add(kid: newKid) }.disabled(newKid.isEmpty) }
            }
            Section { Text("Saved on this iPhone and backed up to your iCloud. Kept when you disconnect Gmail.").font(.caption).foregroundStyle(CalmStyle.secondary) }
        }
            .listRowBackground(CalmStyle.card)
        }
        .calmForm()
        .navigationTitle("Households and kids").navigationBarTitleDisplayMode(.inline)
        .onChange(of: data) { _, new in InsightSettings().save(new) }
        .task { discover() }
    }

    private func foundRow(_ c: Discovery.Candidate, detail: String, add: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(CalmStyle.secondary)
            }
            Spacer()
            Button("Add") { add(); dismissed.insert(c.id) }.buttonStyle(.borderless)
            Button { dismissed.insert(c.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).foregroundStyle(CalmStyle.secondary).accessibilityLabel("Not mine")
        }
    }

    /// Reads the mail already on the phone and offers names and addresses, with how often each appears.
    private func discover() {
        let mails = store.posts.map { Discovery.Mail(subject: $0.email.subject, text: $0.email.body, fromAddress: $0.email.from.email, date: $0.email.date) }
        let owner = store.me.name == "You" ? "" : store.me.name
        foundKids = Discovery.kids(in: mails, ownerName: owner, known: data.kids.map(\.name))
        foundPlaces = Discovery.properties(in: mails, known: data.households.map(\.name), now: Date())
    }

    private func list(_ b: Binding<[String]>) -> Binding<String> {
        Binding(get: { b.wrappedValue.joined(separator: ", ") },
                set: { b.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }

    private func add(household name: String) { data.households.append(Household(id: UUID().uuidString, name: name)); newHousehold = "" }
    private func add(kid name: String) { data.kids.append(KidProfile(id: UUID().uuidString, name: name, school: "")); newKid = "" }
}
