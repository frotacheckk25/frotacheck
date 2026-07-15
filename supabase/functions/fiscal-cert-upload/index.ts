// Edge Function: fiscal-cert-upload
//
// Recebe o certificado .pfx + senha do Flutter (ConfiguracoesFiscaisPage),
// repassa como multipart para o wrapper ACBr no servidor próprio (nunca toca
// no arquivo/senha no Supabase — só o resumo de validação volta), e atualiza
// company_settings.certificado_* com o resultado.
//
// Variáveis de ambiente necessárias (Supabase → Edge Functions → Secrets):
//   FISCAL_WRAPPER_URL    (ex: https://157-245-87-142.sslip.io)
//   FISCAL_WRAPPER_TOKEN  (mesmo valor de /root/fiscal-wrapper/.env no servidor)

import {
  errorResponse,
  getCaller,
  getServiceClient,
  jsonResponse,
  requireManageSettings,
  resolveEmpresaId,
  wrapperAuthHeader,
  wrapperUrl,
} from "../_shared/fiscal.ts";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return errorResponse("Método não suportado", 405);

    const caller = await getCaller(req);
    requireManageSettings(caller);

    // Body em JSON (não multipart) de propósito: o arquivo .pfx é pequeno
    // (poucos KB) e mandar como base64 evita qualquer incerteza sobre suporte
    // a FormData no client Dart do supabase_flutter — o Flutter só faz
    // base64Encode(bytes), sem lidar com multipart.
    const body = await req.json();
    const { empresa_id: empresaIdBody, arquivo_base64, nome_arquivo, senha } = body;

    if (typeof arquivo_base64 !== "string" || !arquivo_base64 || typeof senha !== "string" || !senha) {
      return errorResponse("arquivo_base64 e senha são obrigatórios", 400);
    }

    const empresaId = resolveEmpresaId(caller, empresaIdBody);

    const pfxBytes = Uint8Array.from(atob(arquivo_base64), (c) => c.charCodeAt(0));
    const arquivo = new File([pfxBytes], nome_arquivo || "certificado.pfx");

    const wrapperForm = new FormData();
    wrapperForm.append("arquivo", arquivo, arquivo.name);
    wrapperForm.append("senha", senha);

    const wrapperResp = await fetch(wrapperUrl(`/certificados/${empresaId}`), {
      method: "POST",
      headers: wrapperAuthHeader(),
      body: wrapperForm,
    });
    const wrapperData = await wrapperResp.json();

    if (!wrapperResp.ok || !wrapperData.ok) {
      return jsonResponse({ ok: false, erro: wrapperData.erro ?? "Falha ao validar certificado" }, 400);
    }

    const service = getServiceClient();
    const { data: existente } = await service
      .from("company_settings")
      .select("empresa_id")
      .eq("empresa_id", empresaId)
      .maybeSingle();

    const patch = {
      certificado_status: "ativo",
      certificado_cn: wrapperData.cn ?? null,
      certificado_validade: wrapperData.validade ? wrapperData.validade.slice(0, 10) : null,
      certificado_atualizado_em: new Date().toISOString(),
    };

    if (existente) {
      const { error } = await service.from("company_settings").update(patch).eq("empresa_id", empresaId);
      if (error) throw error;
    } else {
      const { error } = await service.from("company_settings").insert({ empresa_id: empresaId, ...patch });
      if (error) throw error;
    }

    return jsonResponse({ ok: true, cn: wrapperData.cn, validade: wrapperData.validade });
  } catch (e) {
    return errorResponse(e);
  }
});
