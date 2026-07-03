import 'package:supabase_flutter/supabase_flutter.dart';

/// Sincroniza o vínculo bidirecional entre uma conta de usuário e um registro
/// de motorista (`user_profiles.driver_id` <-> `drivers.user_id`).
///
/// A atualização em `drivers` é best-effort (não interrompe o fluxo se falhar,
/// já que `user_profiles.driver_id` é a referência principal usada pelo app).
Future<void> linkUserToDriver(
  SupabaseClient supabase, {
  required String userId,
  required String driverId,
}) async {
  await supabase.from('user_profiles').update({'driver_id': driverId}).eq('user_id', userId);
  try {
    await supabase.from('drivers').update({'user_id': userId}).eq('id', driverId);
  } catch (_) {}
}
