import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'card_scanner_screen.dart';

List<CameraDescription> availableCameraList = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    availableCameraList = await availableCameras();
  } catch (e) {
    debugPrint("Failed to fetch cameras: $e");
  }

  runApp(const CardScannerApp());
}

class CardScannerApp extends StatelessWidget {
  const CardScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card & Document Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF34D399),
          surface: Color(0xFF1E242C),
        ),
      ),
      home: CardScannerScreen(cameras: availableCameraList),
    );
  }
}
