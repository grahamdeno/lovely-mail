import EventKit
import FoundationModels
import PhotosUI
import SwiftUI
import Vision

/// Apple Intelligence's reading of a calendar photo: one entry per event.
@Generable
struct PhotoCalendarEvent {
    @Guide(description: "The event title as written.")
    var title: String
    @Guide(description: "The day as YYYY-MM-DD.")
    var day: String
    @Guide(description: "Start time as HH:mm in 24-hour time, or empty for an all-day event.")
    var start: String
    @Guide(description: "End time as HH:mm in 24-hour time, or empty if not shown.")
    var end: String
}

@Generable
struct PhotoCalendarReading {
    @Guide(description: "Every event visible in the calendar picture, in time order.")
    var events: [PhotoCalendarEvent]
}

/// "Add events from a photo": pick a photo or screenshot of a calendar, check what Lovely read, and add the new ones to
/// the Work calendar (the Google calendar synced to this iPhone). Read on the phone only; nothing goes to Claude or Grok.
/// Events already there (same title, overlapping time) start unchecked. Adding waits 10 seconds for Undo.
struct PhotoEventsView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?
    @State private var phase: Phase = .start
    @State private var rows: [Row] = []
    @State private var calendars: [EKCalendar] = []
    @State private var target: EKCalendar?
    @State private var note: String?
    @State private var showCamera = false
    private let eventStore = EKEventStore()

    enum Phase: Equatable { case start, reading, review, added(Int) }

    struct Row: Identifiable, Equatable {
        var event: PhotoEvent
        var include: Bool
        var duplicate: Bool
        var id: String { event.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch phase {
                case .start: startView
                case .reading: ProgressView("Reading your calendar on this iPhone").frame(maxWidth: .infinity).padding(.top, 40)
                case .review: reviewView
                case .added(let n):
                    Label("Adding \(n) event\(n == 1 ? "" : "s") to \(target?.title ?? "Work") in 10 seconds. Undo below if that was wrong.",
                          systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(CalmStyle.green)
                    Button("Done") { dismiss() }.buttonStyle(SessionButtonStyle())
                }
                if let note { Text(note).font(.caption).foregroundStyle(CalmStyle.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("Events from a photo").navigationBarTitleDisplayMode(.inline)
        .onChange(of: pick) { _, item in if let item { Task { await read(item) } } }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                if let image { Task { await read(image) } }
            }
            .ignoresSafeArea()
        }
    }

    private var startView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Point your camera at your calendar on the computer screen. Lovely reads it on this iPhone, shows you each event, and adds the new ones to your Work calendar.")
                .font(.callout).foregroundStyle(CalmStyle.secondary)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label("Take a photo", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .buttonStyle(SessionButtonStyle())
                .accessibilityIdentifier("photoEvents.camera")
            }
            PhotosPicker(selection: $pick, matching: .images) {
                Label("Choose a photo or screenshot", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(SessionButtonStyle(prominent: !UIImagePickerController.isSourceTypeAvailable(.camera)))
            .accessibilityIdentifier("photoEvents.pick")
            Text("Nothing is sent to Claude or Grok. Events already on your calendar at the same time with the same title are skipped.")
                .font(.caption).foregroundStyle(CalmStyle.secondary)
        }
    }

    private var reviewView: some View {
        let chosen = rows.filter(\.include).count
        let byDay = Dictionary(grouping: rows.indices, by: { Calendar.current.startOfDay(for: rows[$0].event.start) }).sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 12) {
            Text(rows.isEmpty ? "No events found in that picture." : "\(rows.count) event\(rows.count == 1 ? "" : "s") found. Check them, then add.")
                .font(.headline)
            ForEach(byDay, id: \.key) { entry in
                Text(entry.key.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.caption.weight(.semibold))
                    .foregroundStyle(CalmStyle.secondary).padding(.top, 6)
                ForEach(entry.value, id: \.self) { i in row(i) }
            }
            if !calendars.isEmpty {
                Picker("Calendar", selection: Binding(get: { target?.calendarIdentifier ?? "" },
                                                      set: { id in target = calendars.first { $0.calendarIdentifier == id } })) {
                    ForEach(calendars, id: \.calendarIdentifier) { Text($0.title + " · " + $0.source.title).tag($0.calendarIdentifier) }
                }
                .pickerStyle(.menu)
            }
            if target?.title.lowercased() != "work" {
                Text("No calendar named Work on this iPhone yet. Create a calendar called Work in Google Calendar, then turn it on at calendar.google.com/calendar/syncselect so it shows here.")
                    .font(.caption).foregroundStyle(CalmStyle.warningInk).fixedSize(horizontal: false, vertical: true)
            }
            Button(chosen == 0 ? "Nothing to add" : "Add \(chosen) to \(target?.title ?? "Work")") { add() }
                .buttonStyle(SessionButtonStyle()).disabled(chosen == 0 || target == nil)
                .accessibilityIdentifier("photoEvents.add")
            Button("Try another photo") { rows = []; pick = nil; phase = .start }
                .font(.subheadline.weight(.medium)).foregroundStyle(CalmStyle.blue).frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func row(_ i: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { rows[i].include.toggle() } label: {
                Image(systemName: rows[i].include ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(rows[i].include ? CalmStyle.blue : CalmStyle.secondary)
            }.buttonStyle(.plain).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $rows[i].event.title).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    DatePicker("", selection: $rows[i].event.start, displayedComponents: [.hourAndMinute]).labelsHidden()
                    Text("to").font(.caption).foregroundStyle(CalmStyle.secondary)
                    DatePicker("", selection: $rows[i].event.end, displayedComponents: [.hourAndMinute]).labelsHidden()
                }
                if rows[i].duplicate {
                    Label("Already on your calendar", systemImage: "equal.circle").font(.caption).foregroundStyle(CalmStyle.secondary)
                } else if rows[i].event.unsure {
                    Label("Check this one", systemImage: "questionmark.circle").font(.caption).foregroundStyle(CalmStyle.warningInk)
                }
            }
        }
        .padding(10).opacity(rows[i].include ? 1 : 0.55)
        .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Reading

    private func read(_ item: PhotosPickerItem) async {
        phase = .reading; note = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            note = "That picture could not be opened."; phase = .start; return
        }
        await read(image)
    }

    private func read(_ image: UIImage) async {
        phase = .reading; note = nil
        guard let cg = Self.upright(image).cgImage else { note = "That picture could not be opened."; phase = .start; return }
        let lines = await Self.recognize(cg)
        var events = await Self.interpret(lines)
        if events.isEmpty { events = PhotoEvents.parse(lines, now: Date()) }
        await loadCalendars()
        let existing = existingEvents(around: events)
        rows = events.map { e in
            let dup = PhotoEvents.isDuplicate(e, of: existing)
            return Row(event: e, include: !dup, duplicate: dup)
        }
        phase = .review
    }

    /// Camera photos carry a rotation flag; text recognition needs the pixels upright.
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        return UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    /// Apple's on-device text recognition, with where each line sits.
    static func recognize(_ image: CGImage) async -> [PhotoTextLine] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? []).compactMap { o -> PhotoTextLine? in
                    guard let text = o.topCandidates(1).first?.string else { return nil }
                    return PhotoTextLine(text: text, x: o.boundingBox.minX, y: 1 - o.boundingBox.maxY)
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { continuation.resume(returning: []) }
        }
    }

    /// Apple Intelligence turns the lines (with their positions, so a week grid's columns can be matched to days) into events.
    static func interpret(_ lines: [PhotoTextLine]) async -> [PhotoEvent] {
        guard ModelStatus.current.isAvailable, !lines.isEmpty else { return [] }
        let today = Date().formatted(.iso8601.year().month().day())
        let text = lines.prefix(250).map { String(format: "[x=%.2f y=%.2f] ", $0.x, $0.y) + $0.text }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
        You read text recognized from a picture of a calendar (a week grid, a day view or an agenda list). Each line has its \
        position: x is left to right, y is top to bottom, both from 0 to 1. In a week grid, day names and dates sit in a header \
        row and each event sits under its day's column; hour labels on the left give the times. Today is \(today). List every \
        event once. Never invent events that are not in the text.
        """)
        guard let response = try? await session.respond(to: text, generating: PhotoCalendarReading.self,
                                                        options: GenerationOptions(temperature: 0)) else { return [] }
        return response.content.events.compactMap { e in
            guard let start = PhotoEvents.date(e.day, e.start) else { return nil }
            let allDay = e.start.isEmpty
            let end = (e.end.isEmpty ? nil : PhotoEvents.date(e.day, e.end)).flatMap { $0 > start ? $0 : nil }
                ?? start.addingTimeInterval(allDay ? 86_400 : 1_800)
            let title = e.title.trimmingCharacters(in: .whitespaces)
            return PhotoEvent(title: title.isEmpty ? "Untitled" : title, start: start, end: end, allDay: allDay,
                              unsure: title.count < 3 || e.end.isEmpty)
        }
    }

    // MARK: Calendar

    private func loadCalendars() async {
        let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        guard granted else { note = "Lovely needs calendar access to check for duplicates and add events. Turn it on in Settings > Apps > Lovely."; return }
        calendars = eventStore.calendars(for: .event).filter(\.allowsContentModifications).sorted { $0.title < $1.title }
        target = calendars.first { $0.title.lowercased() == "work" && $0.source.title.lowercased().contains("gmail") }
            ?? calendars.first { $0.title.lowercased() == "work" }
            ?? target
    }

    private func existingEvents(around events: [PhotoEvent]) -> [(title: String, start: Date, end: Date)] {
        guard let first = events.map(\.start).min(), let last = events.map(\.end).max(),
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: first.addingTimeInterval(-3_600), end: last.addingTimeInterval(3_600), calendars: nil)
        return eventStore.events(matching: predicate).map { ($0.title ?? "", $0.startDate, $0.endDate) }
    }

    private func add() {
        guard let target else { return }
        let chosen = rows.filter(\.include).map(\.event)
        let calendarID = target.calendarIdentifier
        let store = eventStore
        self.store.undo.enqueue(title: "Adding \(chosen.count) event\(chosen.count == 1 ? "" : "s") to \(target.title)", work: {
            guard let calendar = store.calendar(withIdentifier: calendarID) else { return }
            for e in chosen {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = e.title
                event.startDate = e.start
                event.endDate = e.end
                event.isAllDay = e.allDay
                try store.save(event, span: .thisEvent, commit: false)
            }
            try store.commit()
        }, finished: { error in
            if let error { self.store.errorMessage = "The events were not added. \(error.localizedDescription)" }
        })
        phase = .added(chosen.count)
    }
}

/// The iPhone camera, for photographing a calendar on a computer screen. The photo is read on the phone and not saved.
struct CameraCapture: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
