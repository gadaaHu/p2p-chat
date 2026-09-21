import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cryptography/cryptography.dart';
import 'crypto/x3dh.dart';
import 'crypto/double_ratchet.dart';

class ServerlessWebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  
  final Function(String message) onMessageReceived;
  final Function(String code)? onCodeGenerated;
  final Function()? onConnectionEstablished;

  // Crypto state
  final DoubleRatchet _ratchet = DoubleRatchet();
  final _x25519 = X25519();
  
  SimpleKeyPair? _myIdentityKey;
  SimpleKeyPair? _myEphemeralKey;
  SimpleKeyPair? _mySignedPreKey;

  ServerlessWebRTCService({
    required this.onMessageReceived,
    this.onCodeGenerated,
    this.onConnectionEstablished,
  });

  Future<void> _initializeConnection() async {
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

    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) async {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        RTCSessionDescription? localDesc = await _peerConnection!.getLocalDescription();
        if (localDesc != null && onCodeGenerated != null) {
          
          // Add our crypto keys to the payload
          final identityPublic = await _myIdentityKey!.extractPublicKey();
          final ephemeralPublic = await _myEphemeralKey!.extractPublicKey();
          final signedPrePublic = await _mySignedPreKey!.extractPublicKey();
          
          final codeData = jsonEncode({
            'type': localDesc.type,
            'sdp': localDesc.sdp,
            'ik': base64Encode(identityPublic.bytes),
            'ek': base64Encode(ephemeralPublic.bytes),
            'spk': base64Encode(signedPrePublic.bytes),
          });
          final base64Code = base64Encode(utf8.encode(codeData));
          onCodeGenerated!(base64Code);
        }
      }
    };

    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      _dataChannel = channel;
      _setupDataChannel();
    };
    
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (onConnectionEstablished != null) {
          onConnectionEstablished!();
        }
      }
    };
  }

  void _setupDataChannel() {
    _dataChannel?.onMessage = (RTCDataChannelMessage message) async {
      if (message.isBinary) return;
      
      try {
        // Decrypt incoming message
        final encryptedPacket = jsonDecode(message.text);
        final plaintext = await _ratchet.decryptMessage(encryptedPacket);
        onMessageReceived(plaintext);
      } catch (e) {
        print("Decryption error: \$e");
        onMessageReceived("[Encrypted message failed to decrypt]");
      }
    };
    
    _dataChannel?.onDataChannelState = (RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        if (onConnectionEstablished != null) {
          onConnectionEstablished!();
        }
      }
    };
  }

  /// Step 1: User A (Alice) generates an offer code
  Future<void> generateOfferCode() async {
    // Generate Alice's keys
    _myIdentityKey = await _x25519.newKeyPair();
    _myEphemeralKey = await _x25519.newKeyPair();
    _mySignedPreKey = await _x25519.newKeyPair();

    await _initializeConnection();

    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..ordered = true;
    _dataChannel = await _peerConnection!.createDataChannel('chat', dataChannelDict);
    _setupDataChannel();

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
  }

  /// Step 2: User B (Bob) processes the offer and generates an answer
  Future<void> processOfferCode(String base64Offer) async {
    // Generate Bob's keys
    _myIdentityKey = await _x25519.newKeyPair();
    _myEphemeralKey = await _x25519.newKeyPair(); // Bob's ephemeral isn't technically needed for X3DH but we send it for symmetry
    _mySignedPreKey = await _x25519.newKeyPair();

    await _initializeConnection();

    final decodedStr = utf8.decode(base64Decode(base64Offer));
    final offerData = jsonDecode(decodedStr);

    // Extract Alice's keys
    final aliceIK = SimplePublicKey(base64Decode(offerData['ik']), type: KeyPairType.x25519);
    final aliceEK = SimplePublicKey(base64Decode(offerData['ek']), type: KeyPairType.x25519);

    // Bob computes shared secret
    final sharedSecret = await X3DH.calculateBobSharedSecret(
      IKb: _myIdentityKey!,
      SPKb: _mySignedPreKey!,
      IKa: aliceIK,
      EKa: aliceEK,
    );

    // Initialize Ratchet as Bob (Receiver first)
    await _ratchet.ratchetInitBob(sharedSecret, _mySignedPreKey!);

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offerData['sdp'], offerData['type']),
    );

    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
  }

  /// Step 3: User A (Alice) processes the answer to finalize connection
  Future<void> processAnswerCode(String base64Answer) async {
    final decodedStr = utf8.decode(base64Decode(base64Answer));
    final answerData = jsonDecode(decodedStr);

    // Extract Bob's keys
    final bobIK = SimplePublicKey(base64Decode(answerData['ik']), type: KeyPairType.x25519);
    final bobSPK = SimplePublicKey(base64Decode(answerData['spk']), type: KeyPairType.x25519);

    // Alice computes shared secret
    final sharedSecret = await X3DH.calculateAliceSharedSecret(
      IKa: _myIdentityKey!,
      EKa: _myEphemeralKey!,
      IKb: bobIK,
      SPKb: bobSPK,
    );

    // Initialize Ratchet as Alice (Sender first)
    await _ratchet.ratchetInitAlice(sharedSecret, bobSPK);

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answerData['sdp'], answerData['type']),
    );
  }

  Future<void> sendMessage(String text) async {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      // Encrypt before sending
      final encryptedPacket = await _ratchet.encryptMessage(text);
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(encryptedPacket)));
    } else {
      print("Data channel is not open");
    }
  }

  Future<void> dispose() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
  }
}
