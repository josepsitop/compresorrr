import 'package:flutter/material.dart';

import 'ui/splash.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SqueezeApp());
}

class SqueezeApp extends StatelessWidget {
  const SqueezeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Squeeze',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Splash(),
      );
}
