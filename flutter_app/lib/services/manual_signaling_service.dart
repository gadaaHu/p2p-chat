import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

class ManualSignalingService {
  ServerSocket? _serverSocket;
  Socket? _activeSocket;
  
  final Function(String message) onMessageReceived;

  ManualSignalingService({required this.onMessageReceived});

  /// Listen for incoming connections on a specific port (e.g., LAN)
  Future<void> startListening(int port) async {
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    print("Listening for direct P2P connections on port $port");

    _serverSocket!.listen((Socket socket) {
      if (_activeSocket != null) {
        // Only allow one peer for now
        socket.close();
        return;
      }
      print("Peer connected from: ${socket.remoteAddress.address}");
      _activeSocket = socket;
      _listenToSocket(socket);
    });
  }

  /// Connect to a peer using their IP address and port
  Future<void> connectToPeer(String ipAddress, int port) async {
    try {
      _activeSocket = await Socket.connect(ipAddress, port, timeout: Duration(seconds: 10));
      print("Connected to peer at $ipAddress:$port");
      _listenToSocket(_activeSocket!);
    } catch (e) {
      print("Failed to connect to peer: $e");
      rethrow;
    }
  }

  void _listenToSocket(Socket socket) {
    socket.listen(
      (Uint8List data) {
        final message = utf8.decode(data);
        onMessageReceived(message);
      },
      onError: (error) {
        print("Socket error: $error");
        _activeSocket?.close();
        _activeSocket = null;
      },
      onDone: () {
        print("Peer disconnected");
        _activeSocket?.close();
        _activeSocket = null;
      },
    );
  }

  void sendMessage(String message) {
    if (_activeSocket != null) {
      _activeSocket!.add(utf8.encode(message));
    } else {
      print("No active socket connection to send message");
    }
  }

  Future<void> stop() async {
    await _activeSocket?.close();
    await _serverSocket?.close();
    _activeSocket = null;
    _serverSocket = null;
  }
}
