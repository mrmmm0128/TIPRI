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
            const SizedBox(height: 8),

            // ここはPendingのeffectiveFromを使っていなかったので、
            // シンプルに注意書きコンテナだけ残しています
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

            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('storePercentField'),
                    focusNode: storePercentFocus,
                    controller: storePercentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'スタッフから店舗が差し引く金額（％）',
                      hintText: '例: 10 または 12.5',
                      suffixText: '%',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),

            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: tenantRef.snapshots(),
              builder: (context, snap2) {
                final d2 = snap2.data?.data() ?? {};
                final active = (d2['storeDeduction'] as Map?) ?? {};
                final activePercent = (active['percent'] ?? 0);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '現在：スタッフ${100 - activePercent}%・店舗$activePercent%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFamily: "LINEseed",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),

            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: savingStoreCut ? null : onSave,
                icon: savingStoreCut
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('店舗が差し引く金額割合を保存'),
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
        ),
      ),
    );
  }
}
