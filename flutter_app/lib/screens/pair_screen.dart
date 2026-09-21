import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/serverless_webrtc_service.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  late ServerlessWebRTCService _webRTCService;
  final TextEditingController _inputController = TextEditingController();
  
  String _generatedCode = '';
  bool _isConnected = false;
  
  // Chat messages
  final List<String> _messages = [];
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _webRTCService = ServerlessWebRTCService(
      onMessageReceived: (message) {
        setState(() {
          _messages.add("Peer: $message");
        });
      },
      onCodeGenerated: (code) {
        setState(() {
          _generatedCode = code;
        });
      },
      onConnectionEstablished: () {
        setState(() {
          _isConnected = true;
          _messages.add("System: Connected securely!");
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected to Peer!')),
        );
      },
    );
  }

  @override
  void dispose() {
    _webRTCService.dispose();
    _inputController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _generateOffer() async {
    setState(() => _generatedCode = 'Generating...');
    await _webRTCService.generateOfferCode();
  }

  void _processCode() async {
    final code = _inputController.text.trim();
    if (code.isEmpty) return;

    try {
      if (_generatedCode.isNotEmpty && _generatedCode != 'Generating...') {
        // We already generated an offer, so we are processing an Answer
        await _webRTCService.processAnswerCode(code);
        _inputController.clear();
      } else {
        // We are joining, so we process an Offer and generate an Answer
        setState(() => _generatedCode = 'Generating Answer...');
        await _webRTCService.processOfferCode(code);
        _inputController.clear();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing code: $e')),
      );
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      _webRTCService.sendMessage(text);
      setState(() {
        _messages.add("Me: $text");
      });
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnected) {
      return _buildChatInterface();
    }
    return _buildPairingInterface();
  }

  Widget _buildPairingInterface() {
    return Scaffold(
      appBar: AppBar(title: const Text('Serverless P2P Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              '1. Host a Connection',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _generateOffer,
              child: const Text('Generate Offer Code'),
            ),
            if (_generatedCode.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade200,
                child: SelectableText(
                  _generatedCode,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy Code'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _generatedCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            ],
            const Divider(height: 48),
            const Text(
              '2. Join a Connection',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Paste your peer\'s offer or answer code here:'),
            const SizedBox(height: 8),
            TextField(
              controller: _inputController,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Paste Base64 code here...',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _processCode,
              child: const Text('Submit Code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatInterface() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P Chat'),
        backgroundColor: Colors.green,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_messages[index]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
