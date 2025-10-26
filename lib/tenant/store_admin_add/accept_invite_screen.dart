import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({super.key});
  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  // === Cloud Functions 名 ===
  static const String kAcceptFunctionName = 'acceptTenantAdminInvite';
  // （辞退があるなら↓も用意）
  static const String? kDeclineFunctionName =
      null; // 'declineTenantAdminInvite';

  // === Brand / Dims（既存トーン：黄×黒の太枠） ===
  static const brandYellow = Color(0xFFFCC400);
  static const kStroke = 3.0;
  static const kRadius = 12.0;

  String? tenantId, token;

  bool _busy = false;
  String? _resultMessage;

  // プレビュー情報
  String? _uid;
  String? _tenantName;
  String? email;
  Map<String, dynamic>? _invite;

  // 読み込み中フラグ（追加）
  bool _loadingPreview = true;

  @override
  void initState() {
    super.initState();
    _readParams();
    _bootstrapPreview();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readParams();
  }

  void _readParams() {
    final base = Uri.base;

    // ?tenantId / ?token
    tenantId = base.queryParameters['tenantId'] ?? tenantId;
    token = base.queryParameters['token'] ?? token;
    email = base.queryParameters['email'] ?? email;

    // #/path?tenantId=... 形式にも対応
    if (tenantId == null || token == null) {
      final frag = base.fragment;
      final s = frag.startsWith('/') ? frag.substring(1) : frag;
      final f = Uri.tryParse(s);
      final qp = f?.queryParameters ?? const {};
      tenantId ??= qp['tenantId'];
      token ??= qp['token'];
      email ??= qp["email"];
    }

    // ルート引数（/login 経由で戻ってくる等のケース）
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      tenantId ??= args['tenantId'] as String?;
      token ??= args['token'] as String?;
    }
    setState(() {});
  }

  bool get _hasParams =>
      (tenantId?.isNotEmpty ?? false) && (token?.isNotEmpty ?? false);

  // 画面用：白×黒の太枠パネル
  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: Colors.black, width: kStroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }

  // ===== プレビュー情報の解決 =====
  Future<void> _bootstrapPreview() async {
    setState(() => _loadingPreview = true);
    if (!_hasParams) {
      setState(() => _loadingPreview = false);
      return;
    }
    try {
      // 1) tenantIndex/{tenantId} → uid
      final idx = await FirebaseFirestore.instance
          .collection('tenantIndex')
          .doc(tenantId)
          .get();
      if (idx.exists) {
        final d = idx.data() ?? {};
        _uid = (d['uid'] ?? d['ownerUid'] ?? d['userUid'])?.toString();
      }

      if ((_uid ?? '').isNotEmpty) {
        // 2) /{uid}/{tenantId} → 店舗名
        final tDoc = await FirebaseFirestore.instance
            .collection(_uid!)
            .doc(tenantId)
            .get();
        if (tDoc.exists) {
          _tenantName = (tDoc.data()?['name'] as String?) ?? _tenantName;
        }

        // 3) 招待ドキュメント（存在すれば表示用に拾う）
        //    コレクション名の違いに備え、候補を順に試行
        final pathCandidates = <String>[
          'adminInvites', // 推奨
          'invites', // 互換
          'staffInvites', // 互換
        ];
        for (final coll in pathCandidates) {
          final inv = await FirebaseFirestore.instance
              .collection(_uid!)
              .doc(tenantId)
              .collection(coll)
              .doc(token)
              .get();
          if (inv.exists) {
            _invite = inv.data();
            break;
          }
        }
      }
    } catch (_) {
      // 失敗しても UI は続行（サーバ側で最終判定）
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  // ===== 承認実行（ログイン不要）=====
  Future<void> _accept() async {
    if (!_hasParams) {
      setState(() => _resultMessage = 'リンクが不正です。（tenantId / token が見つかりません）');
      return;
    }
    setState(() {
      _busy = true;
      _resultMessage = null;
    });

    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable(kAcceptFunctionName);
      await fn.call({'tenantId': tenantId, 'token': token, 'email': email});
      if (!mounted) return;
      setState(() => _resultMessage = '承認しました。店舗管理者として追加されました。');
    } on FirebaseFunctionsException catch (e) {
      final msg = switch (e.code) {
        'permission-denied' => '権限がありません。',
        'invalid-argument' => 'リンクが不正または期限切れです。',
        'not-found' => '招待が見つかりません。',
        'failed-precondition' => 'この招待はすでに処理済みです。',
        'unauthenticated' => '処理できません（サーバ設定）。',
        _ => '承認に失敗: ${e.message ?? e.code}',
      };
      if (!mounted) return;
      setState(() => _resultMessage = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _resultMessage = '承認に失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (kDeclineFunctionName == null) {
      setState(() => _resultMessage = 'この環境では辞退 API が未設定です。');
      return;
    }
    if (!_hasParams) {
      setState(() => _resultMessage = 'リンクが不正です。（tenantId / token が見つかりません）');
      return;
    }
    setState(() {
      _busy = true;
      _resultMessage = null;
    });

    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable(kDeclineFunctionName!);
      await fn.call({'tenantId': tenantId, 'token': token});
      if (!mounted) return;
      setState(() => _resultMessage = '招待を辞退しました。');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _resultMessage = '辞退に失敗: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _resultMessage = '辞退に失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 外部ログインURLへ遷移（tipri.jp）
  Future<void> _goLogin() async {
    final loginUrl = 'https://tipri.jp';
    await launchUrlString(
      loginUrl,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
  }

  // ===== 画面 =====
  @override
  Widget build(BuildContext context) {
    final title = _tenantName?.isNotEmpty == true
        ? '「$_tenantName」からの管理者招待'
        : '管理者招待の承認';

    // 招待の概要（あれば表示）
    final invitedEmail =
        (_invite?['email'] as String?) ?? (_invite?['targetEmail'] as String?);
    final invitedRole = (_invite?['role'] as String?) ?? 'admin';
    final staffName = (_invite?['staffName'] as String?); // 任意
    final invitedBy =
        (_invite?['invitedBy'] as String?) ??
        (_invite?['inviterName'] as String?);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        elevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'LINEseed',
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loadingPreview
          ? const Center(
              child: SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    // ===== 招待の概要（店舗名やスタッフ情報） =====
                    _panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(kRadius - 1.5),
                            ),
                            child: Container(height: 6, color: brandYellow),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.storefront,
                                color: Colors.black87,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tenantName?.isNotEmpty == true
                                      ? _tenantName!
                                      : (tenantId ?? '(店舗不明)'),
                                  style: const TextStyle(
                                    fontFamily: 'LINEseed',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (invitedBy != null && invitedBy.isNotEmpty) ...[
                            _kv('招待者', invitedBy),
                            const SizedBox(height: 6),
                          ],
                          _kv('権限', _roleJp(invitedRole)),
                          if (staffName != null && staffName.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _kv('スタッフ名', staffName),
                          ],
                          if (invitedEmail != null &&
                              invitedEmail.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _kv('招待先メール', invitedEmail),
                          ],
                          const SizedBox(height: 8),
                          const Divider(height: 24, color: Colors.black12),
                          const Text(
                            '上記の店舗から、あなたを管理者として招待しています。内容に問題なければ「承認する」を押してください。',
                            style: TextStyle(fontFamily: 'LINEseed'),
                          ),
                          if (_uid != null &&
                              _uid!.isNotEmpty &&
                              tenantId != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              '所属スタッフ（プレビュー）',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            _StaffPreviewGrid(uid: _uid!, tenantId: tenantId!),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ===== アクション =====
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: brandYellow,
                              foregroundColor: Colors.black,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontFamily: 'LINEseed',
                              ),
                              side: const BorderSide(
                                color: Colors.black,
                                width: kStroke,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(kRadius),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            onPressed: _busy ? null : _accept,
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text('承認する'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // 🔐 ログインして続行（追加）
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black,
                              side: const BorderSide(
                                color: Colors.black,
                                width: kStroke,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(kRadius),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontFamily: 'LINEseed',
                              ),
                            ),
                            onPressed: _goLogin,
                            icon: const Icon(Icons.login),
                            label: const Text('ログインして続行（tipri.jp）'),
                          ),
                        ),
                      ],
                    ),

                    if (kDeclineFunctionName != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'LINEseed',
                                ),
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: kStroke,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(kRadius),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              onPressed: _busy ? null : _decline,
                              child: const Text('辞退する'),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_resultMessage != null) ...[
                      const SizedBox(height: 12),
                      _panel(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _resultMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'LINEseed'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            k,
            style: const TextStyle(
              color: Colors.black54,
              fontFamily: 'LINEseed',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(v, style: const TextStyle(fontFamily: 'LINEseed')),
        ),
      ],
    );
  }

  String _roleJp(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('owner')) return 'オーナー';
    if (r.contains('manager')) return 'マネージャー';
    return '管理者';
  }
}

