//
//  PiPHUDManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
@preconcurrency import AVKit
import Combine

/// Менеджер плавающего оверлея Picture-in-Picture (PiP), отображаемого поверх ВСЕХ приложений и игр
@MainActor
public final class PiPHUDManager: NSObject, ObservableObject, @preconcurrency AVPictureInPictureControllerDelegate {
    public static let shared = PiPHUDManager()

    @Published public var isPiPActive: Bool = false
    @Published public var isPiPSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()

    private var pipController: AVPictureInPictureController?
    private var callViewController: AVPictureInPictureVideoCallViewController?
    private var hostingController: UIHostingController<AnyView>?
    private var anchorView: UIView?

    private override init() {
        super.init()
    }

    /// Привязка источника PiP к экрану
    public func setup(with anchorView: UIView, rootView: AnyView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("⚠️ Picture-in-Picture не поддерживается на этом устройстве")
            return
        }
        self.anchorView = anchorView

        if self.callViewController == nil {
            let callVC = AVPictureInPictureVideoCallViewController()
            callVC.preferredContentSize = CGSize(width: 154, height: 38)
            callVC.view.backgroundColor = .clear

            let hosting = UIHostingController(rootView: rootView)
            hosting.view.backgroundColor = .clear
            hosting.view.frame = CGRect(x: 0, y: 0, width: 154, height: 38)
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            callVC.addChild(hosting)
            callVC.view.addSubview(hosting.view)
            hosting.didMove(toParent: callVC)

            self.callViewController = callVC
            self.hostingController = hosting

            let source = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: anchorView,
                contentViewController: callVC
            )

            let pip = AVPictureInPictureController(contentSource: source)
            pip.delegate = self
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            self.pipController = pip
        } else {
            self.hostingController?.rootView = rootView
        }
    }

    /// Обновление содержимого внутри PiP
    public func updateRootView(_ rootView: AnyView) {
        hostingController?.rootView = rootView
    }

    /// Переключение режима Picture-in-Picture (показ плавающего окна)
    public func togglePiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    public func startPiP() {
        pipController?.startPictureInPicture()
    }

    public func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    // MARK: - AVPictureInPictureControllerDelegate

    nonisolated public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = true
        }
    }

    nonisolated public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = false
        }
    }

    nonisolated public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            self.isPiPActive = false
            print("❌ PiP ошибка: \(error.localizedDescription)")
        }
    }
}
