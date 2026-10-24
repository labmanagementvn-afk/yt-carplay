import UIKit
import WebKit

extension Notification.Name {
    /// Posted whenever the car connects or disconnects, or what the car is playing changes.
    static let playerStateChanged = Notification.Name("YTCarPlayPlayerStateChanged")
}

/// Owns the two web views and everything that moves video between them.
///
/// - `phoneWebView` is a normal YouTube browser on the iPhone.
/// - `carWebView` is the player shown on the CarPlay screen.
///
/// Both share the default website data store, so being signed in to YouTube on the phone
/// also signs in the car player. When a video goes to the car, the phone's copy is paused
/// so that only one plays.
@MainActor
final class PlayerController: NSObject {
    static let shared = PlayerController()

    static let homeURL = URL(string: "https://m.youtube.com")!

    let phoneWebView: WKWebView
    let carWebView: WKWebView

    private(set) var isCarConnected = false
    private(set) var carVideoID: String?
    private var urlObservation: NSKeyValueObservation?

    var isCarPlaying: Bool { isCarConnected && carVideoID != nil }

    /// Send a video to the car as soon as it is opened on the phone.
    var autoSendToCar: Bool {
        get { UserDefaults.standard.object(forKey: "autoSendToCar") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoSendToCar") }
    }

    /// Hide everything on the car page except the video element.
    var videoOnly: Bool {
        get { UserDefaults.standard.object(forKey: "videoOnly") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "videoOnly")
            applyVideoOnly()
            notify()
        }
    }

