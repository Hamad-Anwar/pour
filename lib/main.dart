import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/pour_binding.dart';
import 'views/pour_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PourApp());
}

class PourApp extends StatelessWidget {
  const PourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Pour',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3E6B4F),
          primary: const Color(0xFF3E6B4F),
          surface: const Color(0xFFF6F0E6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F0E6),
      ),
      initialBinding: PourBinding(),
      home: const PourView(),
    );
  }
}
