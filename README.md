# RoadsideReady

RoadsideReady is a SwiftUI iOS application that guides users through two offline roadside help flows: changing a flat tire and handling a dead battery. The app combines a step-driven flow engine with safety prompts, searchable reference articles, optional spoken instructions, speech-driven navigation commands, and an AR overlay for selected flat-tire steps.

## Repository Structure

```text
.
├── Icons/
│   └── RoadsideReadyIcon.png
├── RoadsideReady.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/
│       └── xcschemes/
│           └── RoadsideReady.xcscheme
├── RoadsideReady/
│   ├── RoadsideReadyApp.swift
│   ├── RootView.swift
│   ├── FlowEngine.swift
│   ├── FlowScreen.swift
│   ├── Flows.swift
│   ├── Models.swift
│   ├── ManualDrawer.swift
│   ├── Articles.swift
│   ├── ArticlesSheetView.swift
│   ├── SpeechController.swift
│   ├── VoiceCommandController.swift
│   ├── ARSessionModel.swift
│   ├── ARViewContainer.swift
│   ├── ARFullScreenView.swift
│   ├── StepProgressIndicator.swift
│   ├── StepProgressPill.swift
│   ├── Info.plist
│   ├── Assets.xcassets/
│   └── Assets copy.xcassets/
└── dummy/
    ├── Package.swift
    ├── RoadsideReadyApp.swift
    ├── RootView.swift
    ├── FlowEngine.swift
    ├── FlowScreen.swift
    ├── Flows.swift
    ├── Models.swift
    ├── ManualDrawer.swift
    ├── Articles.swift
    ├── ArticlesSheetView.swift
    ├── SpeechController.swift
    ├── ARSessionModel.swift
    ├── ARViewContainer.swift
    ├── StepProgressIndicator.swift
    ├── StepProgressPill.swift
    ├── Assets.xcassets/
    └── Mocks.swift
```

## Key Features

- Two built-in guided assistance modes: `Flat Tire` and `Dead Battery`.
- Step-based navigation backed by in-memory flow definitions in [`RoadsideReady/Flows.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/Flows.swift:1).
- Safety flags and step progress tracking through [`RoadsideReady/FlowEngine.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/FlowEngine.swift:1) and [`RoadsideReady/Models.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/Models.swift:1).
- Searchable, tag-filtered reference articles surfaced in a slide-out drawer and sheet views.
- Optional text-to-speech playback for current step instructions.
- Optional speech recognition commands for `next`, `back`, `repeat`, and stopping voice control.
- AR guidance for flat-tire steps, including wheel placement, lug-count setup, and lug-tightening sequence support.
- Simulator fallback UI when the AR camera is unavailable.

## Tech Stack

| Area | Details |
| --- | --- |
| Language | Swift |
| UI | SwiftUI |
| State management | `ObservableObject`, `@StateObject`, `@AppStorage`, Combine |
| AR | ARKit, RealityKit |
| Audio / speech | AVFoundation, Speech |
| Project format | Xcode project (`RoadsideReady.xcodeproj`) |
| Secondary packaging artifact | Generated Swift package wrapper in `dummy/Package.swift` |

## Architecture Notes

- [`RoadsideReady/RoadsideReadyApp.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/RoadsideReadyApp.swift:1) launches [`RootView`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/RootView.swift:85), which owns the top-level `FlowEngine`, mode switcher, and articles drawer.
- [`FlowEngine`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/FlowEngine.swift:14) is the navigation state machine. It loads one of two `RescueFlow` definitions and manages the current step, back stack, and progress text.
- [`Flows.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/Flows.swift:10) stores the actual roadside procedures as structured data rather than remote content or JSON files.
- [`FlowScreen`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/FlowScreen.swift:63) is the main guided experience. It coordinates step rendering, completion handling, speech playback, voice control, and AR presentation.
- [`Articles.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/Articles.swift:12) and [`ManualDrawer.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/ManualDrawer.swift:3) implement a small local knowledge base scoped by rescue mode.
- [`ARSessionModel.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/ARSessionModel.swift:7) and [`ARViewContainer.swift`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady/ARViewContainer.swift:10) handle AR placement state and RealityKit scene behavior for flat-tire guidance.
- The `dummy/` directory contains a mirrored copy of the app sources plus an auto-generated [`Package.swift`](/Users/jasonco/Documents/RoadsideReady/dummy/Package.swift:1). Based on repository contents, it appears to be a generated package-based wrapper of the same app rather than a separate production target.

## Getting Started

### Requirements

- Xcode with support for the project’s current Apple platform settings.
- An iPhone or iPad if you want to exercise the AR camera flow. The app includes a simulator fallback for the AR panel.

### Open and Run

1. Open `RoadsideReady.xcodeproj` in Xcode.
2. Select the shared `RoadsideReady` scheme.
3. Build and run the app on a simulator or supported device.
4. On first launch, the app requests microphone and speech recognition access for voice features. Camera access is required for AR guidance.

## Available Scripts or Commands

No repository-defined script runner is present.

- No `Makefile`
- No `package.json`
- No `Podfile`
- No Fastlane configuration
- No documented CLI task wrappers

The shared Xcode scheme at [`RoadsideReady.xcodeproj/xcshareddata/xcschemes/RoadsideReady.xcscheme`](/Users/jasonco/Documents/RoadsideReady/RoadsideReady.xcodeproj/xcshareddata/xcschemes/RoadsideReady.xcscheme:1) supports build, run, analyze, profile, and archive actions through Xcode.

## Environment Variables

No environment variable files or sample env files are present in the repository. The app’s current configuration is embedded in source and Xcode project settings.

## Testing

No test target, test bundle, or dedicated test plan is present in the repository.

- The shared Xcode scheme enables test actions, but no concrete tests are defined in the inspected tree.
- There are no unit, UI, or snapshot test directories in the current project structure.

## Build / Deployment Notes

- The main Xcode target is `RoadsideReady` with bundle identifier `com.jasonco.RoadsideReady`.
- The project file defines `Debug` and `Release` configurations and supports archive actions through the shared scheme.
- The project requests permissions for camera, microphone, and speech recognition in Xcode build settings.
- No CI configuration, release automation, App Store delivery scripts, containerization files, or deployment manifests are present in the repository.

## Future Improvements

Omitted intentionally: the repository does not include a documented roadmap or planned improvement list.
