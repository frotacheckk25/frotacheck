// Edge Function: admin-redefinir-senha
//
// Quem administra define uma nova senha para alguém da própria empresa — usado
// quando a pessoa esquece a senha e o e-mail dela é um login interno (ex.:
// paulo.motorista@empresa.com), que não recebe o link de "Esqueceu a senha".
// Também marca o e-mail como confirmado, já que a confirmação por e-mail
// não é usada.
//
// Regras: MASTER → qualquer usuário (menos outro MASTER); ADMIN_EMPRESA →
// gestores e motoristas da sua empresa; GESTOR → motoristas da sua empresa.
import { errorResponse, getCaller, getServiceClient, jsonResponse } from "../_shared/fiscal.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function comCors(r: Response): Response {
  for (const [k, v] of Object.entries(CORS)) r.headers.set(k, v);
  return r;
}

const PODE_REDEFINIR: Record<string, string[]> = {
  MASTER: ["ADMIN_EMPRESA", "GESTOR", "MOTORISTA"],
  ADMIN_EMPRESA: ["GESTOR", "MOTORISTA"],
  GESTOR: ["MOTORISTA"],
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    if (req.method !== "POST") return comCors(errorResponse("Método não suportado", 405));

    const caller = await getCaller(req);
    const { user_id: alvoId, nova_senha: novaSenha } = await req.json();

    if (typeof alvoId !== "string" || !alvoId) return comCors(errorResponse("user_id é obrigatório"));
    if (typeof novaSenha !== "string" || novaSenha.length < 6 || novaSenha.length > 72) {
      return comCors(errorResponse("A senha precisa ter entre 6 e 72 caracteres"));
    }
    if (alvoId === caller.userId) {
      return comCors(errorResponse("Para trocar a sua própria senha use Perfil → Alterar senha", 403));
    }

    const service = getServiceClient();
    const { data: alvo, error } = await service
      .from("user_profiles")
      .select("empresa_id, role")
      .eq("user_id", alvoId)
      .maybeSingle();
    if (error) throw new Error(`Erro ao buscar usuário: ${error.message}`);
    if (!alvo) return comCors(errorResponse("Usuário não encontrado", 404));

    const permitidos = PODE_REDEFINIR[caller.role] ?? [];
    const mesmaEmpresa = caller.role === "MASTER" || (caller.empresaId && alvo.empresa_id === caller.empresaId);
    if (!permitidos.includes(alvo.role) || !mesmaEmpresa) {
      return comCors(errorResponse("Sem permissão para redefinir a senha deste usuário", 403));
    }

    const { error: upErr } = await service.auth.admin.updateUserById(alvoId, {
      password: novaSenha,
      email_confirm: true,
    });
    if (upErr) throw new Error(upErr.message);

    return comCors(jsonResponse({ ok: true }));
  } catch (e) {
    return comCors(errorResponse(e));
  }
});
