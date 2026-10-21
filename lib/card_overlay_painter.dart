import 'package:flutter/material.dart';

class CardOverlayPainter extends CustomPainter {
  /// Aspect ratio of the card/paper cutout (width / height)
  /// - ID / Credit Card: ~1.586 (85.6mm / 54mm)
  /// - A4 Document Portrait: ~0.707 (1 / 1.414)
  final double cardAspectRatio;

  /// Percentage of screen width the card cutout will take (0.0 to 1.0)
  final double widthFactor;

  /// Length of the corner accent lines
  final double cornerLength;

  /// Thickness of the corner accent lines
  final double cornerStrokeWidth;

  /// Color of the corner accent guides
  final Color cornerColor;

  /// Color of the dimmed scrim surrounding the cutout
  final Color overlayColor;

  /// Corner radius of the cutout
  final double borderRadius;

  /// Optional laser scan progress (0.0 to 1.0) for an animated scanner line
  final double? scanLineProgress;

  CardOverlayPainter({
    this.cardAspectRatio = 1.586,
    this.widthFactor = 0.88,
    this.cornerLength = 32.0,
    this.cornerStrokeWidth = 4.0,
    this.cornerColor = const Color(0xFF34D399), // Emerald
    this.overlayColor = const Color(0xAA000000), // 67% black
    this.borderRadius = 16.0,
    this.scanLineProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Calculate the card cutout dimensions
    double cardWidth = size.width * widthFactor;
    double cardHeight = cardWidth / cardAspectRatio;

    // Ensure it doesn't exceed 75% of screen height
    if (cardHeight > size.height * 0.75) {
      cardHeight = size.height * 0.75;
      cardWidth = cardHeight * cardAspectRatio;
    }

    final Rect cardRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cardWidth,
      height: cardHeight,
    );

    final RRect rCardRect = RRect.fromRectAndRadius(
      cardRect,
      Radius.circular(borderRadius),
    );

    // 2. Dimmed background with punch-out transparent rectangle
    final Path backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path cutoutPath = Path()..addRRect(rCardRect);

    final Path overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    final Paint backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlayPath, backgroundPaint);

    // 3. Draw Corner Guides
    final Paint cornerPaint = Paint()
      ..color = cornerColor
      ..strokeWidth = cornerStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double l = cornerLength;
    final double r = borderRadius;

    // Top-Left Corner
    final Path tlPath = Path()
      ..moveTo(cardRect.left, cardRect.top + l)
      ..lineTo(cardRect.left, cardRect.top + r)
      ..arcToPoint(
        Offset(cardRect.left + r, cardRect.top),
        radius: Radius.circular(r),
      )
      ..lineTo(cardRect.left + l, cardRect.top);
    canvas.drawPath(tlPath, cornerPaint);

    // Top-Right Corner
    final Path trPath = Path()
      ..moveTo(cardRect.right - l, cardRect.top)
      ..lineTo(cardRect.right - r, cardRect.top)
      ..arcToPoint(
        Offset(cardRect.right, cardRect.top + r),
        radius: Radius.circular(r),
      )
      ..lineTo(cardRect.right, cardRect.top + l);
    canvas.drawPath(trPath, cornerPaint);

    // Bottom-Left Corner
    final Path blPath = Path()
      ..moveTo(cardRect.left, cardRect.bottom - l)
      ..lineTo(cardRect.left, cardRect.bottom - r)
      ..arcToPoint(
        Offset(cardRect.left + r, cardRect.bottom),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(cardRect.left + l, cardRect.bottom);
    canvas.drawPath(blPath, cornerPaint);

    // Bottom-Right Corner
    final Path brPath = Path()
      ..moveTo(cardRect.right - l, cardRect.bottom)
      ..lineTo(cardRect.right - r, cardRect.bottom)
      ..arcToPoint(
        Offset(cardRect.right, cardRect.bottom - r),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(cardRect.right - l, cardRect.bottom);
    canvas.drawPath(brPath, cornerPaint);

    // 4. Optional Animated Laser Scan Line
    if (scanLineProgress != null) {
      final double scanY = cardRect.top + (cardRect.height * scanLineProgress!);
      final Paint laserPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            cornerColor.withValues(alpha: 0.0),
            cornerColor.withValues(alpha: 0.8),
            cornerColor,
            cornerColor.withValues(alpha: 0.8),
            cornerColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
        ).createShader(Rect.fromLTWH(cardRect.left, scanY, cardRect.width, 2.0))
        ..strokeWidth = 2.0;

      canvas.drawLine(
        Offset(cardRect.left + 8, scanY),
        Offset(cardRect.right - 8, scanY),
        laserPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CardOverlayPainter oldDelegate) {
    return oldDelegate.cardAspectRatio != cardAspectRatio ||
        oldDelegate.cornerColor != cornerColor ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.scanLineProgress != scanLineProgress;
  }
}
