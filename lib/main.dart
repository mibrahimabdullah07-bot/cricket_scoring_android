import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.open();
  runApp(CricketApp(store: store));
}

class CricketApp extends StatelessWidget {
  const CricketApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cricket Scorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF146B45)),
        useMaterial3: true,
      ),
      home: HomePage(store: store),
    );
  }
}
