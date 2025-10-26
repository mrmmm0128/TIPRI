// lib/public/public_staff_qr_list_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PublicStaffQrListPage extends StatefulWidget {
  const PublicStaffQrListPage({super.key});

  @override
  State<PublicStaffQrListPage> createState() => _PublicStaffQrListPageState();
}

class _PublicStaffQrListPageState extends State<PublicStaffQrListPage> {
  String? tenantId;

  final _searchCtrl = TextEditingController();
  String _query = '';

  // 追加: tenantIndex から解決した uid を保持
  String? _ownerUid;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    tenantId = _readTenantIdFromUrl();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 1) 必要なら匿名ログイン（セキュリティルールが閲覧にログインを要求する構成向け）
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {
      // 匿名ログインに失敗しても、公開読み取り可能ならそのまま進める
    }

    // 2) tenantIndex から uid 解決
    if (tenantId == null || tenantId!.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'tenantId が見つかりません';
      });
      return;
    }
    try {
      final idxSnap = await FirebaseFirestore.instance
          .collection('tenantIndex')
          .doc(tenantId)
          .get();

      if (!idxSnap.exists) {
        setState(() {
          _loading = false;
          _error = 'tenantIndex/${tenantId} が存在しません';
        });
        return;
      }

      final data = idxSnap.data() ?? {};
      // 想定フィールド名に幅を持たせる（運用差異に強く）
      final uid = (data['uid'] ?? data['ownerUid'] ?? data['userUid'] ?? '')
          .toString();

      if (uid.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              'tenantIndex/${tenantId} に uid がありません（uid/ownerUid/userUid のいずれも空）';
        });
        return;
      }

      setState(() {
        _ownerUid = uid;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'uid 解決に失敗しました: $e';
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? _readTenantIdFromUrl() {
    final uri = Uri.base;
    // 例: https://example.com/#/qr-all?t=xxx または ?t=xxx
    final frag = uri.fragment;
    final qi = frag.indexOf('?');
    final qp = <String, String>{}..addAll(uri.queryParameters);
    if (qi >= 0) {
      qp.addAll(Uri.splitQueryString(frag.substring(qi + 1)));
    }
    return qp['t'];
  }

  @override
  Widget build(BuildContext context) {
    // 先に致命的エラー
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        body: Center(
          child: Text(_error!, style: const TextStyle(fontFamily: 'LINEseed')),
        ),
      );
    }
    // ローディング
    if (_loading || _ownerUid == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F7F7),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Firestore パス: /{uid}/{tenantId}/employees
    final q = FirebaseFirestore.instance
        .collection(_ownerUid!) // ← 解決した uid を使用
        .doc(tenantId)
        .collection('employees')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
        elevation: 0,
        title: const Text(
          'スタッフQR一覧',
          style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'LINEseed'),
        ),
      ),
      body: Column(
        children: [
          // 説明
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.qr_code_2, color: Colors.black87),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'スタッフ個別のチップ送信ページへ誘導するQR付きポスターを作成できます。'
                      '\n・PDFをダウンロードして印刷、店内に掲示してください。',
                      style: TextStyle(
                        color: Colors.black87,
                        height: 1.35,
                        fontFamily: 'LINEseed',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 検索
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '名前で検索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          FocusScope.of(context).unfocus();
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // 一覧
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      '読み込みエラー: ${snap.error}',
                      style: const TextStyle(fontFamily: 'LINEseed'),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snap.data!.docs;
                final filtered = all.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final name = (d['name'] ?? '').toString().toLowerCase();
                  return _query.isEmpty || name.contains(_query);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      '該当するスタッフがいません',
                      style: TextStyle(fontFamily: 'LINEseed'),
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final cols = w >= 1100 ? 4 : (w >= 800 ? 3 : 2);

                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final doc = filtered[i];
                        final d = doc.data() as Map<String, dynamic>;
                        final empId = doc.id;
                        final name = (d['name'] ?? '').toString();
                        final photoUrl = (d['photoUrl'] ?? '').toString();

                        return _StaffCard(
                          name: name,
                          photoUrl: photoUrl,
                          onMakeQr: () {
                            Navigator.of(context).pushNamed(
                              '/qr-all/qr-builder',
                              arguments: {
                                'tenantId': tenantId, // 非nullはここまでに確定済み
                                'employeeId': empId,
                              },
                            );
                          },
                        );
                      },
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

class _StaffCard extends StatelessWidget {
  final String name;
  final String photoUrl;
  final VoidCallback onMakeQr;

  const _StaffCard({
    required this.name,
    required this.photoUrl,
    required this.onMakeQr,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x14000000),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onMakeQr,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: photoUrl.isNotEmpty
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl.isEmpty
                    ? const Icon(Icons.person, size: 32)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                name.isNotEmpty ? name : 'スタッフ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'LINEseed',
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Color(0xFFFCC400),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(color: Colors.black, width: 3),
                  ),
                  onPressed: onMakeQr,
                  child: const Text(
                    'QRポスターを作る',
                    style: TextStyle(fontFamily: 'LINEseed'),
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
