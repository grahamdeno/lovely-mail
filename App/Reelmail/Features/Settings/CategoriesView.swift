import SwiftUI

/// Settings › Categories: the owner's own categories (Nov 9). Rename, hide, reorder, add; subcategories per
/// category. The rules live in CategorySettings; this view only edits them.
struct CategoriesView: View {
    @Environment(Router.self) private var router
    @State private var settings = CategorySettings.current
    @State private var adding = false
    @State private var newName = ""
    @State private var newMeaning = ""
    @State private var setup = false

    var body: some View {
        List {
            Section {
                ForEach(settings.entries) { e in
                    let d = Drawer(id: e.id)
                    Button { router.open(.category(e.id)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: d.icon).frame(width: 24).foregroundStyle(e.hidden ? CalmStyle.secondary : CalmStyle.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.title(for: d)).font(.lovely(.body, .medium))
                                    .foregroundStyle(e.hidden ? CalmStyle.secondary : CalmStyle.ink)
                                Text(e.hidden ? "Hidden" : subtitle(d)).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.lovely(.caption, .bold)).foregroundStyle(CalmStyle.secondary)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("categories.row.\(e.id)")
                }
                .onMove { settings.move(from: $0, to: $1); settings.save() }
            } header: {
                Text("Lovely files each email in one category")
            } footer: {
                Text("The specific thing wins over the kind of mail: car insurance goes in Auto, a school fee in Family. Health mail stays on this phone whatever you call it. Press and hold a row to reorder.")
            }
            .listRowBackground(CalmStyle.card)

            Section {
                Button { adding = true } label: { Label("Add a category", systemImage: "plus") }
                    .accessibilityIdentifier("categories.add")
                Button { setup = true } label: { Label("Run setup again", systemImage: "arrow.counterclockwise") }
                Button { router.open(.categoryResort) } label: { Label("Move older mail to these categories", systemImage: "arrow.triangle.branch") }
                    .accessibilityIdentifier("categories.resort")
            }
            .listRowBackground(CalmStyle.card)
        }
        .calmForm()
        .navigationTitle("Categories").navigationBarTitleDisplayMode(.inline)
        .onAppear { settings = CategorySettings.current }
        .alert("Add a category", isPresented: $adding) {
            TextField("Name, like Boat", text: $newName)
            TextField("What goes in it", text: $newMeaning)
            Button("Add") {
                settings.add(named: newName, meaning: newMeaning)
                settings.save(); newName = ""; newMeaning = ""
            }
            Button("Cancel", role: .cancel) { newName = ""; newMeaning = "" }
        } message: {
            Text("Say what goes in it, so Lovely and your AI can file mail there.")
        }
        .sheet(isPresented: $setup, onDismiss: { settings = CategorySettings.current }) { CategorySetupView() }
    }

    private func subtitle(_ d: Drawer) -> String {
        let subs = settings.subcategories(for: d)
        return subs.isEmpty ? settings.meaning(for: d) : subs.prefix(4).joined(separator: " \u{00B7} ")
    }
}

/// One category: name, what goes in it, subcategories, hide or remove.
struct CategoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var settings = CategorySettings.current
    @State private var name = ""
    @State private var meaning = ""
    @State private var newSub = ""

    private var drawer: Drawer { Drawer(id: id) }

    var body: some View {
        Form {
            Section("Name") {
                TextField(drawer.defaultTitle, text: $name)
                    .onSubmit { settings.rename(drawer, to: name); settings.save() }
                    .accessibilityIdentifier("category.name")
                Text("Gmail label: " + DrawerChoice(Drawer(id: id)).labelName).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
            }
            Section {
                TextField("What goes in it", text: $meaning, axis: .vertical)
                    .lineLimit(2...4)
                    .onSubmit { settings.setMeaning(drawer, meaning); settings.save() }
            } header: { Text("What goes in it") } footer: {
                Text("Your AI reads this line when it files mail.")
            }
            Section {
                ForEach(MailTagger.topics[drawer]?.map(\.0) ?? [], id: \.self) { Text($0) }
                ForEach(settings.extraSubcategories(for: drawer), id: \.self) { sub in
                    Text(sub)
                        .swipeActions { Button("Remove", role: .destructive) { settings.removeSubcategory(sub, from: drawer); settings.save() } }
                }
                HStack {
                    TextField("Add a subcategory", text: $newSub)
                    Button("Add") { settings.addSubcategory(newSub, to: drawer); settings.save(); newSub = "" }
                        .disabled(newSub.trimmingCharacters(in: .whitespaces).count < 3)
                }
            } header: { Text("Subcategories") } footer: {
                Text("A subcategory you add is used when its name appears in an email, and filed as a Lovely/Topic label in Gmail.")
            }
            Section {
                Toggle("Show this category", isOn: Binding(get: { !settings.isHidden(drawer) },
                                                           set: { settings.setHidden(drawer, !$0); settings.save() }))
                if !drawer.isBuiltIn {
                    Button("Remove category", role: .destructive) { settings.remove(drawer); settings.save(); dismiss() }
                }
            } footer: {
                Text(drawer.isBuiltIn ? "Hidden categories are never suggested. Mail already filed there stays in Gmail."
                                      : "Removing it doesn't touch mail already filed under its Gmail label.")
            }
        }
        .calmForm()
        .navigationTitle(settings.title(for: drawer)).navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings = CategorySettings.current
            name = settings.title(for: drawer)
            meaning = settings.meaning(for: drawer)
        }
        .onDisappear {
            // Typing without pressing Return still saves.
            var s = CategorySettings.current
            s.rename(drawer, to: name)
            s.setMeaning(drawer, meaning == drawer.defaultMeaning ? "" : meaning)
            s.save()
        }
    }
}

/// Six questions, once, that pick the starting set. Shown from Settings and on first use of the session.
struct CategorySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answers = CategorySettings.Answers()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("I own my home", isOn: $answers.ownsHome)
                    Toggle("I have a car", isOn: $answers.hasCar)
                    Toggle("Kids or family at home", isOn: $answers.hasFamily)
                    Toggle("Military or veteran", isOn: $answers.military)
                    Toggle("Side business or projects", isOn: $answers.business)
                    Toggle("Pets", isOn: $answers.pets)
                } footer: {
                    Text("Your answers pick the starting categories. You can rename, hide or add any of them later in Settings.")
                }
            }
            .calmForm()
            .navigationTitle("Set up your categories").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Keeps names, meanings and subcategories he already set; the answers only show or hide.
                        var s = CategorySettings.current
                        let fresh = CategorySettings.starting(answers)
                        for e in fresh.entries { s.setHidden(Drawer(id: e.id), e.hidden) }
                        s.setupDone = true
                        s.save()
                        dismiss()
                    }
                    .accessibilityIdentifier("categories.setup.done")
                }
            }
        }
    }
}
