import SwiftUI
import WebKit

/// A website inside the session. The engine reads the page's fields and proposes values; Lovely fills them while you
/// watch. You sign in yourself, answer anything it asks, and press the site's own Submit. Lovely never submits.
@MainActor
@Observable
final class WebFormModel: Identifiable {
    let id = UUID()
    let task: String
    let emailFacts: String
    let url: URL
    var status = "Sign in if the site asks, then tap Fill this page."
    var questions: [String] = []
    var filling = false
    @ObservationIgnored weak var webView: WKWebView?

    init(task: String, emailFacts: String, url: URL) {
        self.task = task; self.emailFacts = emailFacts; self.url = url
    }

    /// The engine for forms: the chosen cloud engine if it has a key, else the other one.
    static func filler() -> (any FormFiller)? {
        let settings = EngineSettings()
        let order: [EngineKind] = settings.engine == .grok ? [.grok, .claude] : [.claude, .grok]
        for kind in order where EngineSettings.hasKey(kind) {
            if let f = EngineRouter.engine(kind, settings: settings) as? any FormFiller { return f }
        }
        return nil
    }

    func fillPage(kids: [KidProfile]) async {
        guard let webView, !filling else { return }
        guard let filler = Self.filler() else { status = "Add a Claude or Grok key in Settings, Conversation engine, to fill forms."; return }
        filling = true
        defer { filling = false }
        status = "Reading the page…"
        do {
            let raw = try await webView.evaluateJavaScript(FormScripts.extract) as? String ?? "[]"
            let fields = (try? JSONDecoder().decode([FormField].self, from: Data(raw.utf8))) ?? []
            guard !fields.isEmpty else { status = "No fields on this page. Move to the form, then tap Fill this page."; return }
            status = "Asking \(filler.kind.name)…"
            let page = (webView.title ?? "") + " (" + (webView.url?.host ?? "") + ")"
            let user = FormFillPrompt.user(task: task, emailFacts: emailFacts, owner: OwnerDetails.load(), kids: kids, page: page, fields: fields)
            let (plan, answer) = try await filler.fillForm(system: FormFillPrompt.system, user: user)
            EngineUsage().recordCall(answer)
            let fills = FormFillValidator.validate(plan, fields: fields)
            var filled = 0
            if let script = FormScripts.apply(fills) { filled = (try? await webView.evaluateJavaScript(script) as? Int) ?? 0 }
            questions = plan.ask ?? []
            let sensitive = fields.filter(\.isSensitive).count
            var parts = [filled == 0 ? "Nothing to fill on this page." : "Filled \(filled) field\(filled == 1 ? "" : "s"), outlined in blue. Check them."]
            if sensitive > 0 { parts.append("\(sensitive) private field\(sensitive == 1 ? " is" : "s are") yours to fill.") }
            parts.append("Then press the site's own button. Lovely never submits.")
            status = parts.joined(separator: " ")
        } catch {
            status = "Could not fill this page. \(error.localizedDescription)"
        }
    }
}

struct WebFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var store
    @State var model: WebFormModel
    let done: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WebPanel(url: model.url, model: model)
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                    ForEach(model.questions, id: \.self) { q in
                        Label(q, systemImage: "questionmark.circle").font(.callout).foregroundStyle(CalmStyle.warningInk)
                    }
                    Button(model.filling ? "Working…" : "Fill this page") { Task { await model.fillPage(kids: store.sessionKids) } }
                        .buttonStyle(SessionButtonStyle()).disabled(model.filling)
                        .accessibilityIdentifier("webform.fill")
                }
                .padding(16).background(CalmStyle.background)
            }
            .navigationTitle(model.url.host ?? "Website").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { done(); dismiss() } }
            }
        }
    }
}

/// The browser panel. Sign-ins persist like Safari's so the owner signs in to a site once.
struct WebPanel: UIViewRepresentable {
    let url: URL
    let model: WebFormModel

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.allowsBackForwardNavigationGestures = true
        model.webView = view
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
