// Helpers compartilhados pelas Edge Functions de Documentos Fiscais
// (CT-e/MDF-e/CIOT). Diferente de send-push-notification (disparada por
// trigger, fail-open), estas são chamadas direto do Flutter via
// supabase.functions.invoke(...) e precisam validar o chamador elas mesmas —
// a RLS deste projeto só garante isolamento de tenant, não permissão fina.
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.111.0";

export interface CallerInfo {
  userId: string;
  empresaId: string | null;
  role: string;
}

export function getServiceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

/** Valida o JWT do chamador (via Authorization header) e busca seu papel/empresa. */
export async function getCaller(req: Request): Promise<CallerInfo> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new Error("Sem autenticação");

  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user }, error: userError } = await supabaseUser.auth.getUser();
  if (userError || !user) throw new Error("Token inválido ou expirado");

  const service = getServiceClient();
  const { data: perfil, error: perfilError } = await service
    .from("user_profiles")
    .select("empresa_id, role")
    .eq("user_id", user.id)
    .maybeSingle();

  if (perfilError) throw new Error(`Erro ao buscar perfil: ${perfilError.message}`);
  if (!perfil) throw new Error("Perfil de usuário não encontrado");

  return { userId: user.id, empresaId: perfil.empresa_id, role: perfil.role };
}

const ROLES_MANAGE_DOCS = ["MASTER", "ADMIN_EMPRESA", "GESTOR"];
const ROLES_MANAGE_SETTINGS = ["MASTER", "ADMIN_EMPRESA"];

export function requireManageDocs(caller: CallerInfo) {
  if (!ROLES_MANAGE_DOCS.includes(caller.role)) {
    throw new Error("Permissão negada: seu papel não pode gerenciar documentos fiscais");
  }
}

export function requireManageSettings(caller: CallerInfo) {
  if (!ROLES_MANAGE_SETTINGS.includes(caller.role)) {
    throw new Error("Permissão negada: seu papel não pode gerenciar configurações fiscais");
  }
}

/** Resolve qual empresa a operação afeta: MASTER pode mirar qualquer uma
 * (desde que informe empresa_id explicitamente); os demais só a própria. */
export function resolveEmpresaId(caller: CallerInfo, requestedEmpresaId?: string | null): string {
  if (caller.role === "MASTER") {
    if (!requestedEmpresaId) throw new Error("empresa_id é obrigatório para o papel MASTER");
    return requestedEmpresaId;
  }
  if (!caller.empresaId) throw new Error("Usuário não está vinculado a nenhuma empresa");
  if (requestedEmpresaId && requestedEmpresaId !== caller.empresaId) {
    throw new Error("Sem permissão para operar em outra empresa");
  }
  return caller.empresaId;
}

export function wrapperUrl(path: string): string {
  const base = Deno.env.get("FISCAL_WRAPPER_URL");
  if (!base) throw new Error("FISCAL_WRAPPER_URL não configurado (Edge Function secret)");
  return `${base}${path}`;
}

export function wrapperAuthHeader(): Record<string, string> {
  const token = Deno.env.get("FISCAL_WRAPPER_TOKEN");
  if (!token) throw new Error("FISCAL_WRAPPER_TOKEN não configurado (Edge Function secret)");
  return { Authorization: `Bearer ${token}` };
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function errorResponse(e: unknown, status = 400): Response {
  const message = e instanceof Error ? e.message : String(e);
  console.error("fiscal function error:", message);
  return jsonResponse({ ok: false, erro: message }, status);
}
