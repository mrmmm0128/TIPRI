// logout_button.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LogoutButton extends StatefulWidget {
  const LogoutButton({super.key});

  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      // 画面スタックを全消しして /login (BootGate) へ
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ログアウトに失敗: $e',
            style: const TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: const Color(0xFFFCC400),
        ),
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _loggingOut ? null : _logout,
      child: const Text(
        'ログアウト',
        style: TextStyle(
          fontFamily: 'LINEseed',
          fontWeight: FontWeight.w700,
          // 必要なら色をつける（テーマに任せたいならこの行を消してOK）
          color: Colors.black87,
        ),
      ),
    );
  }
}
