# Flutter Card & Document Camera Scanner 📷🪪

A Flutter camera scanner application featuring a custom **cutout border overlay** (viewfinder) with corner guides to easily align and scan ID cards, credit cards, and paper documents.

---

## ✨ Features

- **Custom Border Cutout**: Uses Flutter's `Path.combine(PathOperation.difference, ...)` with `CustomPainter` to produce a transparent punch-hole inside a dimmed backdrop.
- **Dynamic Aspect Ratios**:
  - **ID / Credit Card**: Standard ISO/IEC 7810 ID-1 ratio (`1.586`).
  - **A4 / Letter Document**: Standard document aspect ratio (`0.707` portrait).
- **Scanner Laser Animation**: Smooth scanning beam effect running inside the card boundary.
- **Corner Guides**: Rounded corner borders with customizable color palette (Emerald Green, Sky Blue, Amber, White).
- **Torch & Lens Controls**: Easy toggling between rear/front lenses and flashlight.
- **Card Capture**: Snaps the picture with `takePicture()` and provides an interactive bottom preview modal.
- **Fallback Simulation**: If camera hardware is not available (e.g. running on simulator), the app gracefully enters interactive preview mode.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (>= 3.12.0)
- Android Studio / VS Code / Xcode

### Installation & Run

1. Clone the repository:
   ```bash
   git clone https://github.com/alsaidmandor/flutter-card-scanner.git
   cd flutter-card-scanner
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run on your connected device:
   ```bash
   flutter run
   ```

---

## 📁 Key Files

- [`lib/card_overlay_painter.dart`](lib/card_overlay_painter.dart): CustomPainter handling the cutout mask, corner borders, and laser line.
- [`lib/card_scanner_screen.dart`](lib/card_scanner_screen.dart): Camera viewfinder screen with preview, controls, and capture handler.
- [`lib/main.dart`](lib/main.dart): Application initialization and camera detection.
