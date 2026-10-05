import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider().background(Theme.line)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().background(Theme.line)
            TransportBar()
        }
        .background(Theme.background, ignoresSafeAreaEdges: .all)
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(store.live)
                .environmentObject(store.sequencer)
                .environmentObject(store.midi)
        }
        .onAppear { Haptics.enabled = store.profile.hapticsEnabled }
        .onChange(of: store.profile.hapticsEnabled) { Haptics.enabled = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch store.activeTab {
        case .launcher:
            if live.song.tracks.isEmpty {
                WelcomeView()
            } else {
                LauncherView()
            }
        case .mixer:
            if live.song.tracks.isEmpty {
                WelcomeView()
            } else {
                MixerView()
            }
        case .control:
            ControlView()
        case .sequencer:
            SequencerView()
        }
    }
}

/// Header: connection status, deck tabs, view switcher, settings.
struct TopBar: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                StatusDot(color: statusColor, pulsing: live.state == .searching || live.state == .connecting)
                Text(live.state.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                if live.state == .connected, !live.liveHost.isEmpty {
                    Text(live.liveHost)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.textSecondary.opacity(0.7))
                }
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer()

            Segmented(options: AppStore.AppTab.allCases.map { ($0, $0.rawValue) }, selection: $store.activeTab)
                .frame(width: 340)

            Spacer()

            if !live.lastError.isEmpty {
                Text(live.lastError)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.red)
                    .lineLimit(1)
                    .frame(maxWidth: 220)
            }

            Button(action: { store.showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.panel)
    }

    private var statusColor: Color {
        switch live.state {
        case .connected: return Theme.green
        case .demo: return Theme.secondary
        case .searching, .connecting: return Theme.yellow
        case .disconnected: return Theme.red
        }
    }
}

/// Shown when no set is loaded yet.
struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var live: LiveSession

    var body: some View {
        VStack(spacing: 18) {
            Text("StageDeck")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.textPrimary)
            Text("Clip launcher · stem mixer · step sequencer for Ableton Live")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Install the AbletonOSC remote script on the Mac (see ableton/README.md).")
                Text("2. Put the iPad and the Mac on the same network (Wi‑Fi or Ethernet).")
                Text("3. Press Connect. StageDeck finds Live by itself; or type the Mac's IP in Settings.")
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundColor(Theme.textSecondary)
            .padding()
            .background(Theme.panel)
            .cornerRadius(10)
            HStack(spacing: 12) {
                PadButton(title: live.state == .searching ? "Searching…" : "Connect", color: Theme.accent, active: true, height: 48) {
                    store.connect()
                }
                .frame(width: 180)
                PadButton(title: "Demo mode", color: Theme.secondary, active: false, height: 48) {
                    live.enterDemo()
                }
                .frame(width: 180)
                PadButton(title: "Settings", color: Theme.panelRaised, active: false, height: 48) {
                    store.showSettings = true
                }
                .frame(width: 140)
            }
            if !live.listenerError.isEmpty {
                Text(live.listenerError).font(.system(size: 11)).foregroundColor(Theme.red)
            }
            Text("Your IP: " + OSCClient.localIPAddresses().joined(separator: "  ·  "))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(40)
    }
}
