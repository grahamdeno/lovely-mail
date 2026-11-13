import SwiftUI
import MessageUI
import ContactsUI

/// Pick a person, check the draft, open Messages. One decision per screen: the person is the decision;
/// the draft is ready to send as is.
struct TextAboutSheet: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var recipients = TextRecipients().all
    @State private var chosen: TextRecipient?
    @State private var draft = ""
    @State private var picking = false
    /// What goes to Messages, copied from the editor at the moment of the tap. The old `composing` flag let the
    /// Messages sheet read `draft` through a closure SwiftUI had built earlier, so an edited draft could go out as
    /// the original suggestion (Nov 9).
    @State private var outgoing: OutgoingText?
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("WHO?").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
                    if recipients.isEmpty {
                        Text("Pick someone from your contacts. Next time they'll be right here.")
                            .font(.lovely(.callout)).foregroundStyle(CalmStyle.secondary)
                    }
                    ForEach(recipients) { r in
                        Button { chosen = r } label: {
                            HStack {
                                Image(systemName: chosen == r ? "checkmark.circle.fill" : "circle").foregroundStyle(CalmStyle.blue)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.name).font(.lovely(.body, .medium))
                                    Text(r.phone).font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                                }
                                Spacer()
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Remove from this list", role: .destructive) { TextRecipients().forget(r); recipients = TextRecipients().all } }
                    }
                    Button { picking = true } label: { Label("Choose from Contacts", systemImage: "person.crop.circle.badge.plus") }
                        .frame(minHeight: 44).foregroundStyle(CalmStyle.blue).accessibilityIdentifier("textAbout.pick")

                    Text("MESSAGE").font(.lovely(.caption, .semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary).padding(.top, 6)
                    TextEditor(text: $draft)
                        .focused($editing)
                        .frame(minHeight: 140).scrollContentBackground(.hidden)
                        .padding(10).background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("textAbout.draft")
                    Text("Opens Messages with this filled in. You tap Send there.").font(.lovely(.caption)).foregroundStyle(CalmStyle.secondary)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button(chosen.map { "Text \($0.firstName)" } ?? "Choose someone first") { open() }
                    .buttonStyle(SessionButtonStyle()).disabled(chosen == nil)
                    .padding(.horizontal, 20).padding(.vertical, 10).background(CalmStyle.background)
                    .accessibilityIdentifier("textAbout.send")
            }
            .background(CalmStyle.background).foregroundStyle(CalmStyle.ink).tint(CalmStyle.blue)
            .navigationTitle("Text about this email").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .onAppear {
            if draft.isEmpty {
                let date = MailDates.extract(post.email, now: Date()).first.map { ComingUp.fullLabel($0) }
                draft = TextAbout.draft(fromName: post.email.from.name, subject: post.email.subject, blurb: post.summary.blurb,
                                        sensitive: post.summary.sensitive, dateLabel: date)
            }
            chosen = chosen ?? recipients.first
        }
        .sheet(isPresented: $picking) {
            ContactPhonePicker { r in
                TextRecipients().remember(r); recipients = TextRecipients().all; chosen = r
            }
            .ignoresSafeArea()
        }
        .sheet(item: $outgoing) { text in
            MessageComposer(recipient: text.phone, body: text.body) { sent in
                outgoing = nil
                if sent { dismiss() }
            }
            .ignoresSafeArea()
        }
    }

    private func open() {
        guard chosen != nil else { return }
        editing = false                       // ends the keyboard's pending word so it lands in the draft
        DispatchQueue.main.async { send() }   // read the draft after that last word is in
    }

    private func send() {
        guard let chosen else { return }
        TextRecipients().remember(chosen)
        let body = draft
        if MFMessageComposeViewController.canSendText() {
            outgoing = OutgoingText(phone: chosen.phone, body: body)
        } else if let url = Self.smsURL(phone: chosen.phone, body: body) {
            openURL(url); dismiss()
        }
    }

    static func smsURL(phone: String, body: String) -> URL? {
        var c = URLComponents(); c.scheme = "sms"; c.path = TextRecipients.normalized(phone)
        c.queryItems = [URLQueryItem(name: "body", value: body)]
        return c.url
    }
}

/// The text as it was when the owner tapped Text: a fixed copy, so nothing can swap it for an older draft.
struct OutgoingText: Identifiable, Equatable {
    let id = UUID()
    let phone: String
    let body: String
}

/// Apple's contact picker, phone numbers only. Needs no Contacts permission: Lovely sees only the number picked.
struct ContactPhonePicker: UIViewControllerRepresentable {
    let picked: (TextRecipient) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        vc.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        vc.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let picked: (TextRecipient) -> Void
        init(picked: @escaping (TextRecipient) -> Void) { self.picked = picked }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
            guard let number = (property.value as? CNPhoneNumber)?.stringValue else { return }
            let name = CNContactFormatter.string(from: property.contact, style: .fullName) ?? number
            picked(TextRecipient(name: name, phone: number))
        }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let number = contact.phoneNumbers.first?.value.stringValue else { return }
            picked(TextRecipient(name: CNContactFormatter.string(from: contact, style: .fullName) ?? number, phone: number))
        }
    }
}

/// Apple's Messages sheet with the recipient and text filled in. The owner taps Send.
struct MessageComposer: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    let done: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = [recipient]
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            done(result == .sent)
        }
    }
}
