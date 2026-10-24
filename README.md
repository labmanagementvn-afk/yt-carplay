# YT CarPlay

An iPhone app that plays YouTube on your CarPlay screen. You browse YouTube on the phone as usual;
when you open a video it moves to the car display and keeps playing from the same spot. The phone
then works as a remote (play/pause, skip 10 s back or forward, "video only" mode), and the car
screen has the same buttons.

> **Only watch while parked.** Video on a car screen while driving is dangerous and illegal in most
> places. The app shows this warning on first launch, and it is on you to respect it.

## Read this first: what Apple allows

CarPlay apps can't draw whatever they want. Apple only lets apps into CarPlay in a few categories
(audio, navigation, EV charging, parking, food ordering and so on), each tied to an **entitlement**
that Apple has to grant. Video players are not one of those categories, so **this app can never be
on the App Store**, and Apple will not hand out the entitlement for it.

This app uses the **navigation** entitlement (`com.apple.developer.carplay-maps`), because
navigation apps are the only ones that get a raw `CPWindow` to draw a map into. We draw a YouTube
web player there instead. That works, but it means the app has to be installed in a way that keeps
an entitlement Apple never signed:

| How you install | App on the phone | App on the CarPlay screen |
| --- | --- | --- |
| **TrollStore** (iOS 14.0 to 16.6.1, 16.7 RC, 17.0 on supported devices) | Yes | **Yes**, permanently |
| **Jailbroken** iPhone (e.g. with ldid/Filza/Sileo) | Yes | **Yes** |
| **Xcode Simulator** + CarPlay external display | Yes | **Yes** (good for trying it out) |
| Paid developer account with the CarPlay navigation entitlement approved by Apple | Yes | Yes (Apple approves real navigation apps only) |
| **Xcode with a free Apple ID**, AltStore, SideStore, Sideloadly | Yes | **No**: these re-sign with your own certificate, which strips the CarPlay entitlement, so the car never sees the app |

In short: to get video on a real car you need a phone that can run TrollStore or is jailbroken.
On a current, non-jailbroken iOS version, the free sideloading tools install the app but it will
only work on the phone.

If your car and phone support it, **iOS 26 adds AirPlay video to CarPlay while parked**. That is
Apple's official route and needs no hacks, but the carmaker has to support it, so check your car.

### YouTube terms

The app is a web browser pointed at `m.youtube.com`; it does not download or rip streams. It still
removes YouTube's normal page around the video in "video only" mode and plays video in the
background, which YouTube's Terms of Service may not allow. Keep it for personal use. Ads play as
usual; YouTube Premium removes them if you are signed in.

## Using the app

1. Open the app on the phone and sign in to YouTube if you like (sign-in carries over to the car).
2. Plug into CarPlay (or connect wirelessly). Open **YT CarPlay** on the car screen.
3. Open any video on the phone. With **auto-send** on (the default), it starts on the car screen
   and the phone's copy pauses. Otherwise tap the **car** button in the toolbar.
4. Control playback from the phone toolbar or the buttons on the car screen. The car's top bar has
   **Video only / Show page** and **Reload**. Tap the **iPhone** button to bring the video back.

The car screen is not a touch target for the web page (CarPlay doesn't pass taps through to a
navigation app's window), so pick videos on the phone.

## Building

Requirements: a Mac with **Xcode 15 or newer**. No third-party packages.

```
open YTCarPlay.xcodeproj
```

Signing settings live in [`Config/Signing.xcconfig`](Config/Signing.xcconfig):

- `PRODUCT_BUNDLE_IDENTIFIER`: change `com.yourname.ytcarplay` to something unique.
- `DEVELOPMENT_TEAM`: your team ID, or pick your team in Xcode under *Signing & Capabilities*.
- `YTCP_ENTITLEMENTS`: the CarPlay entitlement. Leave it for the Simulator and TrollStore builds;
  set it to empty for a free Apple ID build (see below).

### Try it in the Simulator (no device needed)

1. Choose an iPhone simulator and press **Run**.
2. In the Simulator menu choose **I/O > External Displays > CarPlay**.
3. In the CarPlay window, open **YT CarPlay**, then open a video in the phone simulator.

### Install with TrollStore (full CarPlay support)

Easiest: download the build from GitHub. Every push runs the **Build** workflow
(`.github/workflows/build.yml`), which uploads an artifact called `YTCarPlay` containing
`YTCarPlay.tipa`. That file is already fake-signed with the CarPlay entitlement by `ldid`.

1. Open the repo's **Actions** tab, open the latest green **Build** run, download `YTCarPlay`, unzip it.
2. AirDrop or Files-copy `YTCarPlay.tipa` to the iPhone and open it with TrollStore. Tap **Install**.

To build it yourself instead:

```
xcodebuild -project YTCarPlay.xcodeproj -target YTCarPlay -configuration Release \
  -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
brew install ldid
mkdir -p Payload && cp -R build/Release-iphoneos/YTCarPlay.app Payload/
ldid -SYTCarPlay/YTCarPlay.entitlements Payload/YTCarPlay.app/YTCarPlay
zip -qry YTCarPlay.tipa Payload
```

On a jailbroken phone, install the same `.tipa` with your package manager or Filza.

### Install with Xcode and your Apple ID (phone only)

1. Set `YTCP_ENTITLEMENTS =` (empty) in `Config/Signing.xcconfig`, and set a unique bundle ID.
2. In Xcode, select the **YTCarPlay** target, *Signing & Capabilities*, pick your team (a free
   personal team works).
3. Connect the iPhone, choose it as the run destination, press **Run**. On the phone, trust the
   developer under *Settings > General > VPN & Device Management*, and enable *Developer Mode*
   when iOS asks.

A free team's builds expire after 7 days; re-run from Xcode to refresh. With a paid account and an
approved CarPlay navigation entitlement, keep `YTCP_ENTITLEMENTS` set and the app will also appear
in the car.

### AltStore / SideStore / Sideloadly (phone only)

Install `YTCarPlay-unsigned.ipa` from the same GitHub artifact. These tools sign it with your Apple
ID, so the CarPlay entitlement is dropped, same as the Xcode route above.

## How it works

- `CarPlaySceneDelegate.swift`: the CarPlay scene. Gets a `CPWindow`, puts the car player in it, and
  adds a `CPMapTemplate` with play/pause and skip buttons.
- `PlayerController.swift`: owns two `WKWebView`s that share cookies, one browser on the phone and
  one player on the car. Watches the phone's URL; when it becomes a video, it loads the same video
  (at the same timestamp) in the car player and pauses any video on the phone. Playback controls and
  "video only" mode are small JavaScript snippets run in the car page.
- `PhoneViewController.swift`: the phone UI (browser, toolbar, settings, safety notice).
- `CarVideoViewController.swift`: the car window's content.

## Not included (yet)

Mirroring the **whole phone screen** to CarPlay. iOS has no API for that without a jailbreak; the
closest option is a ReplayKit broadcast extension feeding frames to the car window, which is
possible but laggy and memory-limited. The app plays YouTube natively on the car screen instead.
