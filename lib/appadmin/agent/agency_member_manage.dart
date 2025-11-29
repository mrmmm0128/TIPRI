import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AgencyMemberManagePage extends StatefulWidget {
  final String agentId;

  const AgencyMemberManagePage({super.key, required this.agentId});

  @override
  State<AgencyMemberManagePage> createState() => _AgencyMemberManagePageState();
}

class _AgencyMemberManagePageState extends State<AgencyMemberManagePage> {
  static const brandYellow = Color(0xFFFCC400);

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // ★ 保存先（必要に応じてここだけ変更）
  CollectionReference<Map<String, dynamic>> get _membersRef => FirebaseFirestore
      .instance
      .collection('agencies')
      .doc(widget.agentId)
      .collection('members');

  Future<void> _addMember() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('メールアドレスを入力してください')));
      return;
    }

    setState(() => _saving = true);
    try {
      await _membersRef.add({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _nameCtrl.clear();
      _emailCtrl.clear();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('メンバーを追加しました')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('追加に失敗しました：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeMember(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('メンバーを削除しますか？'),
        content: const Text('このメンバーを削除すると元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _membersRef.doc(id).delete();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('削除しました')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('削除に失敗しました：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'メンバー管理',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 追加フォーム
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 12, hp, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'メンバーを追加',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '氏名（任意）',
                    filled: true,
                    fillColor: Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black, width: 3),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black, width: 3),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    filled: true,
                    fillColor: Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black, width: 3),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black, width: 3),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: brandYellow,
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black, width: 3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _saving ? null : _addMember,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.person_add_alt),
                    label: Text(_saving ? '追加中…' : '追加'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.black12),

          // メンバー一覧
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _membersRef.orderBy('createdAt').snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('読み込みエラー：${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('メンバーが登録されていません'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Colors.black12),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final data = d.data();
                    final name = (data['name'] ?? '').toString();
                    final email = (data['email'] ?? '').toString();

                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        child: Icon(Icons.person),
                      ),
                      title: Text(
                        name.isNotEmpty ? name : '(名前未設定)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: email.isNotEmpty ? Text(email) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '削除',
                        onPressed: () => _removeMember(d.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
