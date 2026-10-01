import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showLog = false

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .starting(let message):
                StartupView(message: message, failed: false, showLog: $showLog)
            case .failed(let message):
                StartupView(message: message, failed: true, showLog: $showLog)
            case .running:
                if model.showModelPicker {
                    ModelPickerView()
                } else {
                    StudioView()
                }
            }
        }
        .sheet(isPresented: $showLog) { LogView() }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct StartupView: View {
    @Environment(AppModel.self) private var model
    let message: String
    let failed: Bool
    @Binding var showLog: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: failed ? "exclamationmark.triangle" : "photo.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(failed ? .orange : .accentColor)
            Text(failed ? "The engine could not start" : "Getting ready")
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if failed {
                HStack {
                    Button("Show Log") { showLog = true }
                    Button("Try Again") { model.restart() }.keyboardShortcut(.defaultAction)
                }
            } else {
                ProgressView().controlSize(.small)
                if let last = model.logLines.last {
                    Text(last)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                }
                Button("Show Log") { showLog = true }.buttonStyle(.link)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Engine Log").font(.headline)
                Spacer()
                Button("Open Log File") { NSWorkspace.shared.open(EngineProcess.logURL) }
                Button("Copy") { Clipboard.copy(model.logLines.joined(separator: "\n")) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line).font(.caption.monospaced()).textSelection(.enabled).id(index)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { proxy.scrollTo(model.logLines.count - 1, anchor: .bottom) }
            }
        }
        .frame(width: 760, height: 480)
    }
}
