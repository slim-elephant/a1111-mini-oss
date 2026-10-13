# A1111 Mini

A native iPhone and iPad client for Stable Diffusion. Generate images from a
chat-style screen using:

- **Automatic1111 / Forge** on your computer (txt2img, LoRAs, ControlNet,
  Hires fix, refiner, styles, upscaling, PNG info import, live previews)
- **ComfyUI** on your computer (built-in SD/SDXL graph, or your own saved
  workflows with their extra node settings)
- **On-device Core ML** (Stable Diffusion 1.5 and SDXL from Apple's
  `ml-stable-diffusion`, downloaded in the background with a Live Activity)

Plus a gallery with folders, prompt profiles, personas, generation defaults
and app lock.

This repository is the free, open-source app. The App Store build adds
optional premium features that are not part of this repo.

## Requirements

- Flutter 3.38+ (Dart 3.10)
- Xcode 26 and CocoaPods
- iOS 16.2+ (on-device SDXL needs iOS 17+ and a recent iPhone)

## Build

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run
```

To install on a device, open `ios/Runner.xcworkspace` in Xcode, pick your team
under **Signing & Capabilities**, and change the bundle identifier
(`net.neuro9.a1111mini`) to one you own.

## Connecting to your computer

Your phone and computer must be on the same network.

- **A1111 / Forge**: start with `--api --listen` (port 7860).
- **ComfyUI**: start with `--listen` (port 8188).

Then add the server in **Servers** using your computer's local IP address.

## Firebase (optional)

The app runs without Firebase. Accounts (Apple, Google, email sign-in),
analytics and the feature-request board are switched off until you add your
own project. See [FIREBASE_SETUP.md](FIREBASE_SETUP.md) and place your
`GoogleService-Info.plist` at `ios/Runner/GoogleService-Info.plist` (it is
git-ignored). Add your Firebase UID to `lib/config/admin_config.dart` and
`firestore.rules` to moderate feature requests.

## Project layout

```
lib/
  app/          theme and router
  core/         API clients, database, providers, on-device pipeline
  features/     screens (sessions, chat, gallery, servers, settings, …)
  premium/      extension point; empty in this repo
ios/Runner/     Core ML plugin and background downloads (Swift)
```

Premium hooks live behind `lib/core/premium/entitlements.dart` and
`lib/core/remote/remote_access.dart`. In this repo every premium feature is
locked and hidden.

## Contributing

Issues and pull requests are welcome. Run `flutter analyze` and
`flutter test` before opening a PR.

## License

[MIT](LICENSE)
