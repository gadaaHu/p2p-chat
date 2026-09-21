class TransferService {
  void initialize() {
    print("TransferService initialized");
  }

  Future<void> sendFile(String peerId, String filePath) async {
    // Basic stub: chunk a file and send it over WebRTC data channels
    print("Sending file \$filePath to \$peerId");
  }

  Future<void> receiveFile(String peerId, String fileName) async {
    // Basic stub: assemble incoming file chunks
    print("Receiving file \$fileName from \$peerId");
  }
}
