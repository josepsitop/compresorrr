import 'package:flutter/material.dart';

import 'engine/store.dart';
import 'ui/splash.dart';
import 'ui/theme.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  // Archivos recibidos desde el menú del clic derecho de Windows
  if (args.isNotEmpty) store.addPaths(args, open: true);
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
