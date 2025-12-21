// lib/tenant/widget/store_staff/upload_video.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
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
  static const brandYellow = Color(0xFFFCC400);

  Uint8List? _pickedBytes;
  String? _pickedName;
  bool _uploading = false;
  bool _deleting = false;

  String? _currentUrl;

  DocumentReference<Map<String, dynamic>>? get _empRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection(uid)
        .doc(widget.tenantId)
        .collection('employees')
        .doc(widget.staffId);
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentVideo();
  }

  Future<void> _loadCurrentVideo() async {
    final ref = _empRef;
    if (ref == null) return;

    final snap = await ref.get();
    final data = snap.data();
    if (!mounted || data == null) return;

    setState(() {
      _currentUrl = (data['thanksVideoUrl'] ?? '') as String;
    });
  }

  Future<void> _pickVideo() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    final f = res.files.single;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.readStream != null) {
      final chunks = <int>[];
      await for (final c in f.readStream!) {
        chunks.addAll(c);
      }
      bytes = Uint8List.fromList(chunks);
    }
    if (bytes == null) return;

    setState(() {
      _pickedBytes = bytes;
      _pickedName = f.name;
    });
  }

  String _detectContentType(String? filename) {
    final ext = (filename ?? '').split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  Future<void> _uploadVideo() async {
    if (_pickedBytes == null || _pickedName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: brandYellow,
          content: Text(
            'アップロードする動画を選択してください',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
        ),
      );
      return;
    }

    final ref = _empRef;
    if (ref == null) return;

    setState(() => _uploading = true);
    try {
      final contentType = _detectContentType(_pickedName);
      final ext = contentType.split('/').last;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final storageRef = FirebaseStorage.instance.ref().child(
        '$uid/${widget.tenantId}/employees/${widget.staffId}/thanks_video.$ext',
      );

      await storageRef.putData(
        _pickedBytes!,
        SettableMetadata(contentType: contentType),
      );
      final url = await storageRef.getDownloadURL();

      await ref.set({
        'thanksVideoUrl': url,
        'thanksVideoUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _currentUrl = url;
        _pickedBytes = null;
        _pickedName = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: brandYellow,
          content: Text(
            'サンクス動画を更新しました',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: brandYellow,
          content: Text(
            '動画のアップロードに失敗しました: $e',
            style: const TextStyle(fontFamily: 'LINEseed'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteVideo() async {
    if (_currentUrl == null || _currentUrl!.isEmpty) return;
    if (_deleting) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('サンクス動画を削除しますか？'),
        content: Text(
          '「${widget.staffName}」のサンクス動画を削除します。\nこの操作は取り消せません。',
          style: const TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      // ストレージ削除（URLから参照を逆引き）
      try {
        final ref = FirebaseStorage.instance.refFromURL(_currentUrl!);
        await ref.delete();
      } catch (_) {
        // 失敗しても続行（URL無効など）
      }

      final empRef = _empRef;
      if (empRef != null) {
        await empRef.set({
          'thanksVideoUrl': FieldValue.delete(),
          'thanksVideoUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() {
        _currentUrl = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: brandYellow,
          content: Text(
            'サンクス動画を削除しました',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: brandYellow,
          content: Text(
            '削除に失敗しました: $e',
            style: const TextStyle(fontFamily: 'LINEseed'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // ---- UI helpers ----

  ButtonStyle get _filledYellowButton => FilledButton.styleFrom(
    backgroundColor: brandYellow,
    foregroundColor: Colors.black87,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Colors.black, width: 3),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  ButtonStyle get _outlineYellowButton => OutlinedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black87,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Colors.black, width: 2),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  );

  Widget _whiteCard(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: 3,
          color: Colors.black,
        ), // ← ここを BoxBorder にする
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _whiteCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.movie_filter_outlined, color: Colors.black54),
              SizedBox(width: 8),
              Text(
                '感謝動画',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.staffName.isEmpty ? "このスタッフ" : widget.staffName}に紐づく感謝動画を登録できます。',
            style: const TextStyle(color: Colors.black87, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            '推奨：30秒以内、縦向き動画（mp4 / mov / webm など）',
            style: TextStyle(color: Colors.black54, fontSize: 11),
          ),
          const SizedBox(height: 16),

          // 現在登録されている動画
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Row(
              children: [
                Icon(
                  _currentUrl == null || _currentUrl!.isEmpty
                      ? Icons.videocam_off_outlined
                      : Icons.play_circle_outline,
                  color: Colors.black54,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentUrl == null || _currentUrl!.isEmpty
                        ? 'まだ動画が登録されていません'
                        : '動画が登録されています',
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                ),
                if (_currentUrl != null && _currentUrl!.isNotEmpty) ...[
                  OutlinedButton(
                    style: _outlineYellowButton,
                    onPressed: () => showVideoPreview(context, _currentUrl!),
                    child: const Text('プレビュー', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _deleting ? null : _deleteVideo,
                    child: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '削除',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 選択済みファイルの表示
          if (_pickedName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.upload_file,
                    size: 18,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pickedName!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _uploading
                        ? null
                        : () {
                            setState(() {
                              _pickedBytes = null;
                              _pickedName = null;
                            });
                          },
                    child: const Text('クリア', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // ボタン群
          Row(
            children: [
              OutlinedButton.icon(
                style: _outlineYellowButton,
                onPressed: _uploading ? null : _pickVideo,
                icon: const Icon(Icons.video_call_outlined, size: 18),
                label: const Text('動画を選択', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: _filledYellowButton,
                  onPressed: (_pickedBytes == null || _uploading)
                      ? null
                      : _uploadVideo,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.save_alt_outlined, size: 18),
                  label: Text(
                    _uploading ? 'アップロード中…' : 'アップロードして反映',
                    style: const TextStyle(
                      fontFamily: 'LINEseed',
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ====== 動画プレビュー（デザインも少し TIPRI 風に調整） ======

void showVideoPreview(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _VideoPreviewDialog(url: url),
  );
}

class _VideoPreviewDialog extends StatefulWidget {
  final String url;
  const _VideoPreviewDialog({required this.url});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late final VideoPlayerController _controller;
  bool _inited = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setLooping(true);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _inited = true);
          _controller.play();
        })
        .catchError((e) {
          if (!mounted) return;
          setState(() => _err = e.toString());
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (_inited && _controller.value.isInitialized)
        ? (_controller.value.aspectRatio == 0
              ? 16 / 9
              : _controller.value.aspectRatio)
        : 16 / 9;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.black, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Container(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: ratio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_err != null) ...[
                  const Icon(
                    Icons.broken_image,
                    color: Colors.white70,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Positioned(
                    bottom: 12,
                    child: TextButton.icon(
                      onPressed: () => launchUrlString(
                        widget.url,
                        mode: LaunchMode.externalApplication,
                        webOnlyWindowName: '_self',
                      ),
                      icon: const Icon(Icons.open_in_new, color: Colors.white),
                      label: const Text(
                        'ブラウザで開く',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ] else if (!_inited) ...[
                  const CircularProgressIndicator(color: Colors.white),
                ] else ...[
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoPlayer(_controller),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            padding: const EdgeInsets.only(bottom: 4),
                            colors: VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                        ),
                        if (!_controller.value.isPlaying)
                          const Icon(
                            Icons.play_circle_filled,
                            color: Colors.white70,
                            size: 72,
                          ),
                      ],
                    ),
                  ),
                ],
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '閉じる',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
