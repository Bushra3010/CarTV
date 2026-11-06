import SwiftUI
import UniformTypeIdentifiers

struct AddSourceView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SourceKind = .m3u
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var importing = false
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(SourceKind.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if kind == .m3u || kind == .xtream {
                    Section {
                        Button("Scan a QR code", systemImage: "qrcode.viewfinder") { scanning = true }
                    }
                }

                switch kind {
                case .m3u:
                    Section {
                        TextField("Name (optional)", text: $name)
                        TextField("https://example.com/playlist.m3u", text: $url, axis: .vertical)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: { Text("Playlist") } footer: {
                        Text("M3U and M3U8 playlists are supported. Channels are grouped by group-title, and tvg-logo is used for the artwork. A single HLS stream URL works too.")
                    }
                    Section {
                        Button("Paste from clipboard", systemImage: "doc.on.clipboard") {
                            if let s = UIPasteboard.general.string { url = s }
                        }
                        Button("Add sample test streams", systemImage: "sparkles.tv") {
                            Task { await store.addSample(); dismiss() }
                        }
                    }
                case .xtream, .jellyfin:
                    Section {
                        TextField("Name (optional)", text: $name)
                        TextField(kind == .xtream ? "http://server:port" : "http://192.168.1.10:8096", text: $url)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                        SecureField("Password", text: $password).textContentType(.password)
                    } header: { Text(kind.title) } footer: {
                        Text(kind == .xtream
                             ? "Live channels and movies are loaded from your provider's Xtream Codes API."
                             : "Browse your own libraries, seasons and episodes. Your password is sent only to your server, and the access token is kept in the iOS Keychain.")
                    }
                case .local:
                    Section {
                        Button("Choose videos…", systemImage: "folder") { importing = true }
                    } footer: {
                        Text("Videos are copied into Backseat so they play offline. You can find them in the Files app under On My iPhone › Backseat.")
                    }
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if kind != .local {
                    ToolbarItem(placement: .confirmationAction) {
                        if busy { ProgressView() } else { Button("Add") { submit() }.disabled(!isValid) }
                    }
                }
            }
            .onChange(of: kind) { error = nil }
            .sheet(isPresented: $scanning) { QRScannerSheet { apply(scanned: $0) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .video, .audiovisualContent], allowsMultipleSelection: true) { result in
                do {
                    try store.importLocalFiles(try result.get())
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    private func apply(scanned code: String) {
        switch ScannedSource(code) {
        case .m3u(let link):
            kind = .m3u
            url = link
            error = nil
        case .xtream(let server, let user, let pass):
            kind = .xtream
            url = server
            username = user
            password = pass
            error = nil
        case nil:
            error = "That QR code doesn't contain a playlist link."
        }
    }

    private var isValid: Bool {
        switch kind {
        case .m3u: !url.trimmingCharacters(in: .whitespaces).isEmpty
        case .xtream, .jellyfin: !url.isEmpty && !username.isEmpty
        case .local: true
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                switch kind {
                case .m3u: try await store.addM3U(name: name, url: url)
                case .xtream: try await store.addXtream(name: name, server: url, username: username, password: password)
                case .jellyfin: try await store.addJellyfin(name: name, server: url, username: username, password: password)
                case .local: break
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
