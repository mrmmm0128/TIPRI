import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yourpay/tenant/widget/store_setting/subscription_card.dart';

class StoreDeductionInlineCard extends StatelessWidget {
  const StoreDeductionInlineCard({
    super.key,
    required this.tenantRef,
    required this.storePercentCtrl,
    required this.storePercentFocus,
    required this.savingStoreCut,
    required this.onSave,
  });

  final DocumentReference<Map<String, dynamic>> tenantRef;
  final TextEditingController storePercentCtrl;
  final FocusNode storePercentFocus;
  final bool savingStoreCut;
  final Future<void> Function() onSave;

  double? _tryParsePercent(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    if (v < 0 || v > 100) return null;
    return v;
  }

  Future<void> _openPercentDialog(
    BuildContext context, {
    required double currentPercent,
  }) async {
    // 現在値を初期値として入れておく（好みで空にも可）
    storePercentCtrl.text = currentPercent.toString();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 外タップで閉じない
      builder: (context) {
        return AlertDialog(
          title: const Text(
            '店舗が差し引く割合を入力',
            style: TextStyle(fontFamily: "LINEseed"),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('storePercentFieldDialog'),
                focusNode: storePercentFocus,
                controller: storePercentCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '店舗が差し引く金額（％）',
                  hintText: '例: 10 または 12.5',
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  // 0-9 と . だけ許可（簡易）
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onSubmitted: (_) {
                  Navigator.of(context).pop(true);
                },
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '0〜100 の範囲で入力してください。',
                  style: TextStyle(
                    color: Colors.black54,
                    fontFamily: "LINEseed",
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFCC400),
                foregroundColor: Colors.black,
              ),
              child: const Text('確定'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final v = _tryParsePercent(storePercentCtrl.text);
    if (v == null) {
      // バリデーションNG
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('0〜100 の数値（小数可）で入力してください')));
      return;
    }

    // ここで onSave を呼ぶ（onSave の中で controller を参照して保存する想定）
    try {
      await onSave();
      if (context.mounted) {
        Navigator.of(context).pop(); // ダイアログを閉じる…ではなく、すでに閉じてるので不要
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'スタッフにチップを満額渡しますか？',
              style: TextStyle(color: Colors.black87, fontFamily: "LINEseed"),
            ),
            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.schedule, size: 18, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'この変更は「今月分の明細」から自動適用されます。',
                      style: TextStyle(
                        color: Colors.black87,
                        fontFamily: "LINEseed",
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: tenantRef.snapshots(),
              builder: (context, snap2) {
                final d2 = snap2.data?.data() ?? {};
                final active = (d2['storeDeduction'] as Map?) ?? {};
                final activePercentRaw = (active['percent'] ?? 0);
                final activePercent = (activePercentRaw is num)
                    ? activePercentRaw.toDouble()
                    : 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '現在：スタッフ${(100 - activePercent).toStringAsFixed(activePercent % 1 == 0 ? 0 : 1)}%・店舗${activePercent.toStringAsFixed(activePercent % 1 == 0 ? 0 : 1)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFamily: "LINEseed",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: savingStoreCut
                            ? null
                            : () => _openPercentDialog(
                                context,
                                currentPercent: activePercent,
                              ),
                        icon: savingStoreCut
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.edit),
                        label: const Text('割合を変更'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFCC400),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(color: Colors.black, width: 3),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
