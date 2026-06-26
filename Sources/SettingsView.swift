import SwiftUI

struct SettingsView: View {
    @Binding var serverIP: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Адрес BIM Scanner на ПК") {
                    TextField("192.168.1.20", text: $draft)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Text("Узнать IP: на ПК в консоли BIM Scanner написан адрес при запуске.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                            serverIP = draft.trimmingCharacters(in: .whitespaces)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onAppear { draft = serverIP }
        }
    }
}
