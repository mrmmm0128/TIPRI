import 'package:flutter/material.dart';

/// 使い方: MaterialAppの画面として表示
///   home: const LoadingPage(message: '読み込み中...'),
class LoadingPage extends StatelessWidget {
  final String message;
  const LoadingPage({super.key, this.message = 'Loading...'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 好みで
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ローディングインジケータ
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // メッセージ
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
