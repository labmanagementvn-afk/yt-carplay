import UIKit

/// Root view controller of the CarPlay window: the car-side web player plus a hint when idle.
final class CarVideoViewController: UIViewController {
    private let hintLabel = UILabel()
    private var stateObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let webView = PlayerController.shared.carWebView
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "Open a video on your iPhone to play it here"
        hintLabel.textColor = .lightGray
        hintLabel.font = .preferredFont(forTextStyle: .title2)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])

        stateObserver = NotificationCenter.default.addObserver(
            forName: .playerStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateHint() }
        }
        updateHint()
    }

    deinit {
        if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
    }

    private func updateHint() {
        let playing = PlayerController.shared.isCarPlaying
        hintLabel.isHidden = playing
        PlayerController.shared.carWebView.isHidden = !playing
    }
}
