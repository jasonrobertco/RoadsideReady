import SwiftUI

struct ArticlesSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: RescueMode
    let isFlowComplete: Bool

    @State private var query: String = ""
    @State private var selectedTag: String? = nil

    private var allForMode: [HelpArticle] { ArticlesStore.forMode(mode) }

    private var tags: [String] {
        let allTags = allForMode.flatMap(\.tags)
        return Array(Set(allTags)).sorted()
    }

    private var filtered: [HelpArticle] {
        allForMode.filter { article in
            let matchesQuery = query.isEmpty ||
                article.title.localizedCaseInsensitiveContains(query) ||
                article.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })

            let matchesTag = (selectedTag == nil) || article.tags.contains(selectedTag!)
            return matchesQuery && matchesTag
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if !isFlowComplete {
                    Text("Recommended after you finish the steps. Opening articles won’t change your place in the guide.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        tagPill("All", isOn: selectedTag == nil) { selectedTag = nil }
                        ForEach(tags, id: \.self) { tag in
                            tagPill(tag, isOn: selectedTag == tag) { selectedTag = tag }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                List {
                    Section {
                        ForEach(filtered) { article in
                            NavigationLink {
                                ArticlePreviewView(article: article)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(article.title).font(.headline)
                                    Text(article.summary).font(.footnote).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    } footer: {
                        disclaimerFooter
                    }
                }
                .listStyle(.insetGrouped)
            }
            .padding(.horizontal, 12)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed")
                        Text("Articles")
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $query)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var disclaimerFooter: some View {
        Text("Disclaimer: This information is general guidance, not professional advice. Always consult your owner’s manual for vehicle-specific procedures and safety warnings. If you feel unsafe at any point, stop and call for roadside assistance or emergency services.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .textSelection(.enabled)
    }

    private func tagPill(_ text: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ArticlePreviewView: View {
    let article: HelpArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(article.summary)
                .font(.body)
                .foregroundStyle(.secondary)

            FlowTagRow(tags: article.tags)

            NavigationLink {
                ArticleDetailView(article: article)
            } label: {
                Text("Open full article")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ArticleDetailView: View {
    let article: HelpArticle

    var body: some View {
        ScrollView {
            Text(article.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                }
            }
        }
    }
}
