import SwiftUI

/// The top of Home: today as up to three steps. Only the first open step is lit and has a button; finished steps
/// check off. Tap "Today" for the full brief.
struct TodayStepsCard: View {
    @Environment(Router.self) private var router
    let steps: [TodayStep]

    var body: some View {
        let done = steps.filter(\.done).count
        let active = steps.firstIndex { !$0.done }
        VStack(alignment: .leading, spacing: 14) {
            Button { router.open(.brief) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today").font(.title2.weight(.bold)).foregroundStyle(CalmStyle.ink)
                    Spacer()
                    Text(steps.isEmpty ? "Brief" : "\(done) of \(steps.count) done").font(.subheadline).foregroundStyle(CalmStyle.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("home.brief")
            if !steps.isEmpty {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CalmStyle.divider)
                        Capsule().fill(CalmStyle.blue).frame(width: max(8, g.size.width * CGFloat(done) / CGFloat(steps.count)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            if steps.isEmpty || active == nil {
                Text(steps.isEmpty ? "Nothing needs you right now." : "All done for today.")
                    .font(.headline).foregroundStyle(CalmStyle.secondary).padding(.vertical, 6)
            }
            // The lit step as a full card, the other open steps as compact rows that still say what they are and when,
            // then finished steps as single crossed-out lines (owner, Nov 9: he wants to see each step to decide).
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if index == active { row(step, number: index + 1, isActive: true) }
            }
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if !step.done, index != active { openRow(step, number: index + 1) }
            }
            ForEach(steps.filter(\.done)) { step in doneRow(step) }
        }
    }

    private func openRow(_ step: TodayStep, number: Int) -> some View {
        Button { open(step) } label: {
            HStack(alignment: .center, spacing: 12) {
                Text("\(number)").font(.subheadline.weight(.bold)).foregroundStyle(CalmStyle.secondary)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(CalmStyle.secondary.opacity(0.6), lineWidth: 2))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.subheadline.weight(.medium)).foregroundStyle(CalmStyle.ink).lineLimit(1)
                        Text(step.detail).font(.caption).foregroundStyle(CalmStyle.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CalmStyle.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(CalmStyle.card, in: RoundedRectangle(cornerRadius: 12))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.step.open")
    }

    private func doneRow(_ step: TodayStep) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(CalmStyle.blue)
                .frame(width: 24, height: 24).background(CalmStyle.blue.opacity(0.2), in: Circle())
                .frame(width: 30)
            Text(step.title).font(.footnote).strikethrough().foregroundStyle(CalmStyle.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Text(step.kind == .bill ? "Paid" : "Done").font(.caption).foregroundStyle(CalmStyle.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Done: " + step.title)
    }

    private func row(_ step: TodayStep, number: Int, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if step.done {
                    Circle().fill(CalmStyle.blue.opacity(0.2))
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(CalmStyle.blue)
                } else if isActive {
                    Circle().fill(CalmStyle.blue)
                    Text("\(number)").font(.subheadline.weight(.bold)).foregroundStyle(CalmStyle.onBlue)
                } else {
                    Circle().strokeBorder(CalmStyle.secondary.opacity(0.6), lineWidth: 2)
                    Text("\(number)").font(.subheadline.weight(.bold)).foregroundStyle(CalmStyle.secondary)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.headline).strikethrough(step.done).foregroundStyle(step.done ? CalmStyle.secondary : CalmStyle.ink)
                Text(step.detail).font(.subheadline).foregroundStyle(CalmStyle.secondary).lineLimit(2)
                if isActive {
                    Button(buttonTitle(step)) { open(step) }
                        .buttonStyle(SessionButtonStyle())
                        .padding(.top, 8)
                        .accessibilityIdentifier(step.kind == .session ? "home.session" : "home.step.active")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isActive ? CalmStyle.card : Color.clear, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isActive ? CalmStyle.blue.opacity(0.45) : CalmStyle.divider, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { if !step.done { open(step) } }
        }
    }

    private func buttonTitle(_ step: TodayStep) -> String {
        switch step.kind {
        case .answer: step.postID == nil ? "See who" : "Open"
        case .session: "Go through your inbox"
        case .bill: step.postID == nil ? "See bills" : "Open the bill"
        case .date: "Open"
        }
    }

    private func open(_ step: TodayStep) {
        switch step.kind {
        case .answer: router.open(step.postID.map { .email($0) } ?? .mailList("waiting"))
        case .session: router.open(.session)
        case .bill: router.open(step.postID.map { .email($0) } ?? .money)
        case .date: if let id = step.postID { router.open(.email(id)) }
        }
    }
}

/// "When you have a minute": everything else, as quiet chips that open their pages.
struct MinuteChips: View {
    @Environment(Router.self) private var router
    struct Chip: Identifiable { var title: String; var route: Route; var id: String { title } }
    let chips: [Chip]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHEN YOU HAVE A MINUTE").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(CalmStyle.secondary)
            WrapLayout(spacing: 8) {
                ForEach(chips) { chip in
                    Button { router.open(chip.route) } label: {
                        Text(chip.title).font(.subheadline).foregroundStyle(CalmStyle.ink)
                            .padding(.horizontal, 12).frame(minHeight: 38)
                            .background(CalmStyle.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A simple wrapping layout for chips.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

/// All the glance cards on their own page, for browsing.
struct GlanceView: View {
    @Environment(FeedStore.self) private var store
    var body: some View {
        ScrollView {
            GlanceGrid(cards: store.glanceCards).padding(20)
        }
        .background(CalmStyle.background).foregroundStyle(CalmStyle.ink)
        .navigationTitle("At a glance").navigationBarTitleDisplayMode(.inline)
    }
}
