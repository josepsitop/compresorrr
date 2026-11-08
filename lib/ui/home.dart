import 'package:flutter/material.dart';

import '../engine/history.dart';
import '../engine/models.dart';
import '../engine/native.dart';
import '../engine/store.dart';
import 'library_tab.dart';
import 'more_tab.dart';
import 'preset_sheet.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
    history.load();
    // Android: archivos recibidos desde "Compartir" en la galería, WhatsApp, etc.
    Native.init((paths) => store.addPaths(paths, open: true));
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStore());
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    setState(() {});
    final r = store.request;
    if (r != null) {
      store.request = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showPresetSheet(context, r.kind, r.items);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: store.tab,
          children: const [
            LibraryTab(kind: Kind.photo),
            LibraryTab(kind: Kind.video),
            LibraryTab(kind: Kind.file),
            MoreTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: store.tab,
        onDestinationSelected: store.setTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.photo_outlined), selectedIcon: Icon(Icons.photo), label: 'Fotos'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: 'Videos'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Archivos'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Más'),
        ],
      ),
    );
  }
}
