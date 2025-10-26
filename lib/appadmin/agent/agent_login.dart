import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/appadmin/agent/agent_detail.dart';

class AgentLoginPage extends StatefulWidget {
  const AgentLoginPage({super.key});

  @override
  State<AgentLoginPage> createState() => _AgentLoginPageState();
}

class _AgentLoginPageState extends State<AgentLoginPage> {
  // ===== Brand =====
  static const brandYellow = Color(0xFFFCC400);

  final _code = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _code.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final code = _code.text.trim();
    final pw = _pass.text;
    if (code.isEmpty || pw.isEmpty) {
      setState(() => _error = '紹介コードとパスワードを入力してください');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('agentLogin');
      final res = await fn.call({'code': code, 'password': pw});
      final data = Map<String, dynamic>.from(res.data as Map);
      final token = data['token'] as String;
      final agentId = data['agentId'] as String;
      final agent = true;
      print(agent);

      await FirebaseAuth.instance.signInWithCustomToken(token);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AgencyDetailPage(agentId: agentId, agent: agent),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      final msg = switch (e.code) {
        'not-found' => '紹介コードが見つかりません',
        'failed-precondition' => 'パスワード未設定/利用停止中の可能性があります',
        'permission-denied' => 'コードまたはパスワードが違います',
        _ => e.message ?? 'ログインに失敗しました (${e.code})',
      };
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = 'ログインに失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ===== Styles =====
  InputDecoration _blackThickInput(
    String label, {
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: Colors.black87,
        fontFamily: 'LINEseed',
      ),
      hintStyle: const TextStyle(color: Colors.black54),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 3),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 3),
      ),
    );
  }

  ButtonStyle get _brandFilled => FilledButton.styleFrom(
    backgroundColor: brandYellow,
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    side: const BorderSide(color: Colors.black, width: 3),
    textStyle: const TextStyle(
      fontFamily: 'LINEseed',
      fontWeight: FontWeight.w800,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      // appBar: AppBar(
      //   backgroundColor: Colors.white,
      //   foregroundColor: Colors.black,
      //   elevation: 0,
      //   title: const Text(
      //     '代理店ログイン',
      //     style: TextStyle(
      //       color: Colors.black,
      //       fontWeight: FontWeight.w800,
      //       fontFamily: 'LINEseed',
      //     ),
      //   ),
      //   bottom: PreferredSize(
      //     preferredSize: const Size.fromHeight(4),
      //     child: Container(height: 4, color: Colors.black),
      //   ),
      //   automaticallyImplyLeading: false,
      //   surfaceTintColor: Colors.transparent,
      // ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520), // ちょい広めでもOK
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ===== ロゴ（assets/posters/tipri.png） =====
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Image.asset(
                      'assets/posters/tipri.png',
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                  ),

                  // タイトル
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '代理店専用ログイン',
                      style: TextStyle(
                        color: Colors.black,
                        fontFamily: 'LINEseed',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.center,
                    child: Text(
                      'このログインは代理店担当者のみが利用できます。\n'
                      '紹介コードと代理店用パスワードを入力してください。',
                      style: TextStyle(color: Colors.black87, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 紹介コード
                  TextField(
                    controller: _code,
                    style: const TextStyle(
                      color: Colors.black,
                      fontFamily: 'LINEseed',
                    ),
                    cursorColor: Colors.black,
                    decoration: _blackThickInput(
                      '紹介コード',
                      hint: '例: AGT-XXXXXX',
                      prefixIcon: const Icon(
                        Icons.badge_outlined,
                        color: Colors.black,
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),

                  // パスワード
                  TextField(
                    controller: _pass,
                    obscureText: _obscure,
                    style: const TextStyle(
                      color: Colors.black,
                      fontFamily: 'LINEseed',
                    ),
                    cursorColor: Colors.black,
                    decoration: _blackThickInput(
                      'パスワード',
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: Colors.black,
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.black,
                        ),
                        tooltip: _obscure ? '表示' : '非表示',
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 16),

                  // ログインボタン（ブランド黄 + 太枠） — ほか画面と統一
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: _brandFilled,
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.black,
                                ),
                              ),
                            )
                          : const Text('ログイン'),
                    ),
                  ),

                  // エラー表示（赤）
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.red.shade700,
                              height: 1.3,
                              fontFamily: 'LINEseed',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '※ 一般の店舗オーナー/スタッフの方は通常ログインをご利用ください。',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
