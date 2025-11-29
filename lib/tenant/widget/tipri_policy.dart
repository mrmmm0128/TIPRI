// ② アセット画像用の簡単なビューア
import 'package:flutter/material.dart';

class SctaImageViewer extends StatelessWidget {
  const SctaImageViewer({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('特定商取引法に基づく表記')),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.asset(
            'assets/policies/チップリ特定商取引法-1.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
