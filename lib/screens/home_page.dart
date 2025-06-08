import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  final String userEmail;

  const HomePage({super.key, required this.userEmail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Text('Welcome to our application, $userEmail!\nAssia main page, thanks!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
