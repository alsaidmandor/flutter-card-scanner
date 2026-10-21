import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'card_overlay_painter.dart';

enum ScanMode {
  idCard(label: 'ID / Credit Card', ratio: 1.586, instruction: 'Align card within the frame'),
  document(label: 'A4 Document', ratio: 0.707, instruction: 'Position document within the frame');

  final String label;
  final double ratio;
  final String instruction;

  const ScanMode({
    required this.label,
    required this.ratio,
    required this.instruction,
  });
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
  int _selectedCameraIndex = 0;
  ScanMode _scanMode = ScanMode.idCard;
  Color _cornerColor = const Color(0xFF34D399); // Emerald green

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

    // Default to back camera
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

    final newController = CameraController(
      camera,
      ResolutionPreset.veryHigh,
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

  Future<void> _captureCard() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Demo Mode: Simulated photo capture successful!"),
          backgroundColor: Color(0xFF34D399),
        ),
      );
      return;
    }

    try {
      final XFile image = await _controller!.takePicture();
      if (!mounted) return;

      _showCapturedDialog(image);
    } catch (e) {
      debugPrint("Capture error: $e");
    }
  }

  void _showCapturedDialog(XFile image) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E242C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF34D399), size: 24),
                    SizedBox(width: 8),
                    Text(
                      "Card Captured Successfully",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: _scanMode.ratio,
                    child: kIsWeb
                        ? Image.network(image.path, fit: BoxFit.cover)
                        : Image.file(File(image.path), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Saved to: ${image.path}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34D399),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Scan Another Card", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
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
          // Layer 1: Camera Preview or Mock Simulation
          if (_isCameraInitialized && _controller != null)
            Center(
              child: CameraPreview(_controller!),
            )
          else
            _buildMockCameraBackground(),

          // Layer 2: Custom Painter with Card Cutout & Corner Borders
          AnimatedBuilder(
            animation: _scanAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: CardOverlayPainter(
                  cardAspectRatio: _scanMode.ratio,
                  cornerColor: _cornerColor,
                  overlayColor: const Color(0xAA000000),
                  scanLineProgress: _scanAnimation.value,
                ),
              );
            },
          ),

          // Layer 3: Top Navigation Bar and Mode Selector
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
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                  fontSize: 13,
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
          Icon(Icons.crop_free, color: _cornerColor, size: 18),
          const SizedBox(width: 8),
          Text(
            _scanMode.instruction,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0, left: 32.0, right: 32.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          const SizedBox(width: 48), // Balance spacing
          // Shutter Button
          GestureDetector(
            onTap: _captureCard,
            child: Container(
              width: 80,
              height: 80,
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
                child: const Icon(Icons.camera_alt, color: Colors.black, size: 30),
              ),
            ),
          ),
          // Switch Camera Button
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 28),
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
