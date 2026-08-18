import AVFoundation
import PhotosUI
import SwiftUI

struct AvatarSettingsView: View {
    @ObservedObject private var preferences = NativeAvatarPreferences.shared
    @State private var selectedOutfit = NativeAvatarOutfit.casual.rawValue
    @State private var importState: String?
    @State private var fileImportState: String?
    @State private var isFilePickerPresented = false
    @State private var photoImportState: String?
    @State private var isPhotoPickerPresented = false
    @State private var selectedPhotoVideo: PhotosPickerItem?
    @State private var importError: String?
    @State private var customOutfitName = ""
    @State private var showCustomOutfitPrompt = false
    @State private var outfitPendingDeletion: String?
    @State private var preview: AvatarVideoPreview?
    private let states = NativeAvatarEmotion.allCases.map(\.rawValue) + NativeAvatarTouchRegion.allCases.map(\.mediaState)

    var body: some View {
        List {
            Section {
                Toggle(String(localized: "Avatar Settings Auto Open"), isOn: $preferences.autoOpen)
                Picker(String(localized: "Avatar Settings Default Outfit"), selection: $preferences.defaultOutfit) {
                    ForEach(preferences.outfits.filter(preferences.isEnabled), id: \.self) {
                        Text(preferences.displayName(for: $0)).tag($0)
                    }
                }
            } header: {
                Text("Avatar Settings Conversation")
            } footer: {
                Text("Avatar Settings Conversation Footer")
            }

            Section {
                ForEach(preferences.outfits, id: \.self) { outfit in
                    Toggle(preferences.displayName(for: outfit), isOn: outfitBinding(outfit))
                        .disabled(outfit == NativeAvatarOutfit.casual.rawValue)
                }
                Button(String(localized: "Avatar Settings Add Custom Outfit")) { showCustomOutfitPrompt = true }
            } header: {
                Text("Avatar Settings Outfits")
            } footer: {
                Text("Avatar Settings Outfits Footer")
            }

            Section {
                Picker(String(localized: "Avatar Settings Outfit"), selection: $selectedOutfit) {
                    ForEach(preferences.outfits, id: \.self) { Text(preferences.displayName(for: $0)).tag($0) }
                }
                ForEach(states, id: \.self) { state in
                    HStack {
                        Button {
                            importState = state
                        } label: {
                            VStack(alignment: .leading) {
                                Text(preferences.stateDisplayName(for: state))
                                Text(videoDescription(for: state))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            if let url = previewURL(for: state) {
                                preview = AvatarVideoPreview(
                                    title: preferences.stateDisplayName(for: state),
                                    url: url
                                )
                            }
                        } label: {
                            Image(systemName: "play.rectangle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(previewURL(for: state) == nil)
                        .accessibilityLabel("Preview")
                        if preferences.hasVideoOverride(outfit: selectedOutfit, state: state) {
                            Button(String(localized: "Avatar Settings Restore Default")) {
                                preferences.removeVideoOverride(outfit: selectedOutfit, state: state)
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
                Button(String(localized: "Avatar Settings Restore Outfit Defaults")) {
                    preferences.removeOutfitOverrides(outfit: selectedOutfit)
                }
                .disabled(!states.contains { preferences.hasVideoOverride(outfit: selectedOutfit, state: $0) })
                if !preferences.isBuiltIn(selectedOutfit) {
                    Button(String(localized: "Avatar Settings Delete Outfit"), role: .destructive) {
                        outfitPendingDeletion = selectedOutfit
                    }
                }
            } header: {
                Text("Avatar Settings Video Mapping")
            } footer: {
                Text("Avatar Settings Video Mapping Footer")
            }
        }
        .navigationTitle("Avatar Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { preview in
            AvatarVideoPreviewSheet(preview: preview)
        }
        .alert("Avatar Settings Add Custom Outfit", isPresented: $showCustomOutfitPrompt) {
            TextField("Avatar Settings Outfit Name", text: $customOutfitName)
            Button("Avatar Settings Add") {
                if let outfit = preferences.addCustomOutfit(named: customOutfitName) { selectedOutfit = outfit }
                customOutfitName = ""
            }
            Button("Cancel", role: .cancel) { customOutfitName = "" }
        } message: {
            Text("Avatar Settings Add Outfit Message")
        }
        .alert("Avatar Settings Video Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
        .confirmationDialog("Avatar Settings Import Video", isPresented: Binding(get: { importState != nil }, set: { if !$0 { importState = nil } })) {
            Button("Avatar Settings Choose from Photos") {
                photoImportState = importState
                importState = nil
                DispatchQueue.main.async { isPhotoPickerPresented = true }
            }
            Button("Avatar Settings Choose from Files") {
                fileImportState = importState
                importState = nil
                DispatchQueue.main.async { isFilePickerPresented = true }
            }
            Button("Cancel", role: .cancel) { importState = nil }
        } message: {
            Text("Avatar Settings Choose Video Message")
        }
        .confirmationDialog("Avatar Settings Delete Outfit", isPresented: Binding(get: { outfitPendingDeletion != nil }, set: { if !$0 { outfitPendingDeletion = nil } })) {
            Button("Avatar Settings Delete Outfit", role: .destructive) {
                guard let outfitPendingDeletion else { return }
                preferences.deleteCustomOutfit(outfitPendingDeletion)
                selectedOutfit = NativeAvatarOutfit.casual.rawValue
                self.outfitPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { outfitPendingDeletion = nil }
        } message: {
            Text("Avatar Settings Delete Outfit Message")
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhotoVideo, matching: .videos)
        .onChange(of: selectedPhotoVideo) { item in
            guard let item, let state = photoImportState else { return }
            let outfit = selectedOutfit
            photoImportState = nil
            selectedPhotoVideo = nil
            Task { @MainActor in
                do {
                    guard let video = try await item.loadTransferable(type: VideoFileTransferable.self) else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    try await preferences.importVideo(from: video.url, outfit: outfit, state: state, originalFilename: video.originalFilename)
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
        .fileImporter(isPresented: $isFilePickerPresented, allowedContentTypes: [.item]) { result in
            guard let state = fileImportState else { return }
            fileImportState = nil
            switch result {
            case .success(let url):
                let outfit = selectedOutfit
                Task { @MainActor in
                    do { try await preferences.importVideo(from: url, outfit: outfit, state: state) }
                    catch { importError = error.localizedDescription }
                }
            case .failure(let error): importError = error.localizedDescription
            }
        }
    }

    private func outfitBinding(_ outfit: String) -> Binding<Bool> {
        Binding(get: { preferences.isEnabled(outfit) }, set: { preferences.setEnabled($0, outfit: outfit) })
    }

    private func videoDescription(for state: String) -> String {
        if let filename = preferences.mappingOriginalFilename(outfit: selectedOutfit, state: state) {
            let customSuffix = String(localized: "Avatar Settings Custom")
            return "\(filename) · \(customSuffix)"
        }
        return preferences.isBuiltIn(selectedOutfit)
            ? String(localized: "Avatar Settings Default")
            : String(localized: "Avatar Settings Not Configured")
    }

    private func previewURL(for state: String) -> URL? {
        if let region = NativeAvatarTouchRegion.allCases.first(where: { $0.mediaState == state }) {
            return NativeAvatarAssetResolver.reactionURL(outfit: selectedOutfit, region: region)
        }
        if let emotion = NativeAvatarEmotion(rawValue: state) {
            return NativeAvatarAssetResolver.url(outfit: selectedOutfit, state: "idle_01", emotion: emotion)
        }
        return NativeAvatarAssetResolver.url(outfit: selectedOutfit, state: state)
    }
}

struct AvatarVideoPreview: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

struct AvatarVideoPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: AvatarVideoPreview

    var body: some View {
        NavigationStack {
            NativeAvatarPlayer(url: preview.url, looping: true, onFinished: {})
                .background(.black)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(preview.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}
