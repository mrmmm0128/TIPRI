import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// スタッフ並び替え用ダイアログを表示する関数
Future<void> showStaffReorderDialog({
  required BuildContext context,
  required String ownerId,
  required String tenantId,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StaffReorderDialog(ownerId: ownerId, tenantId: tenantId),
  );
}

class _StaffReorderDialog extends StatefulWidget {
  final String ownerId;
  final String tenantId;

  const _StaffReorderDialog({required this.ownerId, required this.tenantId});

  @override
  State<_StaffReorderDialog> createState() => _StaffReorderDialogState();
}

class _StaffReorderDialogState extends State<_StaffReorderDialog> {
  List<Map<String, dynamic>> _staffList = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(widget.ownerId)
          .doc(widget.tenantId)
          .collection('employees')
          .orderBy('sortOrder', descending: false)
          .get();

      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        list.add({
          'id': doc.id,
          'name': data['name'] ?? '',
          'photoUrl': data['photoUrl'] ?? '',
          'sortOrder': data['sortOrder'] ?? 0,
        });
      }

      // sortOrder がない場合は createdAt で再取得してソート
      if (list.isEmpty) {
        final snap2 = await FirebaseFirestore.instance
            .collection(widget.ownerId)
            .doc(widget.tenantId)
            .collection('employees')
            .orderBy('createdAt', descending: true)
            .get();

        for (final doc in snap2.docs) {
          final data = doc.data();
          list.add({
            'id': doc.id,
            'name': data['name'] ?? '',
            'photoUrl': data['photoUrl'] ?? '',
            'sortOrder': data['sortOrder'] ?? 0,
          });
        }
      }

      if (mounted) {
        setState(() {
          _staffList = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('スタッフの読み込みに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveOrder() async {
    setState(() => _saving = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final collRef = FirebaseFirestore.instance
          .collection(widget.ownerId)
          .doc(widget.tenantId)
          .collection('employees');

      for (int i = 0; i < _staffList.length; i++) {
        final docRef = collRef.doc(_staffList[i]['id']);
        batch.update(docRef, {'sortOrder': i});
      }

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '並び順を保存しました',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _staffList.removeAt(oldIndex);
      _staffList.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width < 500 ? size.width * 0.9 : 450.0;
    final dialogHeight = size.height * 0.7;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'スタッフの並び替え',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'LINEseed',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8DC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCC400), width: 1),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 18, color: Colors.black87),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'チップ支払者にも同様の順番で表示されます',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontFamily: 'LINEseed',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // スタッフ一覧
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _staffList.isEmpty
                  ? const Center(
                      child: Text(
                        'スタッフがいません',
                        style: TextStyle(fontFamily: 'LINEseed'),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _staffList.length,
                          onReorder: _onReorder,
                          proxyDecorator: (child, index, animation) {
                            return Material(
                              elevation: 4,
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              child: child,
                            );
                          },
                          itemBuilder: (context, index) {
                            final staff = _staffList[index];
                            return _StaffTile(
                              key: ValueKey(staff['id']),
                              index: index + 1,
                              name: staff['name'] as String,
                              photoUrl: staff['photoUrl'] as String,
                            );
                          },
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 16),

            // ボタン
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.black54),
                  child: const Text(
                    'キャンセル',
                    style: TextStyle(fontFamily: 'LINEseed'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saving ? null : _saveOrder,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFCC400),
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black, width: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          '保存',
                          style: TextStyle(fontFamily: 'LINEseed'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  final int index;
  final String name;
  final String photoUrl;

  const _StaffTile({
    super.key,
    required this.index,
    required this.name,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index - 1,
              child: const Icon(Icons.drag_handle, color: Colors.black38),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundImage: photoUrl.isNotEmpty
                  ? NetworkImage(photoUrl)
                  : null,
              child: photoUrl.isEmpty
                  ? const Icon(Icons.person, size: 20)
                  : null,
            ),
          ],
        ),
        title: Text(
          name.isNotEmpty ? name : 'スタッフ',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'LINEseed',
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              fontFamily: 'LINEseed',
            ),
          ),
        ),
      ),
    );
  }
}
