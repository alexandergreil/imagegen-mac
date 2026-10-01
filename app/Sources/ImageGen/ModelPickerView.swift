import SwiftUI

struct ModelPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Pick a model")
                    .font(.largeTitle.weight(.semibold))
                Text("Models run fully on this Mac. Download one once, then use it from here or from any MCP client.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(model.models) { info in
                        ModelCard(info: info)
                    }
                    if model.models.isEmpty {
                        ProgressView().padding()
                    }
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }

            HStack {
                Label("\(model.physicalMemoryGb) GB memory · \(Int(model.freeDiskGb)) GB free disk", systemImage: "memorychip")
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding()
        }
    }
}

private struct ModelCard: View {
    @Environment(AppModel.self) private var model
    let info: ModelInfo
    @State private var confirmDelete = false

    private var isLoaded: Bool { model.engine.modelId == info.id && model.engine.isReady }
    private var isLastUsed: Bool { model.lastModelId == info.id }
    private var lowMemory: Bool { model.physicalMemoryGb < info.recommendedMemoryGb }
    private var lowDisk: Bool { !info.installed && model.freeDiskGb < info.sizeGb + 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.name).font(.title2.weight(.semibold))
                if isLoaded {
                    Badge(text: "Loaded", color: .green)
                } else if isLastUsed && info.installed {
                    Badge(text: "Last used", color: .accentColor)
                }
                Spacer()
                Link(destination: URL(string: info.url)!) {
                    Label(info.repo, systemImage: "arrow.up.right.square")
                }
                .font(.callout)
            }
            Text(info.description).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Label(String(format: "%.1f GB", info.sizeGb), systemImage: "externaldrive")
                Label("\(info.recommendedMemoryGb) GB+ memory", systemImage: "memorychip")
                Label(info.license, systemImage: "doc.text")
                Label(info.capabilities.joined(separator: ", "), systemImage: "sparkles")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if lowMemory {
                Warning(text: "This Mac has \(model.physicalMemoryGb) GB of memory. The model may run slowly or fail to load.")
            }
            if lowDisk {
                Warning(text: "Not enough free disk space. You need about \(Int(info.sizeGb.rounded(.up))) GB.")
            }

            Divider()
            footer
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isLastUsed ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5))
        .confirmationDialog("Delete \(info.name)?", isPresented: $confirmDelete) {
            Button("Delete \(String(format: "%.0f GB", info.sizeGb))", role: .destructive) { model.delete(info) }
        } message: {
            Text("The model files are removed from disk. Your generated images stay.")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let dl = info.download, dl.isActive {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: dl.fraction)
                HStack {
                    Text("\(dl.bytesDone.byteString) of \(dl.bytesTotal.byteString)")
                    if dl.speedBps > 0 {
                        Text("· \(Int64(dl.speedBps).byteString)/s")
                        Text("· \((Double(dl.bytesTotal - dl.bytesDone) / dl.speedBps).durationString) left")
                    }
                    Spacer()
                    Button("Cancel") { model.cancelDownload(info) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        } else if info.installed {
            HStack {
                Button(role: .destructive) { confirmDelete = true } label: { Text("Delete…") }
                    .disabled(model.engine.isLoading)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: info.localPath)]) }
                Spacer()
                if isLoaded {
                    Button("Continue") { model.showModelPicker = false }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                } else {
                    Button("Use This Model") { model.use(info) }
                        .keyboardShortcut(isLastUsed ? .defaultAction : nil)
                        .controlSize(.large)
                        .disabled(model.engine.isLoading)
                }
            }
        } else {
            HStack {
                if let dl = info.download, dl.status == "error" {
                    Warning(text: "Download failed: \(dl.error ?? "unknown error")")
                } else if let dl = info.download, dl.status == "cancelled" {
                    Text("Download paused at \(dl.bytesDone.byteString). It resumes where it stopped.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.download(info)
                } label: {
                    Label(info.download == nil ? "Download" : "Resume Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(lowDisk)
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct Warning: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
    }
}
