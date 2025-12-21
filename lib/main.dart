import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:yourpay/appadmin/admin_dashboard_screen.dart';
import 'package:yourpay/appadmin/agent/agent_login.dart';
import 'package:yourpay/tenant/bootGate.dart';
import 'package:yourpay/tenant/staff_qr/public_staff_qr_list_page.dart';
import 'package:yourpay/tenant/staff_qr/qr_poster_build_page.dart';
import 'package:yourpay/tenant/store_admin_add/accept_invite_screen.dart';
import 'package:yourpay/tenant/widget/store_setting/account_detail_page.dart';
import 'package:yourpay/tenant/widget/store_setting/tenant_detail_screen.dart';
import 'tenant/login_screens.dart';
import 'tenant/store_detail/store_detail_screen.dart';

FirebaseOptions web = FirebaseOptions(
  apiKey: 'AIzaSyAIfxdoGM5TWDVRjtfazvWZ9LnLlMnOuZ4',
  appId: '1:1005883564338:web:ad2b27b5bbd8c0993d772b',
  messagingSenderId: '1005883564338',
  projectId: 'yourpay-c5aaf',
  authDomain: 'yourpay-c5aaf.firebaseapp.com',
  storageBucket: 'yourpay-c5aaf.firebasestorage.app',
);

// ===== 白黒固定テーマ =====
final ThemeData _monochromeLightTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'LINEseed',
  colorScheme: const ColorScheme.light().copyWith(
    // 主要色は黒、背景/サーフェスは白
    primary: Colors.black,
    onPrimary: Colors.white,
    secondary: Colors.black,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: Colors.black,
    background: Colors.white,
    onBackground: Colors.black,
    // SnackBar の既定色に効く M3 の inverseSurface も黒で固定
    inverseSurface: Colors.black,
    onInverseSurface: Colors.white,
  ),
  scaffoldBackgroundColor: Colors.white,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Colors.black,
    contentTextStyle: TextStyle(color: Colors.white),
    behavior: SnackBarBehavior.floating,
    elevation: 2,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: const ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.black),
      foregroundColor: WidgetStatePropertyAll(Colors.white),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: const ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(Colors.black),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: const ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(Colors.black),
      side: WidgetStatePropertyAll(BorderSide(color: Colors.black)),
    ),
  ),
);
// =======================

Future<void> main() async {
  setUrlStrategy(const HashUrlStrategy());
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: web);

  // 画面が真っ白になっても原因が見えるように
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      return const Material(
        color: Colors.white,
        child: Center(
          child: Text('予期せぬエラーが発生しました', style: TextStyle(color: Colors.red)),
        ),
      );
    }
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          details.exceptionAsString(),
          style: const TextStyle(color: Colors.red),
        ),
      ),
    );
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    final uri = Uri.parse(name);

    // ① admin だけ特別扱い
    if (uri.path == '/admin') {
      final user = FirebaseAuth.instance.currentUser;

      const allowedUids = {
        'KjbZAA5vvueofEuk7mREclRux0a2',
        'sy4g1tML5rO8pwc30htUfIF1meF3',
      };

      // 未ログイン or 許可UID以外 → ルート相当へ返す
      if (user == null || !allowedUids.contains(user.uid)) {
        return MaterialPageRoute(
          // 未ログインなら BootGate、ログイン済みなら Root に返すなど
          builder: (_) => user == null ? const BootGate() : const Root(),
          // URLも「/」として扱いたければ name を上書きしておく
          settings: RouteSettings(
            name: '/', // URL的にはルート扱いにしたい場合
            arguments: settings.arguments, // 必要なら元の arguments を引き継ぐ
          ),
        );
      }

      // 許可された UID のみ admin 画面へ
      return MaterialPageRoute(
        builder: (_) => const AdminDashboardHome(),
        settings: settings,
      );
    }

    // それ以外の静的ルート
    final staticRoutes = <String, WidgetBuilder>{
      '/': (_) => const Root(),
      '/login': (_) => const BootGate(),
      '/store': (_) => const StoreDetailScreen(),
      '/admin': (_) => const AdminDashboardHome(),
      '/tenant': (_) => const TenantDetailScreen(),
      '/account': (_) => const AccountDetailScreen(),
      '/admin-invite': (_) => const AcceptInviteScreen(),
      '/qr-all': (_) => const PublicStaffQrListPage(),
      '/qr-all/qr-builder': (_) => const QrPosterBuilderPage(),
      '/chechout-end': (_) => const LoginScreen(),
      '/agent-login': (_) => const AgentLoginPage(),
    };

    final builder = staticRoutes[uri.path];
    return MaterialPageRoute(
      builder: builder ?? (_) => const LoginScreen(),
      settings: settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      theme: _monochromeLightTheme,
      themeMode: ThemeMode.light,

      onGenerateRoute: _onGenerateRoute,
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 現在のパス（HashStrategy対応）
        String currentPath() {
          final uri = Uri.base;
          if (uri.fragment.isNotEmpty) {
            final frag = uri.fragment;
            final q = frag.indexOf('?');
            return q >= 0 ? frag.substring(0, q) : frag;
          }
          return uri.path;
        }

        final path = currentPath();
        const publicPaths = {'/qr-all', '/qr-all/qr-builder', '/staff', '/p'};

        // ❶ パブリックパスはログインに関係なくパブリック画面をそのまま表示
        if (publicPaths.contains(path)) {
          switch (path) {
            case '/qr-all':
              return const PublicStaffQrListPage();
            case '/qr-all/qr-builder':
              return const QrPosterBuilderPage();
          }
        }

        // ❷ それ以外：未ログインならゲート
        if (snap.data == null) {
          return const BootGate();
        }

        // ❸ ログイン済みの既定画面（必要なら StoreOrAdminSwitcher など）
        return const StoreDetailScreen();
      },
    );
  }
}
