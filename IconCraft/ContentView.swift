//
//  ContentView.swift
//  IconCraft
//
//  Created by Qiang on 2026/08/15.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppIconViewModel()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                infoBar
                Divider()
                HSplitView {
                    iconBrowser
                        .frame(minWidth: 380, idealWidth: 540)
                    comparisonPanel
                        .frame(minWidth: 340, idealWidth: 440)
                }
                Divider()
                actionBar
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Icon Craft")
            .toolbar { toolbarContent }
        }
        .alert(
            "Icons Replaced",
            isPresented: $viewModel.showSuccessAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The App Icon catalog was updated with every required iOS size.")
        }
        .alert(
            "Something Went Wrong",
            isPresented: errorAlertPresented
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

// MARK: - Toolbar & info

private extension ContentView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: viewModel.selectSourceImage) {
                Label("Source Image", systemImage: "photo.on.rectangle")
            }
            .help("Choose the source icon image")

            Button(action: viewModel.selectProjectFolder) {
                Label("iOS Project", systemImage: "folder")
            }
            .help("Choose an iOS project folder or .appiconset")
        }

        ToolbarItem(placement: .automatic) {
            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .help("Working…")
            }
        }
    }

    var infoBar: some View {
        HStack(spacing: 16) {
            infoChip(
                title: "Source",
                value: viewModel.selectedImageURL?.lastPathComponent ?? "No image selected",
                systemImage: "photo"
            )
            infoChip(
                title: "Size",
                value: dimensionText,
                systemImage: "aspectratio"
            )
            infoChip(
                title: "File",
                value: viewModel.fileSizeString ?? "—",
                systemImage: "doc"
            )

            Spacer(minLength: 12)

            if viewModel.availableIconSets.count > 1 {
                Picker("Catalog", selection: iconSetBinding) {
                    ForEach(viewModel.availableIconSets, id: \.self) { url in
                        Text(catalogLabel(url)).tag(Optional(url))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            } else {
                infoChip(
                    title: "Catalog",
                    value: viewModel.selectedIconSetURL.map(catalogLabel) ?? "No project selected",
                    systemImage: "square.stack.3d.up"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    func infoChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
    }

    var dimensionText: String {
        guard let size = viewModel.pixelDimensions else { return "—" }
        return "\(Int(size.width.rounded()))×\(Int(size.height.rounded())) px"
    }

    var iconSetBinding: Binding<URL?> {
        Binding(
            get: { viewModel.selectedIconSetURL },
            set: { viewModel.selectIconSet($0) }
        )
    }

    func catalogLabel(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        return "\(parent)/\(name)"
    }
}

// MARK: - Icon browser

private extension ContentView {
    var filteredSpecs: [IconSpecification] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let specs = AppIconConfig.allSpecs
        guard !query.isEmpty else { return specs }
        return specs.filter { spec in
            let haystack = [
                spec.idiomLabel,
                spec.idiom,
                spec.size,
                spec.scale,
                spec.filename,
                spec.pixelLabel,
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    var iconBrowser: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Generated Icons")
                    .font(.headline)
                Text("\(filteredSpecs.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter by idiom, size, scale…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 240)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                if filteredSpecs.isEmpty {
                    emptyBrowserMessage("No icon sizes match “\(searchText)”.")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 124), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(filteredSpecs) { spec in
                            IconTile(
                                spec: spec,
                                image: previewImage(for: spec)
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
    }

    func previewImage(for spec: IconSpecification) -> NSImage? {
        viewModel.generatedPreviews.first(where: { $0.spec.id == spec.id })?.image
    }

    func emptyBrowserMessage(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding()
    }
}

// MARK: - Comparison

private extension ContentView {
    var comparisonPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Comparison")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        ComparisonCard(
                            title: "Candidate",
                            subtitle: "Source image",
                            systemImage: "sparkles",
                            image: viewModel.sourceImage,
                            interpolation: .medium
                        )
                        ComparisonCard(
                            title: "Current",
                            subtitle: "Project catalog",
                            systemImage: "app",
                            image: viewModel.currentAppIcon,
                            interpolation: .medium
                        )
                    }

                    ComparisonCard(
                        title: "Pixel Diff",
                        subtitle: "Black = changed · White = identical",
                        systemImage: "circle.lefthalf.filled",
                        image: viewModel.diffImage,
                        interpolation: .none,
                        minHeight: 220
                    )
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Action bar

private extension ContentView {
    var actionBar: some View {
        HStack(spacing: 12) {
            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("Processing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let project = viewModel.projectURL {
                Text(project.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: viewModel.calculatePixelDiff) {
                Label("Compare Pixels", systemImage: "circle.lefthalf.filled")
            }
            .disabled(!viewModel.canCalculateDiff || viewModel.isProcessing)
            .help("Generate a black-and-white pixel difference")

            Button(action: viewModel.replaceAppIcons) {
                Label("Replace AppIcon", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canReplaceIcons)
            .help("Write every iOS icon size into the selected catalog")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .controlSize(.large)
    }
}

// MARK: - Tiles & cards

private struct IconTile: View {
    let spec: IconSpecification
    let image: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                CheckerboardBackground()
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .padding(10)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
            }

            VStack(spacing: 3) {
                Text(spec.idiomLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(spec.idiomColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(spec.idiomColor)

                Text(spec.pointAndScaleLabel)
                    .font(.caption.monospacedDigit())
                Text(spec.pixelLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
        }
        .help(spec.filename)
    }
}

private struct ComparisonCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let image: NSImage?
    var interpolation: Image.Interpolation = .medium
    var minHeight: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                CheckerboardBackground()
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(interpolation)
                        .scaledToFit()
                        .padding(12)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .font(.title2)
                        Text("No image")
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(Path(rect), with: .color(.primary.opacity(0.06)))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Spec labels

private extension IconSpecification {
    var idiomLabel: String {
        switch idiom {
        case "iphone": return "iPhone"
        case "ipad": return "iPad"
        case "ios-marketing": return "App Store"
        default: return idiom
        }
    }

    var idiomColor: Color {
        switch idiom {
        case "iphone": return .blue
        case "ipad": return .purple
        case "ios-marketing": return .orange
        default: return .secondary
        }
    }

    var pointAndScaleLabel: String {
        "\(size) @\(scale)"
    }

    var pixelLabel: String {
        let pixels = Int(pixelSize.rounded())
        return "\(pixels)×\(pixels) px"
    }
}

#Preview {
    ContentView()
        .frame(width: 1100, height: 740)
}
