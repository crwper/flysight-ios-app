//
//  FileExplorerView.swift
//  FlySight
//
//  Created by Michael Cooper on 2025-05-19.
//

import SwiftUI
import FlySightCore

struct FileExplorerView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager

    @State private var isDownloading = false
    @State private var isUploading = false
    @State private var showFileImporter = false
    @State private var selectedFileURLForUpload: URL? // Renamed for clarity

    // For sharing downloaded files
    @State private var showShareSheet = false
    @State private var fileToShare: URL?

    var body: some View {
        NavigationView {
            VStack {
                if case .connected = bluetoothManager.connectionState {
                    List {
                        // "Go Up" row
                        if !bluetoothManager.currentPath.isEmpty {
                            Button(action: {
                                bluetoothManager.goUpOneDirectoryLevel()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.turn.up.left")
                                    Text("..")
                                        .font(.headline)
                                }
                            }
                        }

                        // Directory entries
                        ForEach(bluetoothManager.directoryEntries.filter { !$0.isHidden && !$0.isEmptyMarker }) { entry in
                            Button(action: {
                                if entry.isFolder {
                                    bluetoothManager.changeDirectory(to: entry.name)
                                } else {
                                    downloadFile(entry)
                                }
                            }) {
                                HStack {
                                    Image(systemName: entry.isFolder ? "folder.fill" : "doc")
                                        .foregroundColor(entry.isFolder ? .blue : .gray)
                                    VStack(alignment: .leading) {
                                        Text(entry.name)
                                            .font(.headline)
                                        if !entry.isFolder {
                                            Text("Size: \(entry.size.fileSize())")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    Spacer()
                                    Text(entry.formattedDate)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .opacity(bluetoothManager.isAwaitingDirectoryResponse ? 0.5 : 1.0) // Dim if loading
                            }
                            .disabled(bluetoothManager.isAwaitingDirectoryResponse)
                        }
                        if bluetoothManager.isAwaitingDirectoryResponse && bluetoothManager.directoryEntries.isEmpty && bluetoothManager.currentPath.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView("Loading root...")
                                Spacer()
                            }
                        } else if bluetoothManager.isAwaitingDirectoryResponse && !bluetoothManager.directoryEntries.filter({!$0.isEmptyMarker}).isEmpty {
                             HStack {
                                Spacer()
                                ProgressView("Loading...") // When entries are already partially loaded
                                Spacer()
                            }
                        }
                    }
                    .navigationTitle("FlySight Files")
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarLeading) {
                            Button(action: {
                                bluetoothManager.loadDirectoryEntries() // Refresh current directory
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(bluetoothManager.isAwaitingDirectoryResponse)
                        }
                        ToolbarItemGroup(placement: .principal) {
                            Text(currentPathDisplay())
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            Button(action: {
                                showFileImporter = true
                            }) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .disabled(bluetoothManager.isAwaitingDirectoryResponse || isUploading)
                        }
                    }
                    .fileImporter(
                        isPresented: $showFileImporter,
                        allowedContentTypes: [.data], // Allows any file type
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            if let url = urls.first {
                                selectedFileURLForUpload = url
                                uploadSelectedFile()
                            }
                        case .failure(let error):
                            print("Failed to select file for upload: \(error.localizedDescription)")
                            // Optionally show an alert to the user
                        }
                    }
                    .overlay(
                        VStack {
                            if isDownloading {
                                DownloadUploadProgressView(
                                    isShowing: $isDownloading,
                                    progress: $bluetoothManager.downloadProgress,
                                    title: "Downloading...",
                                    cancelAction: cancelDownload
                                )
                            }
                            if isUploading {
                                DownloadUploadProgressView(
                                    isShowing: $isUploading,
                                    progress: $bluetoothManager.uploadProgress,
                                    title: "Uploading...",
                                    cancelAction: cancelUpload
                                )
                            }
                        }
                        .animation(.default, value: isDownloading)
                        .animation(.default, value: isUploading)
                    )
                    .sheet(isPresented: $showShareSheet, content: {
                        if let fileURL = fileToShare {
                            ActivityViewController(activityItems: [fileURL])
                        }
                    })

                } else { // Not connected
                    VStack {
                        Spacer()
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                            .padding(.bottom)
                        Text("Not Connected")
                            .font(.headline)
                        Text("Connect to a FlySight to browse files.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Spacer()
                    }
                    .navigationTitle("FlySight Files")
                }
            }
            .onAppear {
                // Load root directory if connected and path is empty
                if case .connected = bluetoothManager.connectionState, bluetoothManager.currentPath.isEmpty {
                    if bluetoothManager.directoryEntries.isEmpty { // Only load if not already populated
                        bluetoothManager.loadDirectoryEntries()
                    }
                }
            }
        }
    }

    private func currentPathDisplay() -> String {
        if bluetoothManager.currentPath.isEmpty {
            return "/"
        }
        return "/" + bluetoothManager.currentPath.joined(separator: "/")
    }

    private func downloadFile(_ entry: FlySightCore.DirectoryEntry) {
        isDownloading = true
        // Path is already implicitly managed by bluetoothManager.currentPath
        // The `named` parameter for downloadFile should be just the file name.
        bluetoothManager.downloadFile(named: entry.name, knownSize: entry.size) { result in
            DispatchQueue.main.async {
                isDownloading = false
                switch result {
                case .success(let data):
                    saveFileToTemporaryLocation(data: data, name: entry.name)
                case .failure(let error):
                    print("Failed to download file: \(error.localizedDescription)")
                    // TODO: Show alert to user
                }
            }
        }
    }

    private func uploadSelectedFile() {
        guard let localFileURL = selectedFileURLForUpload else { return }

        isUploading = true
        let destinationFileName = localFileURL.lastPathComponent
        // remotePath should be the full path including the directory
        let remoteDir = "/" + bluetoothManager.currentPath.joined(separator: "/")
        let remoteFullPath = (remoteDir == "/" ? "" : remoteDir) + "/" + destinationFileName


        // Access the security-scoped resource if it's from outside the app's sandbox
        let shouldStopAccessing = localFileURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                localFileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileData = try Data(contentsOf: localFileURL)
            Task { // Use Task for async call
                do {
                    try await bluetoothManager.uploadFile(fileData: fileData, remotePath: remoteFullPath)
                    // Success
                    DispatchQueue.main.async {
                        isUploading = false
                        print("File uploaded successfully to \(remoteFullPath)")
                        bluetoothManager.loadDirectoryEntries() // Refresh directory
                    }
                } catch {
                    // Failure
                    DispatchQueue.main.async {
                        isUploading = false
                        print("Failed to upload file: \(error.localizedDescription)")
                        // TODO: Show alert to user
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                isUploading = false
                print("Failed to read file data for upload: \(error.localizedDescription)")
                // TODO: Show alert to user
            }
        }
    }

    private func saveFileToTemporaryLocation(data: Data, name: String) {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(name)

        do {
            try data.write(to: fileURL, options: .atomic)
            print("File saved temporarily to \(fileURL.path)")
            self.fileToShare = fileURL
            self.showShareSheet = true // Present share sheet
        } catch {
            print("Failed to save file temporarily: \(error.localizedDescription)")
            // TODO: Show error to user
        }
    }

    private func cancelDownload() {
        bluetoothManager.cancelDownload() // Or a more generic cancelFileTransfer
        DispatchQueue.main.async {
            isDownloading = false
        }
    }

    private func cancelUpload() {
        bluetoothManager.cancelUpload() // This is an async task, manager handles its state.
        DispatchQueue.main.async {
            isUploading = false // Primarily for UI state here
        }
    }
}

// Reusable Progress View
struct DownloadUploadProgressView: View {
    @Binding var isShowing: Bool
    @Binding var progress: Float
    var title: String
    var cancelAction: () -> Void

    var body: some View {
        if isShowing {
            VStack(spacing: 15) {
                Text(title)
                    .font(.headline)

                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal)

                Text(String(format: "%.0f %%", progress * 100))
                    .font(.caption)

                Button("Cancel") {
                    cancelAction()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(20)
            .frame(minWidth: 280)
            .background( // iOS 14 compatible background
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(UIColor.systemGray4).opacity(0.85)) // Using a system color that adapts
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            .transition(.scale.combined(with: .opacity)) // Nice transition
        }
    }
}


// UIActivityViewControllerRepresentable (for sharing)
struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


struct FileExplorerView_Previews: PreviewProvider {
    static var previews: some View {
        let mockBm = FlySightCore.BluetoothManager()
        // mockBm.connectionState = .connected(to: ...) // For connected state
        // mockBm.directoryEntries = [ ... mock entries ... ]
        FileExplorerView(bluetoothManager: mockBm)
    }
}
