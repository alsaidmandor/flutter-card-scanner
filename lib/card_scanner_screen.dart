import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'card_overlay_painter.dart';

enum ScanMode {
  idCard(
    label: '🪪 ID / Credit Card',
    ratio: 1.586, // Standard ID-1 card aspect ratio (85.6mm x 53.98mm)
    widthFactor: 0.88,
    instruction: 'Point camera over the card to fit frame',
  ),
  document(
    label: '📄 A4 Document / Paper',
    ratio: 0.707, // Standard A4 portrait aspect ratio (210mm x 297mm)
    widthFactor: 0.80,
    instruction: 'Point camera over the page to fit frame',
  );

  final String label;
  final double ratio;
  final double widthFactor;
  final String instruction;

  const ScanMode({
    required this.label,
    required this.ratio,
    required this.widthFactor,
    required this.instruction,
  });
}

class CropParams {
  final String srcPath;
  final String destPath;
  final double screenWidth;
  final double screenHeight;
  final double cardWidth;
  final double cardHeight;

  CropParams({
    required this.srcPath,
    required this.destPath,
    required this.screenWidth,
    required this.screenHeight,
    required this.cardWidth,
    required this.cardHeight,
  });
}

/// Crops the camera image to the exact border cutout
Future<String> _cropImageWorker(CropParams params) async {
  try {
    final file = File(params.srcPath);
    if (!await file.exists()) return params.srcPath;

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return params.srcPath;

    // Apply EXIF camera rotation so pixel coordinates match what the user saw
    final oriented = img.bakeOrientation(decoded);
    final imgW = oriented.width.toDouble();
    final imgH = oriented.height.toDouble();

    // Calculate BoxFit.cover scale on screen
    final scale = math.max(params.screenWidth / imgW, params.screenHeight / imgH);
    final displayedW = imgW * scale;
    final displayedH = imgH * scale;

    final offsetX = (displayedW - params.screenWidth) / 2.0;
    final offsetY = (displayedH - params.screenHeight) / 2.0;

    final screenLeft = (params.screenWidth - params.cardWidth) / 2.0;
    final screenTop = (params.screenHeight - params.cardHeight) / 2.0;

    final cropX = ((screenLeft + offsetX) / scale).round().clamp(0, oriented.width - 1);
    final cropY = ((screenTop + offsetY) / scale).round().clamp(0, oriented.height - 1);
    final cropW = (params.cardWidth / scale).round().clamp(1, oriented.width - cropX);
    final cropH = (params.cardHeight / scale).round().clamp(1, oriented.height - cropY);

    final cropped = img.copyCrop(
      oriented,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    final croppedBytes = img.encodeJpg(cropped, quality: 90);
    final destFile = File(params.destPath);
    await destFile.writeAsBytes(croppedBytes);
    return params.destPath;
  } catch (e) {
    debugPrint("Background crop note: $e, falling back to original");
    return params.srcPath;
  }
}

class CardScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CardScannerScreen({super.key, required this.cameras});

  @override
  State<CardScannerScreen> createState() => _CardScannerScreenState();
}

