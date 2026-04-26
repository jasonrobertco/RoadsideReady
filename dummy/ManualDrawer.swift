import SwiftUI

struct ManualDrawer: View {
    @Binding var isPresented: Bool
    let mode: RescueMode
    let isFlowComplete: Bool
    
    @State private var query: String = ""
    @State private var selectedTag: String? = nil
    
    private var allForMode: [HelpArticle] { ArticlesStore.forMode(mode) }
    
    private var tags: [String] {
        Array(Set(allForMode.flatMap(\.tags))).sorted()
    }
    
    private var filtered: [HelpArticle] {
        allForMode.filter { a in
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = q.isEmpty ||
            a.title.localizedCaseInsensitiveContains(q) ||
            a.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            
            let matchesTag = (selectedTag == nil) || a.tags.contains(selectedTag!)
            return matchesQuery && matchesTag
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "newspaper")
                        Text("Articles").font(.headline)
                    }
                    Spacer()
                    Button("Done") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            isPresented = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                
                if !isFlowComplete {
                    Text("Recommended after you finish the steps. This won’t change your place in the guide.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)
                }
                
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        tagPill("All", isOn: selectedTag == nil) { selectedTag = nil }
                        ForEach(tags, id: \.self) { tag in
                            tagPill(tag, isOn: selectedTag == tag) { selectedTag = tag }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                List(filtered) { article in
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
                .listStyle(.insetGrouped)
                
                Spacer(minLength: 0)
            }
            .background(Color(uiColor: .systemBackground))
        }
        .background(Color(uiColor: .systemBackground))
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
                .foregroundStyle(.secondary)
            
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
