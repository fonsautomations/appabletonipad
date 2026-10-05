import SwiftUI
import UIKit
import CoreAudioKit

/// Apple's Bluetooth MIDI picker: connects to Bluetooth MIDI peripherals (Mac, WIDI, synths…).
struct BluetoothMIDICentralView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CABTMIDICentralViewController()
        let nav = UINavigationController(rootViewController: controller)
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.done))
        context.coordinator.navigation = nav
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var navigation: UINavigationController?
        @objc func done() { navigation?.dismiss(animated: true) }
    }
}

/// Advertises the iPad as a Bluetooth MIDI peripheral so a Mac can connect to it.
struct BluetoothMIDIPeripheralView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CABTMIDILocalPeripheralViewController()
        let nav = UINavigationController(rootViewController: controller)
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.done))
        context.coordinator.navigation = nav
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var navigation: UINavigationController?
        @objc func done() { navigation?.dismiss(animated: true) }
    }
}
