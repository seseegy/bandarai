import 'package:flutter/material.dart';

import 'screens/bandar_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/watchlist_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BandarAiApp());
}

class BandarAiApp extends StatelessWidget {
  const BandarAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BandarAI',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      ChatScreen(isActive: _index == 1),
      const BandarScreen(),
      const WatchlistScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Beranda'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chat Analis'),
          NavigationDestination(
              icon: Icon(Icons.radar_rounded),
              selectedIcon: Icon(Icons.radar_rounded),
              label: 'Radar Bandar'),
          NavigationDestination(
              icon: Icon(Icons.star_border_rounded),
              selectedIcon: Icon(Icons.star_rounded),
              label: 'Watchlist'),
        ],
      ),
    );
  }
}
