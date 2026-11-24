// Edge Function: admin-criar-conta-auth
//
// Cria a conta de AUTENTICAÇÃO (auth.users) de um novo usuário, usando a API
// de administrador (service role) — que NÃO depende do cadastro público estar
// ligado. Permite desligar o auto-cadastro no projeto (disable_signup = true)
// sem quebrar a criação de contas pelo admin.
//
// Só cria o usuário de auth e devolve o user_id. O vínculo com a empresa, o
// papel e o status continuam sendo definidos pelo app logo depois (MASTER via
// upsert em user_profiles; ADMIN_EMPRESA/GESTOR via RPC vincular_usuario_empresa),
// onde a validação de papel/empresa já existe. Aqui só garantimos que QUEM
// chama é um gestor autenticado da plataforma — nunca um visitante anônimo.
//
// Entrada (JSON): { email, senha }
// Saída: { ok: true, user_id } | { ok: false, erro, duplicado? }
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

// Só quem gerencia usuários pode criar conta (igual à matriz de admin-redefinir-senha).
const PODE_CRIAR = ["MASTER", "ADMIN_EMPRESA", "GESTOR"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    if (req.method !== "POST") return comCors(errorResponse("Método não suportado", 405));

    const caller = await getCaller(req);
    if (!PODE_CRIAR.includes(caller.role)) {
      return comCors(errorResponse("Seu papel não pode criar contas de usuário", 403));
    }

    const { email: emailRaw, senha } = await req.json();
    const email = typeof emailRaw === "string" ? emailRaw.trim().toLowerCase() : "";
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return comCors(errorResponse("E-mail inválido"));
    if (typeof senha !== "string" || senha.length < 6 || senha.length > 72) {
      return comCors(errorResponse("A senha precisa ter entre 6 e 72 caracteres"));
    }

    const service = getServiceClient();
    const { data, error } = await service.auth.admin.createUser({
      email,
      password: senha,
      email_confirm: true, // sem confirmação por e-mail (igual ao fluxo atual)
    });

    if (error) {
      const msg = String(error.message ?? error).toLowerCase();
      // e-mail já cadastrado: devolve 200 com duplicado=true para o app mostrar
      // a mensagem amigável (mesma UX de antes).
      if (msg.includes("already") || msg.includes("registered") || msg.includes("exists") || msg.includes("duplicate")) {
        return comCors(jsonResponse({ ok: false, duplicado: true, erro: "Já existe uma conta com esse e-mail." }, 200));
      }
      return comCors(errorResponse(error.message ?? "Falha ao criar a conta"));
    }

    const userId = data?.user?.id;
    if (!userId) return comCors(errorResponse("A conta não foi criada (sem user_id)"));

    return comCors(jsonResponse({ ok: true, user_id: userId }));
  } catch (e) {
    return comCors(errorResponse(e));
  }
});
