import SwiftUI

/// Per-clip note (lyrics cue, reminder, key…) stored in the profile.
struct ClipNoteEditor: View {
    let clip: LiveClip
    let trackName: String
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(clip.color)).frame(width: 18, height: 18)
                    Text(clip.name).font(.system(size: 16, weight: .bold, design: .rounded))
                    Spacer()
                    Text(trackName).font(.system(size: 12)).foregroundColor(.secondary)
                }
                Text("Length: \(Int(clip.length)) beats · Scene \(clip.sceneIndex + 1)")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                TextEditor(text: $text)
                    .font(.system(size: 16, design: .rounded))
                    .frame(minHeight: 160)
                    .padding(6)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                Text("Shown inside the clip in the launcher. Use it for lyrics cues, key, what to tweak, or 'next: drop'.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Clip note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.profile.setClipNote(track: trackName, clip: clip.name, note: text)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { text = store.profile.clipNote(track: trackName, clip: clip.name) ?? "" }
    }
}
