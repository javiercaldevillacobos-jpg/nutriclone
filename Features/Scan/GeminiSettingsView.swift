import SwiftUI

/// Ajustes del escáner de platos: clave propia de Gemini (BYOK) guardada en el Llavero.
struct GeminiSettingsView: View {
    static let aiStudioKeyURL = URL(string: "https://aistudio.google.com/apikey")!

    @Environment(\.dismiss) private var dismiss
    @AppStorage("didAcknowledgeFreeTier") private var didAcknowledgeFreeTier = false
    @AppStorage(GeminiModel.storageKey) private var modelRaw = GeminiModel.default.rawValue

    @State private var draftKey = ""
    @State private var hasSavedKey = KeychainService.shared.geminiAPIKey != nil
    @State private var message: String?
    @State private var confirmingDelete = false

    /// true cuando se abre como hoja desde el escáner (muestra "Cerrar").
    var presentedAsSheet = false

    private var trimmedKey: String { draftKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Estado") {
                    Label(hasSavedKey ? "Clave guardada" : "Sin clave",
                          systemImage: hasSavedKey ? "checkmark.seal.fill" : "key")
                        .foregroundStyle(hasSavedKey ? Color.green : Color.secondary)
                }
                SecureField(hasSavedKey ? "Pega una clave nueva para cambiarla" : "Pega aquí tu clave de API", text: $draftKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.body.monospaced())
                Button("Guardar clave", action: saveKey)
                    .disabled(trimmedKey.isEmpty || !didAcknowledgeFreeTier)
                if hasSavedKey {
                    Button("Borrar clave", role: .destructive) { confirmingDelete = true }
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Clave de Gemini")
            } footer: {
                Text("La clave se guarda solo en el Llavero de este iPhone. No se copia a iCloud ni sale del teléfono salvo para hablar con Google.")
            }

            Section {
                Link(destination: Self.aiStudioKeyURL) {
                    Label("Conseguir una clave gratis en Google AI Studio", systemImage: "arrow.up.right.square")
                }
                Text("Esta app usa el nivel gratuito de la API de Gemini. No requiere tarjeta de crédito ni genera ningún coste. Si en Google AI Studio vinculas una cuenta de facturación, estarías saliendo del nivel gratuito: no lo hagas.")
                    .font(.footnote)
            } header: {
                Text("Cómo conseguirla")
            }

            Section {
                Toggle(isOn: $didAcknowledgeFreeTier) {
                    Text("He leído el aviso y no vincularé facturación al proyecto de esta clave")
                }
            } header: {
                Text("Aviso de coste")
            } footer: {
                Text("⚠️ Esta app usa el nivel gratuito de Gemini. NO vincules una cuenta de facturación en Google AI Studio mientras uses esta app, o estarías saliendo del nivel gratuito. Con el nivel gratuito, el coste es siempre 0 €.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.over)
            }

            Section {
                Picker("Modelo", selection: $modelRaw) {
                    ForEach(GeminiModel.allCases) { model in
                        Text(model.title).tag(model.rawValue)
                    }
                }
            } header: {
                Text("Modelo")
            } footer: {
                Text("Ambos son de la familia Flash con nivel gratuito. Si te sale a menudo el aviso de límite, prueba Flash-Lite. Los límites diarios dependen de tu proyecto y se ven en aistudio.google.com/rate-limit.")
            }

            Section {
                Text("Con el nivel gratuito, Google puede usar las fotos que envías para mejorar sus productos. Envía solo fotos de comida y evita que salgan personas, documentos o pantallas.")
                    .font(.footnote)
                Text("La app no puede ver si tu proyecto de Google tiene facturación activada: eso solo lo controlas tú en Google AI Studio.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacidad")
            }
        }
        .navigationTitle("Escáner de platos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .confirmationDialog("¿Borrar la clave de Gemini?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Borrar clave", role: .destructive, action: deleteKey)
        } message: {
            Text("El escáner de platos dejará de funcionar hasta que pegues otra.")
        }
    }

    private func saveKey() {
        do {
            try KeychainService.shared.save(trimmedKey, account: KeychainService.geminiAPIKeyAccount)
            draftKey = ""
            hasSavedKey = true
            message = "Clave guardada. Ya puedes escanear platos desde Añadir alimento."
        } catch {
            message = "No se pudo guardar la clave en el Llavero (\(error))."
        }
    }

    private func deleteKey() {
        do {
            try KeychainService.shared.delete(account: KeychainService.geminiAPIKeyAccount)
            hasSavedKey = false
            message = "Clave borrada."
        } catch {
            message = "No se pudo borrar la clave (\(error))."
        }
    }
}