class _CardScannerScreenState extends State<CardScannerScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isFlashOn = false;
  bool _isProcessing = false;
  int _selectedCameraIndex = 0;

  ScanMode _scanMode = ScanMode.idCard;
  Color _cornerColor = const Color(0xFF34D399); // Emerald

  late AnimationController _animController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      if (kDebugMode) {
        print("No camera hardware detected. Running in mock/preview mode.");
      }
      return;
    }

    int backCameraIdx = widget.cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    _selectedCameraIndex = backCameraIdx != -1 ? backCameraIdx : 0;

    await _setupCameraController(widget.cameras[_selectedCameraIndex]);
  }

  Future<void> _setupCameraController(CameraDescription camera) async {
    final oldController = _controller;
    if (oldController != null) {
      _controller = null;
      await oldController.dispose();
    }

    // High resolution: 1080p (ideal balance of clarity, speed, and low memory)
    final newController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await newController.initialize();
      if (!mounted) return;
      setState(() {
        _controller = newController;
        _isCameraInitialized = true;
      });
    } catch (e) {
      if (kDebugMode) {
        print("Camera initialization error: $e");
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final newMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
      await _controller!.setFlashMode(newMode);
      setState(() => _isFlashOn = !_isFlashOn);
    } catch (e) {
      debugPrint("Torch toggle error: $e");
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    final nextIdx = (_selectedCameraIndex + 1) % widget.cameras.length;
    _selectedCameraIndex = nextIdx;
    await _setupCameraController(widget.cameras[nextIdx]);
  }

  /// Calculates the automatic optimal size of the card border for the screen
  Size _calculateCutoutSize(Size screenSize) {
    double cardWidth = screenSize.width * _scanMode.widthFactor;
    double cardHeight = cardWidth / _scanMode.ratio;

    // Prevent border from being taller than 72% of the screen
    if (cardHeight > screenSize.height * 0.72) {
      cardHeight = screenSize.height * 0.72;
      cardWidth = cardHeight * _scanMode.ratio;
    }

    return Size(cardWidth, cardHeight);
  }

  /// Snaps the card and presents preview in bottom sheet (does NOT save automatically)
  Future<void> _captureCard() async {
    if (_isProcessing) return;

    if (_controller == null || !_controller!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Demo Mode: Point at card and test preview!"),
          backgroundColor: Color(0xFF34D399),
        ),
      );
      return;
    }

    final screenSize = MediaQuery.of(context).size;
    final cutoutSize = _calculateCutoutSize(screenSize);

    setState(() => _isProcessing = true);

    try {
      // 1. Take raw photo
      final XFile rawPhoto = await _controller!.takePicture();

      // 2. Prepare temp path for cropped card
      final Directory tempDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String tempCroppedPath = '${tempDir.path}/temp_crop_$timestamp.jpg';

      // 3. Crop to the border dimensions
      final cropParams = CropParams(
        srcPath: rawPhoto.path,
        destPath: tempCroppedPath,
        screenWidth: screenSize.width,
        screenHeight: screenSize.height,
        cardWidth: cutoutSize.width,
        cardHeight: cutoutSize.height,
      );

      final String croppedPath = await compute(_cropImageWorker, cropParams);
      final File croppedFile = File(croppedPath);

      if (!mounted) return;

      // 4. Show preview sheet with Accept / Reject buttons (NOT saved yet)
      _showReviewBottomSheet(croppedFile);
    } catch (e) {
      debugPrint("Capture error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not capture image: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Saves the accepted image permanently to app storage and Photo Gallery
  Future<void> _saveAcceptedImage(File tempFile) async {
    try {
      // 1. Save permanently to app documents directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String finalFileName = 'scan_${_scanMode.name}_$timestamp.jpg';
      final String permanentPath = '${appDir.path}/$finalFileName';

      final File savedFile = await tempFile.copy(permanentPath);

      // 2. Request permission and save to Gallery
      bool savedToGallery = false;
      try {
        final hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          final granted = await Gal.requestAccess();
          if (granted) {
            await Gal.putImage(savedFile.path, album: 'CardScanner');
            savedToGallery = true;
          }
        } else {
          await Gal.putImage(savedFile.path, album: 'CardScanner');
          savedToGallery = true;
        }
      } catch (galError) {
        debugPrint("Gallery save note: $galError");
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF34D399)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  savedToGallery
                      ? "Saved to Photos Gallery & Device Storage!"
                      : "Saved to Device Storage!",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E242C),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint("Save error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Review Bottom Sheet: Zero overflow, lets user accept or reject
  void _showReviewBottomSheet(File previewFile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E242C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        return Container(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // Title
                  const Text(
                    "Review Scanned Image",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Cropped to border. Do you want to save this to your device?",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 14),

                  // Image Preview (constrained so it never overflows)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: screenHeight * 0.38,
                      minHeight: 120,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          previewFile,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Action Buttons: Save vs Retake
                  Row(
                    children: [
                      // Retake / Reject Button
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx); // Close without saving
                            try {
                              previewFile.delete(); // Clean up temp file
                            } catch (_) {}
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text("Retake", style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Accept / Save Button
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF34D399),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _saveAcceptedImage(previewFile);
                          },
                          icon: const Icon(Icons.download_done, size: 20),
                          label: const Text(
                            "Save to Device",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Full-screen Camera Feed
          if (_isCameraInitialized && _controller != null)
            _buildFullScreenCamera()
          else
            _buildMockCameraBackground(),

          // Layer 2: Automatic Cutout Border Painter
          AnimatedBuilder(
            animation: _scanAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: CardOverlayPainter(
                  cardAspectRatio: _scanMode.ratio,
                  widthFactor: _scanMode.widthFactor, // Automatic optimal width
                  cornerColor: _cornerColor,
                  overlayColor: const Color(0xAA000000),
                  scanLineProgress: _scanAnimation.value,
                ),
              );
            },
          ),

          // Layer 3: Controls & Top Bar
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const SizedBox(height: 8),
                _buildModeChips(),
                const Spacer(),
                _buildInstructionBadge(),
                const SizedBox(height: 20),
                _buildBottomControls(),
              ],
            ),
          ),

          // Layer 4: Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF34D399)),
                    SizedBox(height: 16),
                    Text(
                      "Cropping card...",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFullScreenCamera() {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.previewSize?.height ?? 1080,
          height: _controller!.value.previewSize?.width ?? 1920,
          child: CameraPreview(_controller!),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: Colors.black45,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          Row(
            children: [
              // Corner Color Selector
              PopupMenuButton<Color>(
                icon: Icon(Icons.palette_outlined, color: _cornerColor),
                color: const Color(0xFF242A34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (color) => setState(() => _cornerColor = color),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: Color(0xFF34D399),
                    child: Text("Emerald Green", style: TextStyle(color: Color(0xFF34D399))),
                  ),
                  const PopupMenuItem(
                    value: Color(0xFF38BDF8),
                    child: Text("Sky Blue", style: TextStyle(color: Color(0xFF38BDF8))),
                  ),
                  const PopupMenuItem(
                    value: Color(0xFFFBBF24),
                    child: Text("Amber Gold", style: TextStyle(color: Color(0xFFFBBF24))),
                  ),
                  const PopupMenuItem(
                    value: Colors.white,
                    child: Text("Clean White", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Torch Toggle
              CircleAvatar(
                backgroundColor: _isFlashOn ? Colors.amber : Colors.black45,
                child: IconButton(
                  icon: Icon(
                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                    color: _isFlashOn ? Colors.black : Colors.white,
                  ),
                  onPressed: _toggleTorch,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ScanMode.values.map((mode) {
          final isSelected = mode == _scanMode;
          return GestureDetector(
            onTap: () => setState(() => _scanMode = mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? _cornerColor : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                mode.label,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInstructionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cornerColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.crop_free, color: _cornerColor, size: 16),
          const SizedBox(width: 8),
          Text(
            _scanMode.instruction,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28.0, left: 32.0, right: 32.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          const SizedBox(width: 48),
          // Shutter Button
          GestureDetector(
            onTap: _captureCard,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  color: _cornerColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, color: Colors.black, size: 28),
              ),
            ),
          ),
          // Switch Camera Button
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 26),
            onPressed: widget.cameras.length > 1 ? _switchCamera : null,
          ),
        ],
      ),
    );
  }

  /// Fallback graphic for simulator/desktop when no physical camera is accessible
  Widget _buildMockCameraBackground() {
    return Container(
      color: const Color(0xFF181C24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 250,
              height: 158,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C3E50), Color(0xFF3498DB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "SAMPLE CARD",
                        style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2),
                      ),
                      Icon(Icons.contactless, color: Colors.white70, size: 20),
                    ],
                  ),
                  Text(
                    "••••  ••••  ••••  8912",
                    style: TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 3, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "JOHN DOE",
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Camera Preview Active",
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
