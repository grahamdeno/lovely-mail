import SwiftUI

/// Search runs locally over the loaded mail and its on-device summaries.
struct SearchView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScreenScaffold(title: "Search") {
            VStack(spacing: RM.Space.m) {
                HStack(spacing: RM.Space.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(RM.Palette.secondary)
                    TextField("", text: $query, prompt: Text("People, subjects, anything").foregroundStyle(RM.Palette.secondary))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, RM.Space.m)
                .frame(height: 44)
                .background(RM.Palette.surface)
                .rmCorner(RM.Radius.button)
                .padding([.horizontal, .top], RM.Space.l)

                ScrollView {
                    LazyVStack(spacing: RM.Space.s) {
                        let results = store.search(query)
                        if query.isEmpty {
                            Text("Search stays on your phone.")
                                .font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
                                .padding(.top, RM.Space.xl)
                        } else if results.isEmpty {
                            Text("No matches").font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
                                .padding(.top, RM.Space.xl)
                        }
                        ForEach(results) { post in
                            PostRow(post: post).onTapGesture { router.open(.email(post.id)) }
                        }
                    }
                    .padding(.horizontal, RM.Space.l)
                }
            }
        }
        .onAppear { focused = true }
    }
}
