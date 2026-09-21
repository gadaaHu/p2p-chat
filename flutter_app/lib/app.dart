import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/peer_registry.dart';
import 'services/session_manager.dart';
import 'services/settings_service.dart';
import 'services/webrtc_manager.dart';

class P2PChatApp extends StatelessWidget {
  final SessionManager session;
  final PeerRegistry peers;
  final SettingsService settings;
  final WebRTCManager webrtc;

  const P2PChatApp({
    super.key,
    required this.session,
    required this.peers,
    required this.settings,
    required this.webrtc,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'p2p_chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(
        session: session,
        peers: peers,
        settings: settings,
        webrtc: webrtc,
      ),
    );
  }
}