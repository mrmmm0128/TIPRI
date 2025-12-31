import 'package:flutter/material.dart';
import 'admin_dashboard_screen.dart';
import 'admin_settings_page.dart';

/// /admin で表示される選択画面
class AdminSelectPage extends StatelessWidget {
  const AdminSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          '管理者メニュー',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.admin_panel_settings,
                size: 80,
                color: Colors.black54,
              ),
              const SizedBox(height: 32),
              const Text(
                'メニューを選択してください',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 48),

              // 管理画面ボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AdminDashboardHome(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.dashboard),
                  label: const Text(
                    '管理画面',
                    style: TextStyle(fontFamily: "LINEseed"),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 各種設定画面ボタン
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AdminSettingsPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text(
                    '各種設定画面',
                    style: TextStyle(fontFamily: "LINEseed"),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
