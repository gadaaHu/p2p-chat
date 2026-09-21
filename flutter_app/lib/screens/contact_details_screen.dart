import 'package:flutter/material.dart';

class ContactDetailsScreen extends StatelessWidget {
  final String contactId;

  const ContactDetailsScreen({Key? key, required this.contactId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Details')),
      body: Center(
        child: Text('Details for contact: \$contactId'),
      ),
    );
  }
}
