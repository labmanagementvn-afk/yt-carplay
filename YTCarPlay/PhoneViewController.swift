import UIKit

/// iPhone screen: a YouTube browser plus a toolbar that sends videos to the car and controls them.
final class PhoneViewController: UIViewController {
    private let player = PlayerController.shared
    private let statusLabel = UILabel()
    private var stateObserver: NSObjectProtocol?

    private lazy var backItem = UIBarButtonItem(
        image: UIImage(systemName: "chevron.backward"), style: .plain,
        target: self, action: #selector(goBack))
    private lazy var homeItem = UIBarButtonItem(
        image: UIImage(systemName: "house"), style: .plain,
        target: self, action: #selector(goHome))
    private lazy var sendItem = UIBarButtonItem(
        image: UIImage(systemName: "car.fill"), style: .plain,
        target: self, action: #selector(sendOrBringBack))
    private lazy var rewindItem = UIBarButtonItem(
        image: UIImage(systemName: "gobackward.10"), style: .plain,
        target: self, action: #selector(rewind))
    private lazy var playPauseItem = UIBarButtonItem(
        image: UIImage(systemName: "playpause.fill"), style: .plain,
        target: self, action: #selector(togglePlay))
    private lazy var forwardItem = UIBarButtonItem(
        image: UIImage(systemName: "goforward.10"), style: .plain,
        target: self, action: #selector(forward))
    private lazy var videoOnlyItem = UIBarButtonItem(
        image: UIImage(systemName: "rectangle.expand.vertical"), style: .plain,
        target: self, action: #selector(toggleVideoOnly))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = "YT CarPlay"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"), style: .plain,
            target: self, action: #selector(showSettings))

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        let webView = player.phoneWebView
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        view.addSubview(webView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])

        let space = { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }
        toolbarItems = [
            backItem, space(), homeItem, space(), sendItem, space(),
            rewindItem, space(), playPauseItem, space(), forwardItem, space(), videoOnlyItem,
        ]
        navigationController?.isToolbarHidden = false

        stateObserver = NotificationCenter.default.addObserver(
            forName: .playerStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateState() }
        }
        updateState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showSafetyNoticeIfNeeded()
    }

    deinit {
        if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
    }

    private func updateState() {
        let connected = player.isCarConnected
        let playing = player.isCarPlaying
        if !connected {
            statusLabel.text = "CarPlay not connected. Videos play here on the phone."
            statusLabel.textColor = .secondaryLabel
        } else if playing {
            statusLabel.text = "Playing on the car screen. Tap the car button to bring it back."
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.text = "CarPlay connected. Open a video, or tap the car button to send this page."
            statusLabel.textColor = .systemBlue
        }
        sendItem.isEnabled = connected
        sendItem.image = UIImage(systemName: playing ? "iphone" : "car.fill")
        for item in [rewindItem, playPauseItem, forwardItem, videoOnlyItem] {
            item.isEnabled = playing
        }
        videoOnlyItem.image = UIImage(
            systemName: player.videoOnly ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
    }

    // MARK: - Actions

    @objc private func goBack() {
        if player.phoneWebView.canGoBack { player.phoneWebView.goBack() }
    }

    @objc private func goHome() {
        player.phoneWebView.load(URLRequest(url: PlayerController.homeURL))
    }

    @objc private func sendOrBringBack() {
        if player.isCarPlaying {
            player.bringBackToPhone()
        } else {
            player.sendCurrentVideoToCar()
        }
    }

    @objc private func rewind() { player.seekCar(by: -10) }
    @objc private func forward() { player.seekCar(by: 10) }
    @objc private func togglePlay() { player.toggleCarPlayback() }
    @objc private func toggleVideoOnly() { player.videoOnly.toggle() }

    @objc private func showSettings() {
        let sheet = UIAlertController(title: "Settings", message: nil, preferredStyle: .actionSheet)
        let auto = player.autoSendToCar
        sheet.addAction(UIAlertAction(
            title: auto ? "Turn off auto-send to car" : "Auto-send videos to car",
            style: .default
        ) { [weak self] _ in
            self?.player.autoSendToCar = !auto
        })
        sheet.addAction(UIAlertAction(
            title: player.videoOnly ? "Car: show full page" : "Car: video only",
            style: .default
        ) { [weak self] _ in
            self?.player.videoOnly.toggle()
        })
        sheet.addAction(UIAlertAction(title: "Reload car player", style: .default) { [weak self] _ in
            self?.player.reloadCar()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    private func showSafetyNoticeIfNeeded() {
        let key = "safetyNoticeShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let alert = UIAlertController(
            title: "Only watch while parked",
            message: "Watching video while driving is dangerous and illegal in most places. "
                + "Use the car screen for video only when the car is parked.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "I understand", style: .default) { _ in
            UserDefaults.standard.set(true, forKey: key)
        })
        present(alert, animated: true)
    }
}
