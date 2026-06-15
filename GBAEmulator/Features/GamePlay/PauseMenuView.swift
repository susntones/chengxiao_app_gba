import SwiftUI

/// Pause menu overlay during gameplay
struct PauseMenuView: View {
    @ObservedObject var viewModel: GamePlayViewModel
    let onResume: () -> Void
    let onQuit: () -> Void

    @State private var showingSaveStates = false
    @State private var saveStateMode: SaveStateMode = .save

    enum SaveStateMode {
        case save, load
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onResume() }

            // Menu card
            VStack(spacing: 0) {
                // Header
                Text("Paused")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                Divider()
                    .background(Color.white.opacity(0.2))

                // Menu items
                VStack(spacing: 0) {
                    PauseMenuItem(icon: "play.fill", title: "Resume", color: .green) {
                        onResume()
                    }

                    PauseMenuItem(icon: "square.and.arrow.down", title: "Save State", color: .blue) {
                        saveStateMode = .save
                        showingSaveStates = true
                    }

                    PauseMenuItem(icon: "square.and.arrow.up", title: "Load State", color: .orange) {
                        saveStateMode = .load
                        showingSaveStates = true
                    }

                    PauseMenuItem(icon: "bolt.fill", title: "Quick Save", color: .cyan) {
                        viewModel.saveState(slot: 0)
                        onResume()
                    }

                    PauseMenuItem(icon: "bolt", title: "Quick Load", color: .cyan) {
                        viewModel.loadState(slot: 0)
                    }

                    PauseMenuItem(
                        icon: viewModel.isFastForwarding ? "forward.fill" : "forward",
                        title: viewModel.isFastForwarding ? "Normal Speed" : "Fast Forward",
                        color: .yellow
                    ) {
                        viewModel.toggleFastForward()
                        onResume()
                    }

                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.vertical, 4)

                    PauseMenuItem(icon: "xmark.circle", title: "Quit to Library", color: .red) {
                        onQuit()
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(radius: 20)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .sheet(isPresented: $showingSaveStates) {
            SaveStateGridView(
                viewModel: viewModel,
                mode: saveStateMode,
                onDismiss: { showingSaveStates = false }
            )
        }
    }
}

// MARK: - Menu Item

struct PauseMenuItem: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 24)

                Text(title)
                    .font(.body)
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Save State Grid

struct SaveStateGridView: View {
    @ObservedObject var viewModel: GamePlayViewModel
    let mode: PauseMenuView.SaveStateMode
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.getSaveStates()) { state in
                        SaveStateCell(state: state) {
                            if mode == .save {
                                if !state.isLocked {
                                    viewModel.saveState(slot: state.slot)
                                    onDismiss()
                                }
                            } else {
                                if state.exists {
                                    viewModel.loadState(slot: state.slot)
                                    onDismiss()
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(mode == .save ? "Save State" : "Load State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}

// MARK: - Save State Cell

struct SaveStateCell: View {
    let state: SaveStateInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Thumbnail or empty placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(3/2, contentMode: .fit)

                    if state.exists, let url = state.thumbnailURL,
                       let uiImage = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack {
                            Image(systemName: state.exists ? "photo" : "plus")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text(state.exists ? "Slot \(state.slot)" : "Empty")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Lock indicator
                    if state.isLocked {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                }

                // Info
                VStack(spacing: 2) {
                    Text("Slot \(state.slot)")
                        .font(.caption)
                        .fontWeight(.medium)

                    if let date = state.date {
                        Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fast Forward Indicator

struct FastForwardIndicator: View {
    let speed: Double

    var body: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                    Text("\(Int(speed))x")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(.top, 50)
                .padding(.trailing, 60)
            }
            Spacer()
        }
    }
}
