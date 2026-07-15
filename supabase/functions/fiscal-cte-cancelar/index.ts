// Edge Function: fiscal-cte-cancelar
//
// Body (JSON): { empresa_id?, chave_acesso, justificativa (>=15 caracteres) }

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
    const justificativa = body.justificativa ?? "";

    if (!chaveAcesso) return errorResponse("chave_acesso é obrigatória", 400);
    if (justificativa.length < 15) {
      return errorResponse("justificativa precisa ter no mínimo 15 caracteres (exigência da SEFAZ)", 400);
    }

    const service = getServiceClient();
    const { data: doc, error: docError } = await service
      .from("cte_documentos")
      .select("id, empresa_id, status")
      .eq("chave_acesso", chaveAcesso)
      .eq("empresa_id", empresaId)
      .single();
    if (docError) throw docError;
    if (doc.status !== "autorizado") {
      return jsonResponse({ ok: false, erro: `Só é possível cancelar um CT-e autorizado (status atual: ${doc.status})` }, 400);
    }

    const { data: empresa, error: empresaError } = await service
      .from("empresas")
      .select("cnpj")
      .eq("id", empresaId)
      .single();
    if (empresaError) throw empresaError;

    const wrapperResp = await fetch(wrapperUrl(`/cte/${empresaId}/${chaveAcesso}/cancelar`), {
      method: "POST",
      headers: { ...wrapperAuthHeader(), "Content-Type": "application/json" },
      body: JSON.stringify({ justificativa, cnpj: empresa.cnpj }),
    });
    const resultado = await wrapperResp.json();

    if (!wrapperResp.ok || !resultado.ok) {
      return jsonResponse({ ok: false, erro: resultado.erro ?? "Falha ao cancelar CT-e" }, 502);
    }

    await service.from("cte_documentos").update({ status: "cancelado" }).eq("id", doc.id);

    return jsonResponse({ ok: true, resposta_acbr: resultado.resposta_acbr });
  } catch (e) {
    return errorResponse(e);
  }
});
