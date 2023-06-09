// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import SwiftUI
import Combine
import Pulse
import Network

@available(iOS 15, *)
struct RemoteLoggerSettingsView: View {
    @ObservedObject private var logger: RemoteLogger = .shared
    @ObservedObject var viewModel: RemoteLoggerSettingsViewModel

    var body: some View {
        contents
            .sheet(item: $viewModel.pendingPasscodeProtectedServer) { item in
                NavigationView {
                    RemoteLoggerEnterPasswordView(viewModel: viewModel, server: item)
                }
            }
            .alert(isPresented: $viewModel.isShowingConnectionError, error: viewModel.connectionError) {
                Button("OK", role: .cancel) {
                    viewModel.isShowingConnectionError = false
                }
            }
    }

    @ViewBuilder
    private var contents: some View {
        let servers = self.servers

        Section(content: {
            Toggle(isOn: $viewModel.isEnabled, label: {
                HStack(spacing: 12) {
#if !os(watchOS)
                    Text(Image(systemName: "wifi"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.blue)
                        .cornerRadius(6)
#endif
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Logging")
                        Text("Requires [Pulse for Mac](https://testflight.apple.com/join/1jcanE3q)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
#if os(macOS)
                    Spacer()
#endif
                }
            })
#if os(iOS)
            .padding(.vertical, 2)
#endif
            if let server = logger.selectedServerName {
                RemoteLoggerSelectedDeviceView(name: server, server: servers.first(where: { $0.isSelected }))
            }
        })

        if viewModel.isEnabled {
            Section(header: Text("Devices")) {
                if let error = logger.browserError {
                    RemoteLoggerErrorView(error: error)
                } else {
                    if !servers.isEmpty {
#if os(macOS) || os(iOS)
                        ForEach(servers, content: makeServerView)
#else
                        List(servers, rowContent: makeServerView)
#endif
                    } else {
                        progressView
                    }
                }
            }
        }
    }

    private var progressView: some View {
#if os(watchOS)
        ProgressView()
            .progressViewStyle(.circular)
            .frame(idealWidth: .infinity, alignment: .center)
#else
        HStack(spacing: 8) {
#if !os(macOS)
            ProgressView()
                .progressViewStyle(.circular)
#endif
            Text("Searching...")
                .foregroundColor(.secondary)
        }
#endif
    }

    private var servers: [RemoteLoggerServerViewModel] {
        logger.servers.map { server in
            RemoteLoggerServerViewModel(
                server: server,
                name: server.name ?? "–",
                isSelected: logger.isSelected(server)
            )
        }
        .sorted { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private func makeServerView(for server: RemoteLoggerServerViewModel) -> some View {
        Button(action: { viewModel.connect(to: server) }) {
            HStack {
                Text(server.name)
                    .fontWeight(server.isSelected ? .medium : .regular)
                    .lineLimit(1)
                if server.isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 21, height: 36, alignment: .center)
                }
                Spacer()
                if server.server.isProtected {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.separator)
                }
            }
        }
        .foregroundColor(Color.primary)
        .frame(maxWidth: .infinity)
    }
}

final class RemoteLoggerSettingsViewModel: ObservableObject {
    @Published var isEnabled = false
    @Published var pendingPasscodeProtectedServer: RemoteLoggerServerViewModel?
    @Published var isShowingConnectionError = false
    private(set) var connectionError: RemoteLogger.ConnectionError?

    private let logger: RemoteLogger
    private var cancellables: [AnyCancellable] = []

    static var shared = RemoteLoggerSettingsViewModel()
    
    init(logger: RemoteLogger = .shared) {
        self.logger = logger
        
        isEnabled = logger.isEnabled
        
        $isEnabled.removeDuplicates().receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                self?.didUpdateIsEnabled($0)
            }.store(in: &cancellables)
    }
    
    private func didUpdateIsEnabled(_ isEnabled: Bool) {
        isEnabled ? logger.enable() : logger.disable()
    }

    func connect(to viewModel: RemoteLoggerServerViewModel) {
        let server = viewModel.server
        if server.isProtected {
            if let passcode = server.name.flatMap(logger.getPasscode) {
                _connect(to: server, passcode: passcode)
            } else {
                pendingPasscodeProtectedServer = viewModel
            }
        } else {
            _connect(to: server)
        }
    }

    func connect(to viewModel: RemoteLoggerServerViewModel, passcode: String) {
        _connect(to: viewModel.server, passcode: passcode)
    }

    private func _connect(to server: NWBrowser.Result, passcode: String? = nil) {
        logger.connect(to: server, passcode: passcode) {
            switch $0 {
            case .success:
                break
            case .failure(let error):
                self.connectionError = error
                self.isShowingConnectionError = true
            }
        }
    }
}

struct RemoteLoggerServerViewModel: Identifiable {
    var id: NWBrowser.Result { server }
    let server: NWBrowser.Result
    let name: String
    let isSelected: Bool
}

extension NWBrowser.Result {
    var name: String? {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        default:
            return nil
        }
    }

    var isProtected: Bool {
        switch metadata {
        case .bonjour(let record):
            return record["protected"].map { Bool($0) } == true
        case .none:
            return false
        @unknown default:
            return false
        }
    }
}

#if DEBUG
@available(iOS 15, *)
struct RemoteLoggerSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            List {
                RemoteLoggerSettingsView(viewModel: .shared)
            }
            .navigationTitle("Settings")
        }
    }
}
#endif