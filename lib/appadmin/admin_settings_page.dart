import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 各種設定画面
/// setting コレクションを編集するページ
class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  bool _isLoading = true;
  bool _nameInputVisible = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('setting')
          .doc('name_input')
          .get();

      if (doc.exists) {
        final data = doc.data();
        setState(() {
          _nameInputVisible = (data?['visible'] as bool?) ?? false;
          _isLoading = false;
        });
      } else {
        // ドキュメントが存在しない場合は作成
        await FirebaseFirestore.instance
            .collection('setting')
            .doc('name_input')
            .set({'visible': false});
        setState(() {
          _nameInputVisible = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('設定の読み込みに失敗しました: $e')));
      }
    }
  }

  Future<void> _toggleNameInputVisible(bool value) async {
    setState(() => _nameInputVisible = value);

    try {
      await FirebaseFirestore.instance
          .collection('setting')
          .doc('name_input')
          .set({'visible': value}, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? '名前入力欄を表示に設定しました' : '名前入力欄を非表示に設定しました'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // 失敗した場合は元に戻す
      setState(() => _nameInputVisible = !value);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('設定の保存に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          '各種設定',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 説明テキスト
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    '表示制御設定',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),

                // 名前入力欄の表示制御
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.black12),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      '名前入力欄',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      _nameInputVisible ? '表示中' : '非表示',
                      style: TextStyle(
                        color: _nameInputVisible
                            ? Colors.green.shade700
                            : Colors.grey,
                      ),
                    ),
                    value: _nameInputVisible,
                    onChanged: _toggleNameInputVisible,
                    activeColor: Colors.black,
                    secondary: Icon(
                      _nameInputVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: _nameInputVisible ? Colors.black : Colors.grey,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 説明
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '設定を変更した場合、チップ送金者向け画面に即時反映されます。',
                          style: TextStyle(fontSize: 13, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
