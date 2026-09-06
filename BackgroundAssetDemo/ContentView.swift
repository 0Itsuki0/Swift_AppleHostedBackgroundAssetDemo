//
//  ContentView.swift
//  BackgroundAssetDemo
//
//  Created by Itsuki on 2026/09/05.
//

import BackgroundAssets
import QuickLook
import SwiftUI

struct ContentView: View {
    @Environment(AssetManager.self) private var manager

    var body: some View {
        NavigationStack {
            VStack {
                Text("Background Assets")
                    .font(.title2)
                    .fontWeight(.bold)

                if let error = manager.error {
                    Text("Error: \(error.localizedDescription)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }

                List {
                    ForEach(Array(manager.assetPacks)) { asset in
                        AssetView(asset: asset)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }
}

struct AssetView: View {
    @Environment(AssetManager.self) private var manager
    let asset: AssetPack

    @State private var status: AssetPack.Status?
    @State private var assetContents: [TreeJsonEntry] = []

    var downloaded: Bool { status?.contains(.downloaded) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AssetOverview(
                asset: asset,
                status: $status,
                assetContents: $assetContents
            )

            if downloaded {
                Divider()

                if assetContents.isEmpty {
                    Text("No contents available in the assets")
                        .foregroundStyle(.secondary)
                }
                NavigationLink(
                    "Contents",
                    destination: {
                        TreeJsonEntryView(
                            getPreviewURL: self.getPreviewURL(
                                parentPaths:
                                fileNameWithExt:
                            ),
                            pathToEntry: [],
                            entries: assetContents
                        )
                        .environment(self.manager)
                    }
                )
            }
        }
        .task {
            self.status = await manager.assetPackStatus(
                for: self.asset.id,
                localOnly: false
            )
        }
        .task(id: self.status) {
            if downloaded {
                self.assetContents = await manager.loadAssetContentStructure(
                    self.asset.id
                )
            } else {
                self.assetContents = []
            }
        }
    }

    private func getPreviewURL(
        parentPaths: [String],
        fileNameWithExt: String
    ) async -> URL? {
        var paths = parentPaths
        paths.append(fileNameWithExt)
        let path = paths.joined(separator: "/")
        guard
            let data = await manager.loadDataFromAsset(
                self.asset.id,
                filePath: path
            )
        else {
            return nil
        }
        let tempURL = URL.temporaryDirectory.appending(path: fileNameWithExt)
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Failed to write data to temporary file: \(error)")
            manager.error = error
            return nil
        }
    }
}

struct TreeJsonEntryView: View {
    let getPreviewURL:
        (_ parentPaths: [String], _ fileNameWithExt: String) async -> URL?

    let pathToEntry: [String]
    let entries: [TreeJsonEntry]

    @State private var previewURL: URL?

    var body: some View {
        List {
            ForEach(entries, id: \.self) { entry in
                switch entry {
                case .directory(let name, let contents):
                    NavigationLink(
                        name,
                        destination: {
                            TreeJsonEntryView(
                                getPreviewURL: self.getPreviewURL,
                                pathToEntry: pathToEntry + [name],
                                entries: contents
                            )
                        }
                    )
                case .file(let name):
                    HStack {
                        Text(name)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(
                            "Preview",
                            action: { self.previewFile(name) }
                        )
                    }
                case .report:
                    EmptyView()
                }
            }
        }
        .quickLookPreview($previewURL)

    }

    private func previewFile(_ name: String) {
        Task {
            guard
                let url = await self.getPreviewURL(pathToEntry, name)
            else {
                return
            }
            self.previewURL = url
        }

    }

}

struct AssetOverview: View {
    @Environment(AssetManager.self) private var manager
    let asset: AssetPack

    @Binding var status: AssetPack.Status?
    @Binding var assetContents: [TreeJsonEntry]

    @State private var downloadStatus: AssetPackManager.DownloadStatusUpdate?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Id: \(asset.id)")
                    .fontWeight(.medium)
                Text("Version: \(asset.version)")
                    .font(.caption)
                Text("Size: \(asset.downloadSize.formattedBytes)")
                    .font(.caption)
                if let status {
                    Text("Status: \(status.description)")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let canDownload =
                self.status == nil
                || self.status?.newDownloadsAvailable == true

            if case .downloading(_, let progress) = downloadStatus {
                VStack {
                    ProgressView(value: progress.fractionCompleted, total: 1)
                        .progressViewStyle(.circular)
                    if let remaining = progress.estimatedTimeRemaining {
                        let range = Range<Date>(
                            uncheckedBounds: (Date(), Date() + remaining)
                        )
                        Text(
                            "Estimated Remaining: \(range.formatted(.timeDuration))"
                        )
                    }

                    // cancel the download
                    Button(
                        action: {
                            progress.cancel()
                        },
                        label: {
                            Text("Cancel")
                        }
                    )
                    .buttonStyle(.borderless)
                }
            } else {
                Button(
                    action: {
                        Task {
                            if canDownload {
                                await manager.downloadAssetPack(
                                    id: self.asset.id,
                                    requiresLatestVersion: true
                                )
                                self.assetContents =
                                    await manager.loadAssetContentStructure(
                                        self.asset.id
                                    )
                            } else {
                                await manager.removeAssetPack(
                                    id: self.asset.id
                                )
                            }

                            self.status = await manager.assetPackStatus(
                                for: self.asset.id,
                                localOnly: false
                            )
                        }

                        if canDownload {
                            Task {
                                for await status in manager.downloadStatus(
                                    for: self.asset.id
                                ) {
                                    self.downloadStatus = status
                                }
                            }
                        }
                    },
                    label: {
                        Text(canDownload ? "Download" : "Remove")
                    }
                )
                .buttonStyle(.borderless)
            }
        }
    }
}

extension Int {
    var formattedBytes: String {
        let bytes = Measurement(
            value: Double(self),
            unit: UnitInformationStorage.bytes
        )
        return bytes.formatted(.byteCount(style: .memory))
    }
}

extension AssetPack.Status {

    var newDownloadsAvailable: Bool {
        return self.contains(.downloadAvailable) && !self.contains(.upToDate)
    }

    var description: String {
        var description: [String] = []
        if contains(.downloadAvailable) {
            description.append("Download available")
        }

        if contains(.updateAvailable) {
            description.append("Update available")
        }

        if contains(.upToDate) {
            description.append("Up to date")
        }

        if contains(.outOfDate) {
            description.append("Out of date")
        }

        if contains(.obsolete) {
            description.append("Obsolete")
        }

        if contains(.downloading) {
            description.append("Downloading")
        }

        if contains(.downloaded) {
            description.append("Downloaded")
        }

        return description.joined(separator: ", ")
    }
}