class _StaffPreviewGrid extends StatelessWidget {
  final String uid;
  final String tenantId;
  const _StaffPreviewGrid({required this.uid, required this.tenantId});

  static const kStroke = 3.0;
  static const kRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection(uid)
        .doc(tenantId)
        .collection('employees')
        .orderBy('createdAt', descending: true)
        .limit(6);

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _panel(child: const Text('スタッフ情報の取得に失敗しました'));
        }
        if (!snap.hasData) {
          return _panel(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _panel(child: const Text('スタッフ情報はまだありません'));
        }

        return _panel(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              int cross = 2;
              if (w >= 900) {
                cross = 4;
              } else if (w >= 640) {
                cross = 3;
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 120,
                ),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final m = docs[i].data() as Map<String, dynamic>;
                  final name = (m['name'] as String?)?.trim() ?? 'スタッフ';
                  final photo = (m['photoUrl'] as String?)?.trim() ?? '';

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(kRadius),
                      border: Border.all(color: Colors.black, width: kStroke),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundImage: photo.isNotEmpty
                              ? NetworkImage(photo)
                              : null,
                          backgroundColor: const Color(0xFFF6F6F6),
                          child: photo.isEmpty
                              ? Icon(
                                  Icons.person,
                                  color: Colors.black.withOpacity(.55),
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // 招待画面のトーンに合わせた太枠パネル
  Widget _panel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: Colors.black, width: kStroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}
