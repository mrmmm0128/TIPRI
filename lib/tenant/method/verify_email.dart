import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<String?> signupAndSendVerifyIsolated({
  required String email,
  required String password,
  String? displayName,
  ActionCodeSettings? acs,
}) async {
  // 既に 'shadow' があれば一旦破棄（ホットリロード対策）
  try {
    await Firebase.app('shadow').delete();
  } catch (_) {}

  final shadow = await Firebase.initializeApp(
    name: 'shadow',
    options: Firebase.app().options,
  );
  final auth = FirebaseAuth.instanceFor(app: shadow);

  String? createdUid;

  try {
    // Webのみ：セッションを残さない
    try {
      await auth.setPersistence(Persistence.NONE);
    } catch (_) {}

    // 新規作成（このセカンダリApp内だけでログイン状態になる）
    final cred = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    createdUid = cred.user?.uid;

    if ((displayName ?? '').isNotEmpty) {
      await cred.user?.updateDisplayName(displayName);
    }

    await cred.user?.sendEmailVerification(acs);
  } finally {
    try {
      await auth.signOut();
    } catch (_) {}
    await shadow.delete();
  }

  return createdUid;
}

/// 既存ユーザー向け：パスワードで“影響なしログイン”して検証メールだけ再送
Future<void> resendVerifyIsolated({
  required String email,
  required String password,
  ActionCodeSettings? acs,
}) async {
  try {
    await Firebase.app('shadow').delete();
  } catch (_) {}

  final shadow = await Firebase.initializeApp(
    name: 'shadow',
    options: Firebase.app().options,
  );
  final auth = FirebaseAuth.instanceFor(app: shadow);

  try {
    try {
      await auth.setPersistence(Persistence.NONE);
    } catch (_) {}

    final cred = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await cred.user?.sendEmailVerification(acs);
  } finally {
    try {
      await auth.signOut();
    } catch (_) {}
    await shadow.delete();
  }
}
