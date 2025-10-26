// lib/tenant/staff/widgets/staff_thanks_video_manager.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class StaffThanksVideoManager extends StatefulWidget {
  final String tenantId;
  final String staffId;
  final String staffName;

  const StaffThanksVideoManager({
    super.key,
    required this.tenantId,
    required this.staffId,
    required this.staffName,
  });

  @override
  State<StaffThanksVideoManager> createState() =>
      _StaffThanksVideoManagerState();
}

class _StaffThanksVideoManagerState extends State<StaffThanksVideoManager> {
  // ===== Breakpoints =====
  static const double _bpCompact = 520; // ~スマホ縦
  static const double _bpMedium = 900; // タブレット/小さめPC

  CollectionReference<Map<String, dynamic>> get _videosCol => FirebaseFirestore
      .instance
      .collection('publicThanks')
      .doc(widget.tenantId)
      .collection('staff')
      .doc(widget.staffName)
      .collection('videos');

  Future<void> _pickAndUpload() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'mov', 'm4v', 'webm'],
        allowMultiple: false,
        withData: true, // Web/デスクトップ対応
      );
      if (picked == null || picked.files.isEmpty) return;

      final f = picked.files.single;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.readStream != null) {
        final buf = <int>[];
        await for (final c in f.readStream!) {
          buf.addAll(c);
        }
        bytes = Uint8List.fromList(buf);
      }
      if (bytes == null) {
        _toast('動画の読み込みに失敗しました');
        return;
      }

      // Firestore ドキュメントを確保
      final docRef = _videosCol.doc();

      String contentType = _detectVideoContentType(f.name);
      final ext = contentType.split('/').last;

      final storagePath =
          'publicThanks/${widget.tenantId}/staff/${widget.staffName}/videos/${docRef.id}.$ext';
      final storageRef = FirebaseStorage.instance.ref(storagePath);

      // 進捗ダイアログ
      final progress = ValueNotifier<double>(0);
      _showProgressDialog(progress);

      final metadata = SettableMetadata(contentType: contentType);
      final task = storageRef.putData(bytes, metadata);
      task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) {
          progress.value = s.bytesTransferred / s.totalBytes;
        }
      });

      await task;
      final url = await storageRef.getDownloadURL();

      await docRef.set({
        'tenantId': widget.tenantId,
        'staffId': widget.staffId,
        'name': f.name,
        'url': url,
        'storagePath': storagePath,
        'contentType': contentType,
        'size': bytes.length,
        'published': true,
        // 並び順は昇順、作成時刻ミリ秒でソート可能
        'order': DateTime.now().millisecondsSinceEpoch,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // 任意メタ
        'title': f.name,
        'description': '',
        'durationMs': null,
        'thumbUrl': null,
      });

      if (mounted) Navigator.of(context).maybePop(); // 進捗ダイアログを閉じる
      _toast('アップロードしました');
    } catch (e) {
      Navigator.of(context).maybePop();
      _toast('アップロード失敗: $e');
    }
  }

  String _detectVideoContentType(String? name) {
    final ext = (name ?? '').split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  void _showProgressDialog(ValueNotifier<double> progress) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, __) => AlertDialog(
          title: const Text('アップロード中'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v == 0 ? null : v),
              const SizedBox(height: 8),
              Text(v == 0 ? '準備中…' : '${(v * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteVideo(Map<String, dynamic> data, String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('削除しますか？'),
        content: Text(data['name'] ?? 'この動画を削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final path = (data['storagePath'] as String?) ?? '';
      if (path.isNotEmpty) {
        await FirebaseStorage.instance.ref(path).delete();
      }
      await _videosCol.doc(docId).delete();
      _toast('削除しました');
    } catch (e) {
      _toast('削除に失敗: $e');
    }
  }

  Future<void> _togglePublish(String docId, bool value) async {
    try {
      await _videosCol.doc(docId).set({
        'published': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _toast('更新に失敗: $e');
    }
  }

  Future<void> _rename(String docId, String currentTitle) async {
    final ctrl = TextEditingController(text: currentTitle);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('タイトルを編集'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'タイトル'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _videosCol.doc(docId).set({
        'title': ctrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _toast('保存に失敗: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontFamily: 'LINEseed')),
        backgroundColor: Color(0xFFFCC400),
      ),
    );
  }

  Future<void> _preview(String url) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _VideoPreviewDialog(url: url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle = '${widget.staffName} の 感謝動画';
    final outlineButton = OutlinedButton.styleFrom(
      backgroundColor: Color(0xFFFCC400),
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: Colors.black, width: 3),

      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Center(
      // ワイド画面で読みやすい最大幅を設定
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final isCompact = w < _bpCompact;
                final isMedium = w >= _bpCompact && w < _bpMedium;

                final uploadBtn = OutlinedButton.icon(
                  style: outlineButton,
                  onPressed: _pickAndUpload,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('動画をアップロード'),
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ===== Header (responsive) =====
                    if (isCompact) ...[
                      Text(
                        pageTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: uploadBtn),
                    ] else ...[
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 8,
                        children: [
                          Text(
                            pageTitle,
                            style: TextStyle(
                              fontSize: isMedium ? 18 : 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          uploadBtn,
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),

                    // ===== List (responsive items) =====
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _videosCol
                          .orderBy('order', descending: false)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return ListTile(
                            leading: const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                            ),
                            title: const Text('読み込みに失敗しました'),
                            subtitle: Text('${snap.error}'),
                          );
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final docs = snap.data!.docs;
                        if (docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'まだ動画はありません。右上の「動画をアップロード」から追加してください。',
                              style: TextStyle(color: Colors.black54),
                            ),
                          );
                        }

                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final d = docs[i];
                            final m = d.data();
                            final title =
                                (m['title'] as String?) ??
                                (m['name'] as String? ?? '動画');
                            final published =
                                (m['published'] as bool?) ?? false;
                            final url = (m['url'] as String?) ?? '';
                            final createdAt = (m['createdAt'] as Timestamp?);
                            final when = createdAt == null
                                ? ''
                                : _fmt(createdAt.toDate());

                            // trailing は Wrap で折り返し → 狭い時も崩れない
                            final trailingControls = Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('公開'),
                                    Switch(
                                      value: published,
                                      onChanged: (v) => _togglePublish(d.id, v),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  tooltip: '再生',
                                  onPressed: url.isEmpty
                                      ? null
                                      : () => _preview(url),
                                  icon: const Icon(Icons.play_circle_fill),
                                ),
                                IconButton(
                                  tooltip: '名前変更',
                                  onPressed: () => _rename(d.id, title),
                                  icon: const Icon(Icons.edit),
                                ),
                                IconButton(
                                  tooltip: '削除',
                                  onPressed: () => _deleteVideo(m, d.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            );

                            // コンパクト時は情報を2行に整理
                            final isThreeLine = w < _bpCompact;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              leading: const CircleAvatar(
                                child: Icon(Icons.movie),
                              ),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: isThreeLine
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(when),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              published
                                                  ? Icons.visibility
                                                  : Icons.visibility_off,
                                              size: 16,
                                              color: published
                                                  ? Colors.green
                                                  : Colors.grey,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              published ? '公開中' : '非公開',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: published
                                                    ? Colors.green
                                                    : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  : Text(when),
                              trailing: ConstrainedBox(
                                constraints: BoxConstraints(
                                  // ボタン群がはみ出さないように最大幅を画面幅の 55% に制限
                                  maxWidth: w * 0.55,
                                ),
                                child: trailingControls,
                              ),
                              onTap: url.isEmpty ? null : () => _preview(url),
                            );
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _VideoPreviewDialog extends StatefulWidget {
  final String url;
  const _VideoPreviewDialog({required this.url});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
        _controller?.play();
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 画面サイズに応じてダイアログを 90% までに制限、縦横どちらでも見やすく
    final size = MediaQuery.of(context).size;
    final maxW = size.width * 0.9;
    final maxH = size.height * 0.9;

    final ar = (_controller?.value.aspectRatio ?? 16 / 9);
    // 希望幅高さをアスペクト比を保って決定
    double w = maxW;
    double h = w / ar;
    if (h > maxH) {
      h = maxH;
      w = h * ar;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w, maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: ar,
                    child:
                        _controller != null && _controller!.value.isInitialized
                        ? Stack(
                            children: [
                              VideoPlayer(_controller!),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: VideoProgressIndicator(
                                  _controller!,
                                  allowScrubbing: true,
                                ),
                              ),
                            ],
                          )
                        : const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
