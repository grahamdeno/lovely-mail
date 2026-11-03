import Contacts
import Foundation
import Observation
import UIKit

/// Pictures for avatars, both optional and both kept on this phone:
/// - People: the photo from your own Contacts, matched by email address. Nothing leaves the phone.
/// - Organizations: the company's own icon, fetched once from the company's own website (never a third-party
///   icon service, never for people or shared domains like gmail.com) and cached. Turn off in Settings.
@MainActor
@Observable
final class AvatarImages {
    static let shared = AvatarImages()

    private(set) var contactPhotos: [String: UIImage] = [:]
    private(set) var logos: [String: UIImage] = [:]
    private(set) var contactsStatus: String = ""

    var showLogos: Bool {
        didSet { defaults.set(showLogos, forKey: Self.logosKey); if !showLogos { logos = [:] } }
    }
    private(set) var useContacts: Bool

    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private let defaults: UserDefaults
    private static let logosKey = "lovely.avatars.logos"
    private static let contactsKey = "lovely.avatars.contacts"
    /// A failed logo lookup is retried after a week.
    private static let retryAfter: TimeInterval = 7 * 86_400

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showLogos = defaults.object(forKey: Self.logosKey) as? Bool ?? true
        useContacts = defaults.bool(forKey: Self.contactsKey)
        if useContacts, Self.contactsAllowed { loadContacts() }
    }

    // MARK: People, from Contacts

    func contactPhoto(for address: String) -> UIImage? {
        guard useContacts else { return nil }
        return contactPhotos[TriageContext.canonical(address)]
    }

    private static var contactsAllowed: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        return false
    }

    /// Asks for Contacts access (the system shows its own prompt once) and loads photos.
    func setUseContacts(_ on: Bool) async {
        guard on else {
            useContacts = false; contactPhotos = [:]; defaults.set(false, forKey: Self.contactsKey); return
        }
        let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        useContacts = granted
        defaults.set(granted, forKey: Self.contactsKey)
        contactsStatus = granted ? "" : "Contacts access is off. Turn it on in iPhone Settings > Apps > Lovely > Contacts."
        if granted { loadContacts() }
    }

    private func loadContacts() {
        Task.detached(priority: .utility) {
            var found: [String: Data] = [:]
            let keys = [CNContactEmailAddressesKey, CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                guard let data = contact.thumbnailImageData else { return }
                for email in contact.emailAddresses { found[TriageContext.canonical(email.value as String)] = data }
            }
            let images = found.compactMapValues { UIImage(data: $0) }
            await MainActor.run { AvatarImages.shared.contactPhotos = images }
        }
    }

    // MARK: Organizations, from their own websites

    /// The company's icon if already fetched; otherwise starts one fetch and returns nil.
    func logo(for domain: String?) -> UIImage? {
        guard showLogos, let domain, Self.fetchable(domain) else { return nil }
        if let image = logos[domain] { return image }
        if !requested.contains(domain) {
            requested.insert(domain)
            Task { await self.fetchLogo(domain) }
        }
        return nil
    }

    /// Fictional and local domains are never fetched (demo mail, tests).
    static func fetchable(_ domain: String) -> Bool {
        !(domain.hasSuffix(".example") || domain.hasSuffix(".test") || domain.hasSuffix(".local") || domain.hasSuffix(".invalid"))
            && OrganizationKey.domain(of: "x@" + domain) == domain
    }

    private static var cacheFolder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("lovely-logos", isDirectory: true)
    }

    private func fetchLogo(_ domain: String) async {
        let folder = Self.cacheFolder
        let file = folder.appendingPathComponent(domain + ".png")
        let miss = folder.appendingPathComponent(domain + ".none")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { logos[domain] = image; return }
        if let date = (try? miss.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(date) < Self.retryAfter { return }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let candidates = ["https://\(domain)/apple-touch-icon.png", "https://www.\(domain)/apple-touch-icon.png",
                          "https://\(domain)/favicon.ico", "https://www.\(domain)/favicon.ico"]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            var request = URLRequest(url: url)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count < 400_000, let image = UIImage(data: data),
                  min(image.size.width * image.scale, image.size.height * image.scale) >= 16 else { continue }
            if let png = image.pngData() { try? png.write(to: file) }
            logos[domain] = image
            return
        }
        try? Data().write(to: miss)
    }
}
