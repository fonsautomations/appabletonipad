import SwiftUI
import UIKit

enum Theme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.075)
    static let panel = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let panelRaised = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let line = Color.white.opacity(0.08)
    static let textPrimary = Color(red: 0.93, green: 0.93, blue: 0.9)
    static let textSecondary = Color.white.opacity(0.55)
    static let accent = Color(red: 0.95, green: 0.55, blue: 0.16)
    static let secondary = Color(red: 0.56, green: 0.71, blue: 0.87)
    static let green = Color(red: 0.49, green: 0.76, blue: 0.3)
    static let red = Color(red: 0.93, green: 0.33, blue: 0.27)
    static let yellow = Color(red: 0.95, green: 0.84, blue: 0.24)
    static let corner: CGFloat = 8
}

enum Haptics {
    static var enabled = true
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    static func tap() { if enabled { light.impactOccurred() } }
    static func launch() { if enabled { medium.impactOccurred() } }
    static func heavy() { if enabled { rigid.impactOccurred() } }
}

/// Small uppercase label used across the UI.
struct CapsLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = Theme.textSecondary

    init(_ text: String, size: CGFloat = 10, color: Color = Theme.textSecondary) {
        self.text = text; self.size = size; self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(1)
            .foregroundColor(color)
            .lineLimit(1)
    }
}

/// A big touch-friendly button.
struct PadButton: View {
    let title: String
    var subtitle: String? = nil
    var color: Color = Theme.panelRaised
    var textColor: Color = Theme.textPrimary
    var active: Bool = false
    var height: CGFloat = 44
    var fontSize: CGFloat = 13
    var action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
            .foregroundColor(active ? Color.black : textColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(active ? color : color.opacity(0.35))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(active ? color : Theme.line, lineWidth: 1))
            .cornerRadius(Theme.corner)
        }
        .buttonStyle(.plain)
    }
}

/// Vertical fader with drag gesture; value 0...1.
struct VerticalFader: View {
    @Binding var value: Double
    var color: Color = Theme.accent
    var meter: Double? = nil
    var label: String? = nil
    var onChange: ((Double) -> Void)? = nil

    @State private var dragStartValue: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.22))
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
                    .frame(height: max(4, h * CGFloat(max(0, min(1, value)))))
                if let meter {
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 3, height: max(0, h * CGFloat(max(0, min(1, meter)))))
                            .padding(.trailing, 4)
                            .padding(.bottom, 2)
                    }
                }
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 2)
                    .offset(y: -h * CGFloat(max(0, min(1, value))) + 1)
                if let label {
                    VStack {
                        Spacer()
                        Text(label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.75))
                            .padding(.bottom, 6)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStartValue == nil { dragStartValue = value }
                        // Relative drag: moving the full height changes the value by 1.
                        let delta = -Double(g.translation.height / h)
                        let v = max(0, min(1, (dragStartValue ?? value) + delta))
                        value = v
                        onChange?(v)
                    }
                    .onEnded { _ in dragStartValue = nil }
            )
            .onTapGesture(count: 2) {
                value = 0.85
                onChange?(0.85)
                Haptics.tap()
            }
        }
    }
}

/// Horizontal slider with drag gesture; value 0...1.
struct HorizontalSlider: View {
    @Binding var value: Double
    var color: Color = Theme.accent
    var label: String = ""
    var onChange: ((Double) -> Void)? = nil
    @State private var dragStartValue: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.22))
                RoundedRectangle(cornerRadius: 6).fill(color).frame(width: max(4, w * CGFloat(max(0, min(1, value)))))
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.leading, 8)
                    .shadow(color: .black.opacity(0.6), radius: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStartValue == nil { dragStartValue = value }
                        let delta = Double(g.translation.width / w)
                        let v = max(0, min(1, (dragStartValue ?? value) + delta))
                        value = v
                        onChange?(v)
                    }
                    .onEnded { _ in dragStartValue = nil }
            )
        }
    }
}

