import SwiftUI

// MARK: - Inspector

struct ImageInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let image = model.selectedImage {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text(image.prompt).textSelection(.enabled)
                    }
                    if let negative = image.negativePrompt, !negative.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Negative prompt").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Text(negative).textSelection(.enabled)
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        row("Size", "\(image.width) × \(image.height)")
                        row("Seed", image.seed.map(String.init) ?? "–")
                        row("Steps", image.steps.map(String.init) ?? "–")
                        if image.mode == "RGBA" { row("Alpha", "Transparent") }
                        if let refs = image.referenceImages, !refs.isEmpty { row("References", "\(refs.count)") }
                        row("Took", image.durationS.durationString)
                        row("Model", model.models.first { $0.id == image.modelId }?.name ?? image.modelId)
                        row("Source", image.isFromMCP ? "MCP client" : "App")
                        row("Created", image.createdDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.callout)

                    VStack(spacing: 8) {
                        Button {
                            model.reuseSettings(of: image)
                        } label: {
                            Label("Use Settings", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                        }
                        Button {
                            model.addReference(image.url)
                        } label: {
                            Label("Edit This Image", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                        }
                        HStack {
                            Button { Clipboard.copyImage(at: image.url) } label: {
                                Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                            }
                            Button { NSWorkspace.shared.activateFileViewerSelecting([image.url]) } label: {
                                Label("Finder", systemImage: "folder").frame(maxWidth: .infinity)
                            }
                        }
                        Button(role: .destructive) {
                            model.delete(image)
                        } label: {
                            Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                    }
                    .controlSize(.large)
                }
                .padding(16)
            }
        } else {
            Text("No image selected")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

// MARK: - MCP connection panel

struct MCPPanel: View {
    @Environment(AppModel.self) private var model
    @State private var copied: String?

    private var jsonConfig: String {
        """
        {
          "mcpServers": {
            "imagegen": { "type": "http", "url": "\(model.mcpURL)" }
          }
        }
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Color.accentColor)
                Text("Connect an MCP client").font(.headline)
                Spacer()
                Label("Running", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
            Text("The MCP server runs while ImageGen is open, even with the window closed. Clients get the tools generate_image, edit_image, list_models, load_model, get_status and list_recent_images.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            snippet("Claude Code", model.claudeCommand, id: "claude")
            snippet("Server URL (Streamable HTTP)", model.mcpURL, id: "url")
            snippet("JSON config (Cursor, VS Code, others)", jsonConfig, id: "json")

            Text("Add `--scope user` to the Claude Code command to make it available in every project.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 460)
    }

    private func snippet(_ title: String, _ text: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(alignment: .top) {
                Text(text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Clipboard.copy(text)
                    copied = id
                } label: {
                    Image(systemName: copied == id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("port") private var port = 7860
    @State private var portText = ""
    @State private var token = ""
    @State private var showLog = false

    var body: some View {
        Form {
            Section("Engine") {
                LabeledContent("Status", value: model.engine.message)
                TextField("Port", text: $portText)
                    .onSubmit(applyPort)
                Text("The API and the MCP server listen on 127.0.0.1 at this port. Changing it restarts the engine and MCP clients need the new URL.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Restart Engine") { model.restart() }
                    Button("Show Log") { showLog = true }
                }
            }
            Section("Hugging Face") {
                SecureField("Access token (optional)", text: $token)
                    .onSubmit { Keychain.hfToken = token }
                Text("Only needed for gated or private models. Stored in your Keychain. Applied on the next engine restart.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save Token") {
                    Keychain.hfToken = token
                    model.restart()
                }
            }
            Section("Storage") {
                LabeledContent("Images") {
                    Button(model.outputDir) { NSWorkspace.shared.open(URL(fileURLWithPath: model.outputDir)) }
                        .buttonStyle(.link)
                }
                LabeledContent("Models & environment") {
                    Button(EngineProcess.supportDir.path) { NSWorkspace.shared.open(EngineProcess.supportDir) }
                        .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            portText = String(port)
            token = Keychain.hfToken ?? ""
        }
        .sheet(isPresented: $showLog) { LogView().environment(model) }
    }

    private func applyPort() {
        guard let value = Int(portText), (1024...65535).contains(value), value != port else { return }
        port = value
        model.restart()
    }
}
