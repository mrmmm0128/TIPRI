import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cプラン特典セクション（c_perks だけ）
/// - モバイル/タブレット: BottomSheetでリンク編集
/// - PC: 従来どおりインライン編集
Widget buildCPerksSection({
  required DocumentReference<Map<String, dynamic>> tenantRef,
  required TextEditingController lineUrlCtrl,
  required TextEditingController reviewUrlCtrl,
  required bool uploadingPhoto,
  required bool uploadingVideo,
  required bool savingExtras,
  required Uint8List? thanksPhotoPreviewBytes,
  required String? thanksPhotoUrlLocal,
  required String? thanksVideoUrlLocal,
  required VoidCallback onSaveExtras, // () => _saveExtras(tenantRef)
  required VoidCallback onPickPhoto, // () => _pickAndUploadPhoto(...)
  required VoidCallback onDeletePhoto, // () => _deleteThanksPhoto(...)
  required DocumentReference thanksRef,
  required void Function(BuildContext, String)
  onPreviewVideo, // showVideoPreview
  required ButtonStyle primaryBtnStyle,
}) {
  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: tenantRef.snapshots(),
    builder: (context, snap) {
      final data = snap.data?.data() ?? const <String, dynamic>{};
      final perks = (data['c_perks'] as Map<String, dynamic>?) ?? const {};

      final serverVideoUrl = (perks['thanksVideoUrl'] as String?)?.trim();
      final serverLineUrl = (perks['lineUrl'] as String?)?.trim();
      final serverReview = (perks['reviewUrl'] as String?)?.trim();

      // 初期流し込み（手入力を上書きしない）
      if (lineUrlCtrl.text.isEmpty && (serverLineUrl?.isNotEmpty ?? false)) {
        lineUrlCtrl.text = serverLineUrl!;
      }
      if (reviewUrlCtrl.text.isEmpty && (serverReview?.isNotEmpty ?? false)) {
        reviewUrlCtrl.text = serverReview!;
      }

      final displayVideoUrl = (thanksVideoUrlLocal?.isNotEmpty ?? false)
          ? thanksVideoUrlLocal
          : (serverVideoUrl?.isNotEmpty ?? false)
          ? serverVideoUrl
          : null;

      final isCompact = MediaQuery.of(context).size.width < 900; // スマホ/タブレット閾値

      Future<void> _saveLineUrl(BuildContext ctx) async {
        final v = lineUrlCtrl.text.trim();
        try {
          if (v.isEmpty) {
            try {
              await tenantRef.update({'c_perks.lineUrl': FieldValue.delete()});
            } catch (_) {}
            try {
              await thanksRef.update({'c_perks.lineUrl': FieldValue.delete()});
            } catch (_) {}
          } else {
            await tenantRef.set({
              'c_perks.lineUrl': v,
            }, SetOptions(merge: true));
            await thanksRef.set({
              'c_perks.lineUrl': v,
            }, SetOptions(merge: true));
          }
          if (ctx.mounted) {
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(const SnackBar(content: Text('LINEリンクを保存しました')));
          }
        } catch (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
          }
        }
      }

      Future<void> _saveReviewUrl(BuildContext ctx) async {
        final v = reviewUrlCtrl.text.trim();
        try {
          if (v.isEmpty) {
            try {
              await tenantRef.update({
                'c_perks.reviewUrl': FieldValue.delete(),
              });
            } catch (_) {}
            try {
              await thanksRef.update({
                'c_perks.reviewUrl': FieldValue.delete(),
              });
            } catch (_) {}
          } else {
            await tenantRef.set({
              'c_perks.reviewUrl': v,
            }, SetOptions(merge: true));
            await thanksRef.set({
              'c_perks.reviewUrl': v,
            }, SetOptions(merge: true));
          }
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Googleレビューリンクを保存しました')),
            );
          }
        } catch (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
          }
        }
      }

      Future<void> _openLinksSheet() async {
        // 既存コントローラを使い回し（フォーカスはシート内）
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) {
            return AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (ctx, localSetState) {
                    bool savingLine = false;
                    bool savingReview = false;

                    Future<void> saveLine() async {
                      if (savingLine) return;
                      localSetState(() => savingLine = true);
                      try {
                        await _saveLineUrl(ctx);
                      } finally {
                        localSetState(() => savingLine = false);
                      }
                    }

                    Future<void> saveReview() async {
                      if (savingReview) return;
                      localSetState(() => savingReview = true);
                      try {
                        await _saveReviewUrl(ctx);
                      } finally {
                        localSetState(() => savingReview = false);
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ハンドル
                          Container(
                            height: 4,
                            width: 40,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                'Cプランの特典（表示用リンク）',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: '閉じる',
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 現在値の簡易表示
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '現在: '
                                  '${(serverLineUrl?.isNotEmpty ?? false) ? serverLineUrl : "LINE 未設定"} / '
                                  '${(serverReview?.isNotEmpty ?? false) ? serverReview : "レビュー 未設定"}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // LINE
                          TextField(
                            controller: lineUrlCtrl,
                            decoration: const InputDecoration(
                              labelText: '公式LINEリンク（任意）',
                              hintText: 'https://lin.ee/xxxxx',
                              prefixIcon: Icon(Icons.link),
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'.*')),
                            ],
                            onSubmitted: (_) => saveLine(),
                            autofocus: true,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: savingLine ? null : saveLine,
                              icon: savingLine
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('LINEリンクを保存'),
                              style: primaryBtnStyle,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // レビュー
                          TextField(
                            controller: reviewUrlCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Googleレビューリンク（任意）',
                              hintText: 'https://g.page/r/xxxxx/review',
                              prefixIcon: Icon(Icons.reviews),
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'.*')),
                            ],
                            onSubmitted: (_) => saveReview(),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: savingReview ? null : saveReview,
                              icon: savingReview
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('レビューリンクを保存'),
                              style: primaryBtnStyle,
                            ),
                          ),

                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'Cプランの特典（表示用リンク）',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          if (isCompact) ...[
            // ★ モバイル/タブレット：現在値＋設定を開く
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'LINE: ${serverLineUrl?.isNotEmpty == true ? serverLineUrl : "未設定"} / '
                    'レビュー: ${serverReview?.isNotEmpty == true ? serverReview : "未設定"}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _openLinksSheet,
                icon: const Icon(Icons.tune),
                label: const Text('設定を開く'),
                style: primaryBtnStyle,
              ),
            ),
          ] else ...[
            // ★ PC：従来のインライン（あなたの元の行を残す）
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: lineUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: '公式LINEリンク（任意）',
                      hintText: 'https://lin.ee/xxxxx',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async => _saveLineUrl(context),
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                  style: primaryBtnStyle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: reviewUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Googleレビューリンク（任意）',
                      hintText: 'https://g.page/r/xxxxx/review',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async => _saveReviewUrl(context),
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                  style: primaryBtnStyle,
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'Cプランの特典（感謝の写真・動画）',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),

          // ===== 動画（表示のみ。登録は別画面というあなたの方針を尊重） =====
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x11000000)),
                ),
                child: uploadingVideo
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ((displayVideoUrl ?? '').isNotEmpty
                          ? const Icon(Icons.play_circle_fill, size: 36)
                          : const Icon(Icons.movie, size: 32)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('チップを贈ってくれた方にお礼の動画を提供しましょう。\nスタッフ詳細画面から登録してください。'),
              ),
            ],
          ),
        ],
      );
    },
  );
}
