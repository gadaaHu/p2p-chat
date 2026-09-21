import 'dart:async';
import 'dart:convert';

import 'package:p2p_chat/models/outbound_message.dart';
import 'package:p2p_chat/services/storage_service.dart';
import 'package:p2p_chat/services/offline_relay_service.dart';

class OutboundQueue {
  static const String _file = 'outbound_queue.json';
  static const int expiryMs = 604800000; // 7 days

  final StorageService _storage;
  final OfflineRelayService _relay;

  final Map<String, OutboundMessage> _messages = {};
  final StreamController<OutboundMessage> _stateCtrl = StreamController.broadcast();
  Timer? _retryTimer;
  bool _isProcessing = false;

  OutboundQueue(this._storage, this._relay);

  Stream<OutboundMessage> get stateChanged => _stateCtrl.stream;

  Future<void> load() async {
    final raw = await _storage.read(_file);
    if (raw != null) {
      try {
        final list = OutboundMessage.decodeList(utf8.decode(raw));
        for (final m in list) {
          _messages[m.messageId] = m;
        }
      } catch (e) {
        // ignore
      }
    }
    _scheduleRetry();
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _stateCtrl.close();
  }

  OutboundMessage? byId(String id) => _messages[id];

  Future<void> enqueue(OutboundMessage m) async {
    _messages[m.messageId] = m;
    await _save();
    _stateCtrl.add(m);
    _scheduleRetry(immediate: true);
  }

  Future<void> markDelivered(String messageId, int timestamp) async {
    final m = _messages[messageId];
    if (m == null) return;
    _update(m.copyWith(state: MessageState.delivered, deliveredAt: timestamp));
  }
  
  Future<void> markRead(String messageId) async {
    final m = _messages[messageId];
    if (m == null) return;
    _update(m.copyWith(state: MessageState.read));
  }

  Future<void> markAllBlockedForPeer(String peerDeviceId) async {
    for (final m in _messages.values.where((m) => m.peerDeviceId == peerDeviceId && !m.isTerminal)) {
      _update(m.copyWith(state: MessageState.blocked));
    }
  }

  Future<void> flushOverP2P(String peerDeviceId, Future<void> Function(OutboundMessage) send) async {
    final queued = _messages.values.where((m) => m.peerDeviceId == peerDeviceId && m.state == MessageState.queued).toList();
    for (final m in queued) {
      try {
        await send(m);
        _update(m.copyWith(state: MessageState.relayed));
      } catch (e) {
        _update(m.copyWith(lastError: e.toString()));
      }
    }
  }

  void _update(OutboundMessage m) {
    _messages[m.messageId] = m;
    _save();
    _stateCtrl.add(m);
  }

  bool _isSaving = false;

  Future<void> _save() async {
    if (_disposed || _isSaving) return;
    _isSaving = true;
    try {
      // garbage collect very old terminal messages occasionally
      final now = DateTime.now().millisecondsSinceEpoch;
      final toSave = _messages.values.where((m) {
        if (m.isTerminal && (now - m.createdAt > expiryMs)) return false;
        return true;
      }).toList();
      if (_disposed) return;
      await _storage.writeAtomic(_file, utf8.encode(OutboundMessage.encodeList(toSave)));
    } finally {
      _isSaving = false;
    }
  }

  void _scheduleRetry({bool immediate = false}) {
    if (_isProcessing || _disposed) return;
    _retryTimer?.cancel();
    if (immediate) {
      _processQueue();
    } else {
      _retryTimer = Timer(const Duration(milliseconds: 50), _processQueue);
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _disposed) return;
    _isProcessing = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      var hasMore = false;
      var nextWakeup = now + 60000;

      for (final m in _messages.values.where((m) => m.state == MessageState.queued).toList()) {
        if (now - m.createdAt > expiryMs) {
          _update(m.copyWith(state: MessageState.failed, lastError: 'expired'));
          continue;
        }

        if (now >= m.nextAttemptAt) {
          try {
            await _relay.enqueue(m.envelope);
            _update(m.copyWith(
              state: MessageState.relayed,
              attempts: m.attempts + 1,
              clearError: true,
            ));
          } catch (e) {
            final next = now + 1000 * (1 << (m.attempts < 6 ? m.attempts : 6));
            _update(m.copyWith(
              attempts: m.attempts + 1,
              nextAttemptAt: next,
              lastError: e.toString(),
            ));
            if (next < nextWakeup) nextWakeup = next;
            hasMore = true;
          }
        } else {
          if (m.nextAttemptAt < nextWakeup) nextWakeup = m.nextAttemptAt;
          hasMore = true;
        }
      }

      if (hasMore) {
        final delay = nextWakeup - DateTime.now().millisecondsSinceEpoch;
        _retryTimer = Timer(Duration(milliseconds: delay > 10 ? delay : 10), _processQueue);
      }
    } finally {
      _isProcessing = false;
    }
  }
}
