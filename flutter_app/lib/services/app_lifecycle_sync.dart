import 'package:flutter/widgets.dart';
import 'session_manager.dart';

class AppLifecycleSync with WidgetsBindingObserver {
  void attach(SessionManager session) {
    WidgetsBinding.instance.addObserver(this);
    print("AppLifecycleSync attached");
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("App resumed, refreshing connections");
      // In a full implementation, we would reconnect WebRTC or flush queues here
    } else if (state == AppLifecycleState.paused) {
      print("App paused, suspending connections");
    }
  }
}