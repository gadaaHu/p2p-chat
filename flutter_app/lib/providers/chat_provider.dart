import 'package:flutter/foundation.dart';
import '../services/database_service.dart';

class ChatMessage {
  final String content;
  final bool isMe;
  final String timestamp;

  ChatMessage({required this.content, required this.isMe, required this.timestamp});
}

class ChatProvider extends ChangeNotifier {
  final String peerUsername;
  List<ChatMessage> _messages = [];
  
  List<ChatMessage> get messages => _messages;

  ChatProvider(this.peerUsername) {
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final dbMessages = await DatabaseService.instance.getMessages(peerUsername);
    _messages = dbMessages.map((msg) => ChatMessage(
      content: msg['content'],
      isMe: msg['is_me'] == 1,
      timestamp: msg['timestamp'],
    )).toList();
    notifyListeners();
  }

  Future<void> addMessage(String content, {required bool isMe}) async {
    // Add to memory immediately for UI responsiveness
    final newMessage = ChatMessage(
      content: content,
      isMe: isMe,
      timestamp: DateTime.now().toIso8601String(),
    );
    _messages.add(newMessage);
    notifyListeners();

    // Persist to database in background
    await DatabaseService.instance.saveMessage(peerUsername, isMe, content);
  }
}
