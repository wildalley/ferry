/// Reading a subscription or share link off a QR code: live with the camera
/// on Android, or from an image file on every platform.
///
/// Both hand back text and nothing else. The import sheet shows it for the
/// user to check before anything is fetched — a QR code is an opaque link, and
/// importing straight from the camera would fetch whatever a code pointed at.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/qr_decoder.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

/// Whether this platform can scan with a camera. Android is the only one the
/// app ships on that both has one and is supported by the scanner.
bool get cameraScanSupported => Platform.isAndroid;

/// Opens the camera scanner and returns the first code's text, or null when
/// the user backs out.
Future<String?> scanQrWithCamera(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScannerPage()),
    );

/// Asks for an image and returns the code in it. Null when the user cancels;
/// a picked image with no code says so in a snackbar and also returns null.
Future<String?> pickQrImage(BuildContext context) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: l10n.qrImageGroup,
        extensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
        mimeTypes: const ['image/*'],
      ),
    ],
  );
  if (file == null) return null;
  final text = await decodeQrImage(await file.readAsBytes());
  if (text == null) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.qrNotFound)));
  }
  return text;
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  /// Detection keeps firing while the route animates away; only the first
  /// code may pop it.
  var _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final text = barcode.rawValue?.trim();
      if (text == null || text.isEmpty) continue;
      _done = true;
      Navigator.of(context).pop(text);
      return;
    }
  }

  Future<void> _fromImage() async {
    final text = await pickQrImage(context);
    if (text != null && mounted && !_done) {
      _done = true;
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final size = MediaQuery.sizeOf(context);
    final side = (size.shortestSide * .7).clamp(200.0, 320.0);
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .42),
      width: side,
      height: side,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(l10n.qrScanTitle),
        actions: [
          IconButton(
            tooltip: l10n.qrFromImage,
            onPressed: _fromImage,
            icon: const Icon(Icons.image_outlined),
          ),
          IconButton(
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            scanWindow: window,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScannerError(
              message:
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? l10n.qrCameraDenied
                      : l10n.qrCameraUnavailable,
              onFromImage: _fromImage,
            ),
          ),
          // Dim everything but the window, and frame it.
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _WindowPainter(window, palette.violetSoft),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: window.bottom + 24,
            child: Text(
              l10n.qrScanHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message, required this.onFromImage});

  final String message;
  final VoidCallback onFromImage;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 40),
              const SizedBox(height: Gap.lg),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: Gap.xl),
              FilledButton.icon(
                onPressed: onFromImage,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(l10n.qrFromImage),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  const _WindowPainter(this.window, this.accent);

  final Rect window;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(window, const Radius.circular(20));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = Colors.black.withValues(alpha: .55),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _WindowPainter old) =>
      old.window != window || old.accent != accent;
}
