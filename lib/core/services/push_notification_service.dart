import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    );
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
  }
}
