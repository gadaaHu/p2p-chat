import 'session_manager.dart';

class NotificationService {
  Future<void> init(SessionManager session) async {
    // Initialize flutter_local_notifications here in a full implementation
    print("NotificationService initialized");
  }

  Future<void> showMessage(String senderName, String preview) async {
    print("NOTIFICATION from \$senderName: \$preview");
  }

  Future<void> clearNotifications() async {}
}