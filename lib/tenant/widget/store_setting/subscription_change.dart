import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/tenant/widget/store_setting/b_plan.dart';
import 'package:yourpay/tenant/widget/store_setting/c_plan.dart';
import 'package:yourpay/tenant/widget/store_setting/subscription_card.dart';
import 'package:yourpay/tenant/widget/store_setting/trial_progress_bar.dart';
import 'package:yourpay/tenant/widget/store_staff/show_video_preview.dart';

class SubscriptionPlanCard extends StatefulWidget {
  final String currentPlan;
  final bool periodEndBool;
  final DateTime? periodEnd;

  final String? trialStatus;
  final DateTime? trialStart;
  final DateTime? trialEnd;

  final String tenantId;
  final String? ownerId;
  final String? uid;

  final DocumentReference<Map<String, dynamic>> tenantRef;
  final DocumentReference<Map<String, dynamic>> publicThankRef;

  final TextEditingController lineUrlCtrl;
  final TextEditingController reviewUrlCtrl;

  final bool uploadingPhoto;
  final bool uploadingVideo;
  final bool savingExtras;
  final Uint8List? thanksPhotoPreviewBytes;
  final String? thanksPhotoUrl;
  final String? thanksVideoUrl;

  final Future<void> Function() onSaveExtras;
  final Future<void> Function(String newPlan) onChangePlan;

  final ButtonStyle primaryBtnStyle;
  final ButtonStyle outlinedBtnStyle;

  final VoidCallback? onShowTipriInfo;

  const SubscriptionPlanCard({
    super.key,
    required this.currentPlan,
    required this.periodEndBool,
    required this.periodEnd,
    required this.trialStatus,
    required this.trialStart,
    required this.trialEnd,
    required this.tenantId,
    required this.ownerId,
    required this.uid,
    required this.tenantRef,
    required this.publicThankRef,
    required this.lineUrlCtrl,
    required this.reviewUrlCtrl,
    required this.uploadingPhoto,
    required this.uploadingVideo,
    required this.savingExtras,
    required this.thanksPhotoPreviewBytes,
    required this.thanksPhotoUrl,
    required this.thanksVideoUrl,
    required this.onSaveExtras,
    required this.onChangePlan,
    required this.primaryBtnStyle,
    required this.outlinedBtnStyle,
    this.onShowTipriInfo,
  });

  @override
  State<SubscriptionPlanCard> createState() => _SubscriptionPlanCardState();
}

class _SubscriptionPlanCardState extends State<SubscriptionPlanCard> {
  String? _pendingPlan;
  bool _changingPlan = false;
  bool _updatingPlan = false;

  @override
  void initState() {
    super.initState();
    _pendingPlan = widget.currentPlan;
  }

  void _enterChangeMode() {
    setState(() {
      _changingPlan = true;
      _pendingPlan = widget.currentPlan;
    });
  }

  void _cancelChangeMode() {
    setState(() {
      _changingPlan = false;
      _pendingPlan = null;
    });
  }

  void _onPlanChanged(String v) {
    if (!_changingPlan) return;
    setState(() => _pendingPlan = v);
  }

