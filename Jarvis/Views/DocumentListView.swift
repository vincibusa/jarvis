import SwiftUI

struct DocumentListView: View {

    @Environment(\.dismiss) private var dismiss

    let documentService: DocumentService

    @State private var documents: [Document] = []
    @State private var showPicker = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if documents.isEmpty && !isImporting {
                    emptyState
                } else {
                    documentList
                }

                if isImporting {
                    importingOverlay
                }
            }
            .navigationTitle("Documenti")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isImporting)
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPickerView { url in
                    Task {
                        await importDocument(from: url)
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Errore importazione", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Errore sconosciuto")
            }
            .preferredColorScheme(.dark)
        }
        .onAppear {
            documents = documentService.listDocuments()
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.gray)
            Text("Nessun documento")
                .font(.title2)
                .foregroundStyle(.white)
            Text("Importa PDF, testo o documenti Word\nper farli cercare a Jarvis.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
                .font(.subheadline)
            Button {
                showPicker = true
            } label: {
                Label("Importa documento", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .foregroundStyle(.white)
            .padding(.top, 8)
        }
        .padding()
    }

    private var documentList: some View {
        List {
            ForEach(documents) { doc in
                DocumentRow(document: doc)
                    .listRowBackground(Color.white.opacity(0.05))
            }
            .onDelete { indexSet in
                Task {
                    for index in indexSet {
                        let doc = documents[index]
                        await documentService.deleteDocument(id: doc.id)
                    }
                    documents = documentService.listDocuments()
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var importingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
            Text("Importazione in corso…")
                .foregroundStyle(.white)
                .font(.subheadline)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions

    private func importDocument(from url: URL) async {
        isImporting = true
        defer {
            isImporting = false
            documents = documentService.listDocuments()
        }

        do {
            _ = try await documentService.importDocument(url: url)
        } catch {
            importError = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Document row

private struct DocumentRow: View {

    let document: Document

    private var icon: String {
        switch document.fileType.lowercased() {
        case "pdf":  return "doc.richtext"
        case "docx": return "doc.text"
        case "csv":  return "tablecells"
        default:     return "doc.plaintext"
        }
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "it_IT")
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: document.importedAt)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .foregroundStyle(.white)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(".\(document.fileType.uppercased())")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .foregroundStyle(.gray)

                    Text("\(document.chunkCount) sezioni")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    Text("·")
                        .foregroundStyle(.gray)

                    Text(dateString)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
