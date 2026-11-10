import Foundation

/// The owner's categories: order, names, what goes in, hidden ones, extra subcategories, and categories he added.
/// Kept on this phone. Pure apart from load/save, so it is tested. See docs/calm-feed.md (Nov 9, categories).
struct CategorySettings: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        var id: String
        /// Nil keeps the built-in name.
        var title: String?
        /// Nil keeps the built-in meaning. For a category he added, this is the line engines read.
        var meaning: String?
        var hidden = false
        /// Subcategories he added. Each becomes a topic tag (Lovely/Topic/<name>) when its name appears in the mail.
        var extraSubcategories: [String] = []
    }

    var entries: [Entry]
    var setupDone = false

    /// Answers to the six setup questions, which pick the starting set.
    struct Answers: Codable, Equatable, Sendable {
        var ownsHome = true
        var hasCar = true
        var hasFamily = true
        var military = false
        var business = false
        var pets = false
    }

    static let `default` = CategorySettings(entries: Drawer.builtIns.map { Entry(id: $0.id, hidden: $0 == .pets) })

    /// The starting set for these answers. Renters still get Home (rent, renters insurance, utilities).
    static func starting(_ a: Answers) -> CategorySettings {
        var s = CategorySettings.default
        s.setHidden(.auto, !a.hasCar)
        s.setHidden(.family, !a.hasFamily)
        s.setHidden(.government, !a.military)
        s.setHidden(.projects, !a.business)
        s.setHidden(.pets, !a.pets)
        s.setupDone = true
        return s
    }

    // MARK: Reading

    var visible: [Drawer] { entries.filter { !$0.hidden }.map { Drawer(id: $0.id) } }
    var all: [Drawer] { entries.map { Drawer(id: $0.id) } }

    func entry(_ d: Drawer) -> Entry? { entries.first { $0.id == d.id } }

    func title(for d: Drawer) -> String {
        let t = entry(d)?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? d.defaultTitle : t
    }

    func meaning(for d: Drawer) -> String {
        let m = entry(d)?.meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return m.isEmpty ? d.defaultMeaning : m
    }

    /// A category not in the list (an old saved choice for a removed custom one) counts as hidden.
    func isHidden(_ d: Drawer) -> Bool { entry(d)?.hidden ?? true }

    func extraSubcategories(for d: Drawer) -> [String] { entry(d)?.extraSubcategories ?? [] }

    var extraSubcategoryMap: [String: [String]] {
        Dictionary(uniqueKeysWithValues: entries.filter { !$0.extraSubcategories.isEmpty }.map { ($0.id, $0.extraSubcategories) })
    }

    /// Built-in subcategory names (topic tags) plus the ones he added, for Settings.
    func subcategories(for d: Drawer) -> [String] {
        (MailTagger.topics[d] ?? []).map(\.0) + extraSubcategories(for: d)
    }

    // MARK: Changing

    mutating func setHidden(_ d: Drawer, _ hidden: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == d.id }) else { return }
        entries[i].hidden = hidden
    }

    /// Renames a category. Slashes would make a deeper Gmail label, so they become dashes. Empty restores the
    /// built-in name.
    mutating func rename(_ d: Drawer, to name: String) {
        guard let i = entries.firstIndex(where: { $0.id == d.id }) else { return }
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        entries[i].title = clean.isEmpty || clean == d.defaultTitle ? nil : String(clean.prefix(30))
    }

    mutating func setMeaning(_ d: Drawer, _ text: String) {
        guard let i = entries.firstIndex(where: { $0.id == d.id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[i].meaning = clean.isEmpty ? nil : String(clean.prefix(200))
    }

    /// Adds a category of his own. Returns nil when the name is empty or already used.
    @discardableResult
    mutating func add(named name: String, meaning: String = "") -> Drawer? {
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !entries.contains(where: { title(for: Drawer(id: $0.id)).lowercased() == clean.lowercased() }) else { return nil }
        let slug = clean.lowercased().filter { $0.isLetter || $0.isNumber }
        var id = "c-" + (slug.isEmpty ? "category" : String(slug.prefix(20)))
        var n = 2
        while entries.contains(where: { $0.id == id }) || Drawer.builtIns.contains(Drawer(id: id)) { id = "c-\(slug)\(n)"; n += 1 }
        entries.append(Entry(id: id, title: String(clean.prefix(30)), meaning: meaning.isEmpty ? nil : meaning))
        return Drawer(id: id)
    }

    /// Removes a category he added. Built-in ones can only be hidden.
    mutating func remove(_ d: Drawer) {
        guard !d.isBuiltIn else { return }
        entries.removeAll { $0.id == d.id }
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        // Plain array move, without SwiftUI's helper, so this stays a pure Foundation type.
        let moving = source.sorted().map { entries[$0] }
        var rest = entries.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let before = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(rest.count, destination - before)))
        entries = rest
    }

    mutating func addSubcategory(_ name: String, to d: Drawer) {
        guard let i = entries.firstIndex(where: { $0.id == d.id }) else { return }
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3, !entries[i].extraSubcategories.contains(where: { $0.lowercased() == clean.lowercased() }) else { return }
        entries[i].extraSubcategories.append(String(clean.prefix(30)))
    }

    mutating func removeSubcategory(_ name: String, from d: Drawer) {
        guard let i = entries.firstIndex(where: { $0.id == d.id }) else { return }
        entries[i].extraSubcategories.removeAll { $0 == name }
    }

    /// Keeps every built-in present (a new built-in added in a later version joins at the end, hidden if it is Pets).
    func completed() -> CategorySettings {
        var s = self
        for b in Drawer.builtIns where !s.entries.contains(where: { $0.id == b.id }) {
            s.entries.append(Entry(id: b.id, hidden: b == .pets))
        }
        return s
    }

    // MARK: Storage

    static let key = "lovely.categories.v1"
    nonisolated(unsafe) private static var cache: CategorySettings?

    /// The saved settings, read once and kept in memory; `save` refreshes it.
    static var current: CategorySettings {
        if let c = cache { return c }
        let loaded = load()
        cache = loaded
        return loaded
    }

    static func load(defaults: UserDefaults = .standard) -> CategorySettings {
        guard let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(CategorySettings.self, from: data) else { return .default }
        return s.completed()
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
        if defaults == .standard { Self.cache = self }
    }

    /// For tests: forget the in-memory copy.
    static func resetCache() { cache = nil }
}