  Future<void> _submitChange() async {
    final newPlan = _pendingPlan;
    if (!_changingPlan || newPlan == null || newPlan == widget.currentPlan)
      return;

    setState(() => _updatingPlan = true);
    try {
      await widget.onChangePlan(newPlan);
    } finally {
      if (!mounted) return;
      setState(() {
        _updatingPlan = false;
        _changingPlan = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPlan = widget.currentPlan;
    final periodEnd = widget.periodEnd;
    final periodEndBool = widget.periodEndBool;
    final trialStatus = widget.trialStatus;
    final trialStart = widget.trialStart;
    final trialEnd = widget.trialEnd;

    final uid = widget.uid;
    final isOwner = widget.ownerId != null && widget.ownerId == uid;

    final effectivePickerValue = _changingPlan
        ? (_pendingPlan ?? currentPlan)
        : currentPlan;

    return CardShell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== 上部ヘッダ =====
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const PlanChip(label: '現在', dark: true),
                Text(
                  'プラン $currentPlan',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),

                // // 説明ボタン
                // FittedBox(
                //   fit: BoxFit.scaleDown,
                //   child: TextButton.icon(
                //     onPressed: widget.onShowTipriInfo,
                //     icon: const Icon(Icons.info_outline),
                //     label: const Text(
                //       'チップリについて',
                //       style: TextStyle(color: Color(0xFFFCC400)),
                //     ),
                //     style: TextButton.styleFrom(
                //       foregroundColor: Colors.black87,
                //     ),
                //   ),
                // ),
                if (periodEnd != null)
                  Text(
                    '${periodEndBool ? '終了予定' : '次回の請求'}: '
                    '${periodEnd.year}/${periodEnd.month.toString().padLeft(2, '0')}/${periodEnd.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.black54),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // ===== トライアル表示 =====
            if (trialStatus == "trialing" &&
                trialStart != null &&
                trialEnd != null)
              TrialProgressBar(
                trialStart: trialStart,
                trialEnd: trialEnd,
                totalDays: 30,
                onTap: () {},
              )
            else if (trialStatus == "none")
              const Text("トライアル期間は終了しました"),

            const SizedBox(height: 12),

            // ===== プラン選択 =====
            Stack(
              children: [
                AbsorbPointer(
                  absorbing: !_changingPlan,
                  child: Opacity(
                    opacity: _changingPlan ? 1.0 : 0.8,
                    child: PlanPicker(
                      selected: effectivePickerValue,
                      onChanged: _onPlanChanged,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ===== B プラン特典 =====
            if (currentPlan == "B") ...[
              buildBPerksSection(
                tenantRef: widget.tenantRef,
                thanksRef: widget.publicThankRef,
                lineUrlCtrl: widget.lineUrlCtrl,
                primaryBtnStyle: widget.primaryBtnStyle,
                tenantId: widget.tenantId,
              ),
            ],

            // ===== C プラン特典 =====
            if (currentPlan == 'C') ...[
              buildCPerksSection(
                tenantRef: widget.tenantRef,
                lineUrlCtrl: widget.lineUrlCtrl,
                reviewUrlCtrl: widget.reviewUrlCtrl,
                uploadingPhoto: widget.uploadingPhoto,
                uploadingVideo: widget.uploadingVideo,
                tenantId: widget.tenantId,
                savingExtras: widget.savingExtras,
                thanksPhotoPreviewBytes: widget.thanksPhotoPreviewBytes,
                thanksPhotoUrlLocal: widget.thanksPhotoUrl,
                thanksVideoUrlLocal: widget.thanksVideoUrl,
                onSaveExtras: widget.onSaveExtras,
                onPreviewVideo: showVideoPreview,
                primaryBtnStyle: widget.primaryBtnStyle,
                thanksRef: widget.publicThankRef,
              ),
            ],

            const SizedBox(height: 16),

            // ===== 下部ボタン（モードによって分岐） =====
            if (!_changingPlan) ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: widget.primaryBtnStyle,
                      onPressed: !isOwner
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'オーナーのみ変更可能です',
                                    style: TextStyle(fontFamily: 'LINEseed'),
                                  ),
                                  backgroundColor: Color(0xFFFCC400),
                                ),
                              );
                            }
                          : _updatingPlan
                          ? null
                          : _enterChangeMode,
                      icon: const Icon(Icons.tune),
                      label: currentPlan.isEmpty
                          ? const Text('サブスクのプランを追加')
                          : periodEndBool
                          ? const Text('サブスクのプランを更新')
                          : const Text('サブスクのプランを変更'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: widget.primaryBtnStyle,
                      onPressed:
                          (_updatingPlan ||
                              _pendingPlan == null ||
                              _pendingPlan == currentPlan)
                          ? null
                          : _submitChange,
                      icon: _updatingPlan
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        (_pendingPlan == currentPlan) ? '変更なし' : 'このプランに変更',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: widget.outlinedBtnStyle,
                    onPressed: _updatingPlan ? null : _cancelChangeMode,
                    icon: const Icon(Icons.close),
                    label: const Text('やめる'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
