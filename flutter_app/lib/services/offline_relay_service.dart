import '../models/encrypted_envelope.dart';

class OfflineRelayService {
  void initialize() {
    print("OfflineRelayService initialized");
  }

  Future<void> enqueue(EncryptedEnvelope envelope) async {
    // Basic stub: HTTP POST to FastAPI backend to store message temporarily
    print("Sent offline message for ${envelope.toDeviceId} to relay server");
  }

  Future<void> fetchFromRelay() async {
    // Basic stub: HTTP GET to FastAPI backend to retrieve offline messages
    print("Fetched offline messages from relay server");
  }
}