/// Simple horizontal level meter.
struct MeterBar: View {
    var level: Double
    var color: Color = Theme.green

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(level > 0.95 ? Theme.red : color).frame(width: max(0, geo.size.width * CGFloat(max(0, min(1, level)))))
            }
        }
    }
}

/// Custom segmented control that looks right on a dark stage UI.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var color: Color = Color.white.opacity(0.9)
    var height: CGFloat = 32

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { opt in
                Button(action: {
                    Haptics.tap()
                    selection = opt.0
                }) {
                    Text(opt.1)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundColor(selection == opt.0 ? .black : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 4)
                        .background(selection == opt.0 ? color : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.panelRaised)
        .cornerRadius(8)
    }
}

/// Stepper-like value editor: tap arrows or drag to change an integer.
struct ValueDial: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var format: (Int) -> String = { "\($0)" }
    var step: Int = 1
    @State private var dragAccumulator: CGFloat = 0

    var body: some View {
        VStack(spacing: 3) {
            CapsLabel(title, size: 9)
            HStack(spacing: 0) {
                Button(action: { change(-step) }) {
                    Image(systemName: "minus").frame(width: 28, height: 34)
                }
                .buttonStyle(.plain)
                Text(format(value))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { g in
                                let delta = -g.translation.height - dragAccumulator
                                if abs(delta) >= 6 {
                                    change(delta > 0 ? step : -step)
                                    dragAccumulator = -g.translation.height
                                }
                            }
                            .onEnded { _ in dragAccumulator = 0 }
                    )
                Button(action: { change(step) }) {
                    Image(systemName: "plus").frame(width: 28, height: 34)
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(Theme.textSecondary)
            .background(Theme.panelRaised)
            .cornerRadius(6)
        }
    }

    private func change(_ delta: Int) {
        let v = max(range.lowerBound, min(range.upperBound, value + delta))
        if v != value {
            value = v
            Haptics.tap()
        }
    }
}

/// Toggle styled as a pad.
struct ToggleButton: View {
    let title: String
    @Binding var isOn: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 36

    var body: some View {
        PadButton(title: title, color: color, active: isOn, height: height) { isOn.toggle() }
    }
}

struct StatusDot: View {
    var color: Color
    var pulsing: Bool = false
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(pulsing ? 0.5 : 1)
            .animation(pulsing ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: pulsing)
    }
}

extension View {
    func panel(_ padding: CGFloat = 8) -> some View {
        self.padding(padding)
            .background(Theme.panel)
            .cornerRadius(10)
    }
}

/// Confirmation wrapper used for destructive actions in performance mode.
struct ConfirmButton: View {
    let title: String
    let message: String
    var color: Color = Theme.red
    var requireConfirm: Bool = true
    var height: CGFloat = 40
    let action: () -> Void
    @State private var showConfirm = false

    var body: some View {
        PadButton(title: title, color: color, active: false, height: height) {
            if requireConfirm { showConfirm = true } else { action() }
        }
        .confirmationDialog(message, isPresented: $showConfirm, titleVisibility: .visible) {
            Button(title, role: .destructive) { action() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// UNDO / REDO for profile edits, shown in every EDIT header.
struct UndoButtons: View {
    @EnvironmentObject var store: AppStore
    var height: CGFloat = 30

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { Haptics.tap(); store.undo() }) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 13, weight: .bold))
                    .foregroundColor(store.canUndo ? Theme.textPrimary : Theme.textSecondary.opacity(0.4))
                    .frame(width: 40, height: height).background(Theme.panelRaised).cornerRadius(8)
            }
            .buttonStyle(.plain).disabled(!store.canUndo)
            Button(action: { Haptics.tap(); store.redo() }) {
                Image(systemName: "arrow.uturn.forward").font(.system(size: 13, weight: .bold))
                    .foregroundColor(store.canRedo ? Theme.textPrimary : Theme.textSecondary.opacity(0.4))
                    .frame(width: 40, height: height).background(Theme.panelRaised).cornerRadius(8)
            }
            .buttonStyle(.plain).disabled(!store.canRedo)
        }
    }
}
