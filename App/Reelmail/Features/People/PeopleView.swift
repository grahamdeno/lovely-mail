import SwiftUI

struct PeopleView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: RM.Space.m)]

    var body: some View {
        ScreenScaffold(title: "People") {
            ScrollView {
                LazyVGrid(columns: columns, spacing: RM.Space.l) {
                    ForEach(store.people) { person in
                        Button { router.open(.person(person)) } label: {
                            VStack(spacing: 6) {
                                AvatarView(person: person, size: 72, needsReply: store.needsReply(person))
                                Text(person.name).font(RM.Typo.caption).foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(RM.Space.l)
            }
        }
    }
}
