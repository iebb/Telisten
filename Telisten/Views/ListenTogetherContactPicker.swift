import SwiftUI

struct ListenTogetherContactPicker: View {
    @Bindable var model: AppModel
    let session: ListenTogetherSession
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [MusicChat] = []
    @State private var selection: Set<String> = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var isInviting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Telegram contacts…")
                            .foregroundStyle(.secondary)
                    }
                } else if filteredContacts.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No Telegram contacts" : "No matching contacts",
                        systemImage: "person.2.slash",
                        description: Text(
                            query.isEmpty
                                ? "Contacts saved in Telegram will appear here."
                                : "Try a different name or username."
                        )
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredContacts) { contact in
                        contactRow(contact)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Find Telegram contacts")
            .navigationTitle("Invite Contacts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? "Invite" : "Invite \(selection.count)") {
                        Task { await inviteSelectedContacts() }
                    }
                    .disabled(selection.isEmpty || isInviting)
                }
            }
            .overlay {
                if isInviting {
                    ProgressView("Inviting…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        .task { await loadContacts() }
        .alert("Couldn’t invite contacts", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Telegram could not complete the invitation.")
        }
    }

    private func contactRow(_ contact: MusicChat) -> some View {
        Button {
            if selection.contains(contact.id) {
                selection.remove(contact.id)
            } else {
                selection.insert(contact.id)
            }
        } label: {
            HStack(spacing: 11) {
                ChatAvatar(model: model, chat: contact, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let username = contact.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: selection.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        selection.contains(contact.id) ? Color.telistenAccent : Color.secondary
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredContacts: [MusicChat] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return contacts }
        return contacts.filter {
            $0.title.localizedCaseInsensitiveContains(value)
                || $0.username?.localizedCaseInsensitiveContains(value) == true
        }
    }

    private var selectedContacts: [MusicChat] {
        contacts.filter { selection.contains($0.id) }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadContacts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            contacts = try await model.listenTogetherContacts()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func inviteSelectedContacts() async {
        let values = selectedContacts
        guard !values.isEmpty else { return }
        isInviting = true
        defer { isInviting = false }
        do {
            let invited = try await model.inviteContacts(values, to: session)
            guard invited == values.count else {
                errorMessage = "Telegram added \(invited) of \(values.count) selected contacts."
                return
            }
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
