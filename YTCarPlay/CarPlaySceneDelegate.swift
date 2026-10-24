import CarPlay
import UIKit

/// The CarPlay screen.
///
/// The app declares the CarPlay *navigation* entitlement (`com.apple.developer.carplay-maps`).
/// Navigation apps are the only CarPlay category that is handed a `CPWindow` it can draw
/// arbitrary UIKit content into, which is what lets us put a web video player on the car screen.
/// A `CPMapTemplate` sits on top of that window and provides the car-side buttons.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?
    private var playPauseButton: CPMapButton?
    private var videoOnlyButton: CPBarButton?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.carWindow = window

        let videoController = CarVideoViewController()
        window.rootViewController = videoController

        interfaceController.setRootTemplate(makeMapTemplate(), animated: false, completion: nil)
        PlayerController.shared.carDidConnect()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        PlayerController.shared.carDidDisconnect()
        window.rootViewController = nil
        self.interfaceController = nil
        self.carWindow = nil
    }

    private func makeMapTemplate() -> CPMapTemplate {
        let template = CPMapTemplate()
        template.automaticallyHidesNavigationBar = true
        template.hidesButtonsWithNavigationBar = true

        let player = PlayerController.shared

        let back = CPMapButton { _ in player.seekCar(by: -10) }
        back.image = UIImage(systemName: "gobackward.10")

        let playPause = CPMapButton { _ in player.toggleCarPlayback() }
        playPause.image = UIImage(systemName: "playpause.fill")
        playPauseButton = playPause

        let forward = CPMapButton { _ in player.seekCar(by: 10) }
        forward.image = UIImage(systemName: "goforward.10")

        template.mapButtons = [back, playPause, forward]

        let videoOnly = CPBarButton(title: videoOnlyTitle()) { [weak self] _ in
            player.videoOnly.toggle()
            self?.videoOnlyButton?.title = self?.videoOnlyTitle() ?? ""
        }
        videoOnlyButton = videoOnly
        template.leadingNavigationBarButtons = [videoOnly]

        let reload = CPBarButton(title: "Reload") { _ in player.reloadCar() }
        template.trailingNavigationBarButtons = [reload]

        return template
    }

    private func videoOnlyTitle() -> String {
        PlayerController.shared.videoOnly ? "Show page" : "Video only"
    }
}
