// Edge Function: fiscal-cte-consultar
//
// Consulta a situação de um CT-e diretamente na SEFAZ (útil quando o status
// ficou em 'erro' ou 'enviando' por instabilidade da SEFAZ durante a emissão
// original — nunca tratamos a resposta síncrona do emitir como única fonte
// de verdade).
//
// Body (JSON): { empresa_id?, chave_acesso }

import {
  errorResponse,
  getCaller,
  getServiceClient,
  jsonResponse,
  requireManageDocs,
  resolveEmpresaId,
  wrapperAuthHeader,
  wrapperUrl,
} from "../_shared/fiscal.ts";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return errorResponse("Método não suportado", 405);

    const caller = await getCaller(req);
    requireManageDocs(caller);

    const body = await req.json();
    const empresaId = resolveEmpresaId(caller, body.empresa_id);
    const chaveAcesso = body.chave_acesso;
    if (!chaveAcesso) return errorResponse("chave_acesso é obrigatória", 400);

    const service = getServiceClient();
    const { data: doc, error: docError } = await service
      .from("cte_documentos")
      .select("id, empresa_id")
      .eq("chave_acesso", chaveAcesso)
      .eq("empresa_id", empresaId)
      .single();
    if (docError) throw docError;

    const wrapperResp = await fetch(wrapperUrl(`/cte/${empresaId}/${chaveAcesso}/consultar`), {
      method: "GET",
      headers: wrapperAuthHeader(),
    });
    const resultado = await wrapperResp.json();

    if (!wrapperResp.ok || !resultado.ok) {
      return jsonResponse({ ok: false, erro: resultado.erro ?? "Falha ao consultar CT-e" }, 502);
    }

    return jsonResponse({ ok: true, resposta_acbr: resultado.resposta_acbr });
  } catch (e) {
    return errorResponse(e);
  }
});
