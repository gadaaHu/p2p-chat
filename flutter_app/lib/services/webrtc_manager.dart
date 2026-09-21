import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCManager {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  
  final Function(String message) onMessageReceived;
  final Function(String signalingData) sendSignalingData;

  WebRTCManager({
    required this.onMessageReceived,
    required this.sendSignalingData,
  });

  // ─── SessionManager interface ──────────────────────────────────────────

  final _messageCtrl = StreamController<String>.broadcast();

  /// Stream of raw data-channel messages, for use by [SessionManager].
  Stream<String> get messages => _messageCtrl.stream;

  /// Whether the data channel is currently open.
  bool get isDataChannelOpen =>
      _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  /// Send a raw string over the data channel.
  Future<void> send(String text) async {
    if (!isDataChannelOpen) throw StateError('data channel not open');
    _dataChannel!.send(RTCDataChannelMessage(text));
  }

  Future<void> initializeConnection() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
        {"url": "stun:stun1.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": false,
        "OfferToReceiveVideo": false,
      },
      "optional": [],
    };

    _peerConnection = await createPeerConnection(configuration, offerSdpConstraints);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      sendSignalingData(jsonEncode({
        'type': 'candidate',
        'candidate': candidate.toMap(),
      }));
    };

    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      _dataChannel = channel;
      _setupDataChannel();
    };
  }

  void _setupDataChannel() {
    _dataChannel?.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) return;
      onMessageReceived(message.text);
    };
  }

  Future<void> createOffer(String targetUsername) async {
    await initializeConnection();

    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..ordered = true;
      
    _dataChannel = await _peerConnection!.createDataChannel('chat', dataChannelDict);
    _setupDataChannel();

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    sendSignalingData(jsonEncode({
      'to': targetUsername,
      'type': 'offer',
      'sdp': offer.sdp,
    }));
  }

  Future<void> handleSignalingData(Map<String, dynamic> data) async {
    final type = data['type'];

    if (type == 'offer') {
      await initializeConnection();
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(data['sdp'], type),
      );
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      sendSignalingData(jsonEncode({
        'to': data['from'],
        'type': 'answer',
        'sdp': answer.sdp,
      }));
    } else if (type == 'answer') {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(data['sdp'], type),
      );
    } else if (type == 'candidate') {
      final candidateMap = data['candidate'];
      RTCIceCandidate candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
    }
  }

  void sendMessage(String text) {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(text));
    } else {
      print("Data channel is not open");
    }
  }

  Future<void> dispose() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
  }
}
