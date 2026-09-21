import 'package:flutter/material.dart';

class ConnectionCard extends StatelessWidget {
  final String peerName;
  final String status;
  final VoidCallback onTap;

  const ConnectionCard({
    Key? key,
    required this.peerName,
    required this.status,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(peerName),
        subtitle: Text(status),
        onTap: onTap,
      ),
    );
  }
}
