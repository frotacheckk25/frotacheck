import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../home/notificacoes/notificacoes_page.dart' show abrirTelaDaNotificacao;
import '../navigation/root_navigator_key.dart';

/// Notificações push (FCM) só existem no app Android nativo — a versão Web
/// ainda não tem um projeto Firebase Web configurado (VAPID key / service
/// worker), então nem tentamos inicializar lá.
bool get pushNotificationsSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Handler de mensagens recebidas com o app em segundo plano/fechado.
/// Precisa ser uma função top-level (fora de classe) — exigência do
/// firebase_messaging para rodar num isolate separado.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  // Nada a fazer aqui: o próprio FCM já exibe a notificação do sistema
  // quando o payload tem "notification" e o app está em segundo plano.
  debugPrint('Push em segundo plano: ${message.messageId}');
}

/// Registra o token de notificação do dispositivo no Supabase e trata
/// mensagens recebidas com o app aberto (primeiro plano).
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  bool _initialized = false;

  static const _androidChannel = AndroidNotificationChannel(
    'frotacheck_default',
    'Avisos do FrotaCheck',
    description: 'Abastecimentos, ocorrências, multas e manutenções registradas pela equipe.',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);

      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        // Toque numa notificação exibida enquanto o app já estava aberto
        // (via flutter_local_notifications, ver _showForegroundNotification).
        onDidReceiveNotificationResponse: _onLocalNotificationTap,
      );

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Permissão de notificação negada pelo usuário.');
        return;
      }

      await _registerToken();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen(_saveToken);

      _foregroundSub = FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // Toque na notificação nativa com o app em segundo plano (não fechado).
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(_abrirTelaDoRemoteMessage);

      // App estava fechado e foi aberto tocando na notificação (cold start).
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) _abrirTelaDoRemoteMessage(initialMessage);
    } catch (e) {
      debugPrint('Erro ao inicializar notificações push: $e');
    }
  }

  Future<void> _registerToken() async {
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('device_tokens').upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': defaultTargetPlatform.name,
      }, onConflict: 'fcm_token');
    } catch (e) {
      debugPrint('Erro ao salvar token de notificação: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // Repassa o tipo (nome da tabela de origem) para o toque poder abrir a
      // tela certa — ver _onLocalNotificationTap.
      payload: message.data['table']?.toString(),
    );
  }

  // Toque na notificação exibida via flutter_local_notifications (app já
  // estava em primeiro plano quando ela chegou).
  void _onLocalNotificationTap(NotificationResponse response) {
    final tipo = response.payload;
    if (tipo == null || tipo.isEmpty) return;
    _abrirTela(tipo);
  }

  // Toque na notificação nativa exibida pelo próprio FCM (app em segundo
  // plano ou recém-aberto a partir dela — cold start).
  void _abrirTelaDoRemoteMessage(RemoteMessage message) {
    final tipo = message.data['table']?.toString();
    if (tipo == null || tipo.isEmpty) return;
    _abrirTela(tipo);
  }

  void _abrirTela(String tipo) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    abrirTelaDaNotificacao(ctx, tipo);
  }

  /// Chame ao fazer logout — evita que o próximo usuário do mesmo aparelho
  /// continue recebendo notificações da conta anterior.
  Future<void> unregister() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await Supabase.instance.client
            .from('device_tokens')
            .delete()
            .eq('fcm_token', token);
      }
    } catch (e) {
      debugPrint('Erro ao remover token de notificação: $e');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
  }
}
