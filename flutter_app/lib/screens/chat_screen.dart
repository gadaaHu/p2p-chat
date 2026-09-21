import 'dart:async';

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../models/outbound_message.dart';
import '../services/session_manager.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final SessionManager session;
  final String peerDeviceId;

  const ChatScreen({
    super.key,
    required this.session,
    required this.peerDeviceId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messages = <Message>[];
  final _outbound = <String, OutboundMessage>{};
  final _input = TextEditingController();
  final _scroll = ScrollController();

  StreamSubscription<String>? _incomingSub;
  StreamSubscription<OutboundMessage>? _outboundSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.setPeerVisible(widget.peerDeviceId, true);

    _incomingSub = widget.session.messages.listen((text) {
      if (!mounted) return;
      setState(() {
        _messages.add(Message(
          id: 'in-${DateTime.now().microsecondsSinceEpoch}',
          conversationId: widget.peerDeviceId,
          isGroup: false,
          senderDeviceId: widget.peerDeviceId,
          text: text,
          isMe: false,
          timestamp: DateTime.now(),
        ));
      });
      _scrollToBottom();
    });

    _outboundSub = widget.session.outboundState.listen((m) {
      if (!mounted) return;
      if (m.peerDeviceId != widget.peerDeviceId) return;
      setState(() => _outbound[m.messageId] = m);
    });

    _loadHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.setPeerVisible(widget.peerDeviceId, false);
    _incomingSub?.cancel();
    _outboundSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.session.setPeerVisible(
      widget.peerDeviceId,
      state == AppLifecycleState.resumed,
    );
  }

  Future<void> _loadHistory() async {
    final history = await widget.session.messagesFor(widget.peerDeviceId);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(history);
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final id = await widget.session.sendMessage(widget.peerDeviceId, text);
    if (!mounted) return;
    setState(() {
      _messages.add(Message(
        id: id,
        conversationId: widget.peerDeviceId,
        isGroup: false,
        senderDeviceId: null,
        text: text,
        isMe: true,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.session.peers.byId(widget.peerDeviceId);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(peer?.displayName ?? widget.peerDeviceId),
            Text(
              widget.peerDeviceId,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                return MessageBubble(
                  message: m,
                  outboundState: _outbound[m.id]?.state,
                  outboundError: _outbound[m.id]?.lastError,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}