    private override init() {
        phoneWebView = Self.makeWebView()
        carWebView = Self.makeWebView()
        super.init()

        phoneWebView.navigationDelegate = self
        phoneWebView.uiDelegate = self
        carWebView.navigationDelegate = self
        carWebView.uiDelegate = self
        carWebView.isOpaque = false
        carWebView.backgroundColor = .black
        carWebView.scrollView.backgroundColor = .black
        carWebView.isHidden = true

        installPhoneSuppressor()
        phoneWebView.load(URLRequest(url: Self.homeURL))

        urlObservation = phoneWebView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor in self?.phoneURLDidChange(webView.url) }
        }
    }

    private static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    // MARK: - Car lifecycle

    func carDidConnect() {
        isCarConnected = true
        if autoSendToCar, Self.videoID(from: phoneWebView.url) != nil {
            sendCurrentVideoToCar()
        }
        notify()
    }

    func carDidDisconnect() {
        isCarConnected = false
        carWebView.evaluateJavaScript(Self.pauseJS, completionHandler: nil)
        carWebView.load(URLRequest(url: URL(string: "about:blank")!))
        carVideoID = nil
        installPhoneSuppressor()
        setPhoneSuppressed(false)
        notify()
    }

    // MARK: - Sending video to the car

    /// Plays whatever the phone is showing on the car screen, continuing from the same position.
    func sendCurrentVideoToCar() {
        guard isCarConnected, let pageURL = phoneWebView.url else { return }
        phoneWebView.evaluateJavaScript(Self.currentTimeJS) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let seconds = (result as? Double) ?? 0
                if let id = Self.videoID(from: pageURL) {
                    self.playOnCar(videoID: id, startAt: seconds)
                } else {
                    // Not a video page: show the page itself on the car.
                    self.carVideoID = pageURL.absoluteString
                    self.carWebView.load(URLRequest(url: pageURL))
                    self.notify()
                }
            }
        }
    }

    private func playOnCar(videoID: String, startAt seconds: Double) {
        carVideoID = videoID
        var components = URLComponents(string: "https://m.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        if seconds >= 1 {
            components.queryItems?.append(URLQueryItem(name: "t", value: "\(Int(seconds))s"))
        }
        carWebView.load(URLRequest(url: components.url!))
        installPhoneSuppressor()
        setPhoneSuppressed(true)
        notify()
    }

    /// Stops the car player and resumes the video on the phone.
    func bringBackToPhone() {
        carWebView.evaluateJavaScript(Self.pauseJS, completionHandler: nil)
        carWebView.load(URLRequest(url: URL(string: "about:blank")!))
        carVideoID = nil
        installPhoneSuppressor()
        setPhoneSuppressed(false)
        phoneWebView.evaluateJavaScript(Self.playJS, completionHandler: nil)
        notify()
    }

    private func phoneURLDidChange(_ url: URL?) {
        guard isCarConnected, autoSendToCar,
              let id = Self.videoID(from: url), id != carVideoID else { return }
        playOnCar(videoID: id, startAt: 0)
    }

    // MARK: - Car playback controls

    func toggleCarPlayback() {
        carWebView.evaluateJavaScript(Self.togglePlayJS, completionHandler: nil)
    }

    func seekCar(by seconds: Double) {
        carWebView.evaluateJavaScript(Self.seekJS(seconds), completionHandler: nil)
    }

    func reloadCar() {
        carWebView.reload()
    }

    // MARK: - Page scripts

    /// Pauses any video that starts on the phone while the car is playing, so audio never doubles up.
    /// The flag is baked into a document-start script so it also holds across full page loads.
    private func installPhoneSuppressor() {
        let controller = phoneWebView.configuration.userContentController
        controller.removeAllUserScripts()
        let source = """
        window.__ytcpCarActive = \(isCarPlaying ? "true" : "false");
        document.addEventListener('play', function (e) {
            if (window.__ytcpCarActive && e.target && e.target.pause) { e.target.pause(); }
        }, true);
        """
        controller.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
    }

    private func setPhoneSuppressed(_ suppressed: Bool) {
        var js = "window.__ytcpCarActive = \(suppressed ? "true" : "false");"
        if suppressed { js += Self.pauseJS }
        phoneWebView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func applyVideoOnly() {
        carWebView.evaluateJavaScript(Self.videoOnlyJS(videoOnly), completionHandler: nil)
    }

    private func notify() {
        NotificationCenter.default.post(name: .playerStateChanged, object: self)
    }

    private static let currentTimeJS = "(function(){var v=document.querySelector('video');return v?v.currentTime:0;})()"
    private static let pauseJS = "document.querySelectorAll('video').forEach(function(v){v.pause();});"
    private static let playJS = "(function(){var v=document.querySelector('video');if(v){v.play();}})()"
    private static let togglePlayJS = """
    (function(){var v=document.querySelector('video');if(!v)return;
    if(v.paused){window.__ytcpUserPaused=false;v.play();}else{window.__ytcpUserPaused=true;v.pause();}})()
    """

    private static func seekJS(_ seconds: Double) -> String {
        "(function(){var v=document.querySelector('video');if(v){v.currentTime=Math.max(0,v.currentTime+(\(seconds)));}})()"
    }

    /// YouTube sometimes starts muted or waits for a tap; nobody can tap the car screen, so nudge it.
    private static let ensurePlayingJS = """
    (function(){var n=0;var t=setInterval(function(){var v=document.querySelector('video');
    if(v){v.muted=false;if(v.paused&&!window.__ytcpUserPaused){v.play().catch(function(){});}}
    if(++n>=15)clearInterval(t);},1000);})()
    """

    private static func videoOnlyJS(_ on: Bool) -> String {
        #"""
        (function(on){
          var id = 'ytcp-video-only';
          var s = document.getElementById(id);
          if (!on) { if (s) { s.remove(); } return; }
          if (!s) {
            s = document.createElement('style');
            s.id = id;
            (document.head || document.documentElement).appendChild(s);
          }
          s.textContent =
            'html,body{background:#000!important;overflow:hidden!important;}' +
            'body *{visibility:hidden!important;}' +
            'video{visibility:visible!important;position:fixed!important;top:0!important;left:0!important;' +
            'width:100vw!important;height:100vh!important;object-fit:contain!important;' +
            'z-index:2147483647!important;background:#000!important;transform:none!important;}';
        })(\#(on ? "true" : "false"))
        """#
    }

    // MARK: - URL parsing

    static func videoID(from url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return parts.first
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        if url.path == "/watch" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
        }
        if parts.count >= 2, ["shorts", "live", "embed"].contains(parts[0]) {
            return parts[1]
        }
        return nil
    }
}

// MARK: - WKNavigationDelegate

extension PlayerController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === carWebView else { return }
        applyVideoOnly()
        webView.evaluateJavaScript(Self.ensurePlayingJS, completionHandler: nil)
    }
}

// MARK: - WKUIDelegate

extension PlayerController: WKUIDelegate {
    /// Open `target=_blank` links in the same web view instead of dropping them.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
