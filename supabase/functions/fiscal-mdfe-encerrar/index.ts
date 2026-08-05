// Edge Function: fiscal-mdfe-encerrar
//
// Encerra um MDF-e autorizado (confirma que a viagem terminou — obrigatório
// pela SEFAZ, não é opcional). Usa o protocolo de autorização já guardado no
// banco, então o chamador só precisa informar onde a viagem foi encerrada.
//
// Body (JSON): { empresa_id?, chave_acesso, municipio_codigo_ibge }

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
    const municipioCodigoIbge = body.municipio_codigo_ibge;

    if (!chaveAcesso) return errorResponse("chave_acesso é obrigatória", 400);
    if (!municipioCodigoIbge) return errorResponse("municipio_codigo_ibge é obrigatório", 400);

    const service = getServiceClient();
    const { data: doc, error: docError } = await service
      .from("mdfe_documentos")
      .select("id, empresa_id, status, protocolo_autorizacao")
      .eq("chave_acesso", chaveAcesso)
      .eq("empresa_id", empresaId)
      .single();
    if (docError) throw docError;
    if (doc.status !== "autorizado") {
      return jsonResponse({ ok: false, erro: `Só é possível encerrar um MDF-e autorizado (status atual: ${doc.status})` }, 400);
    }
    if (!doc.protocolo_autorizacao) {
      return jsonResponse({ ok: false, erro: "MDF-e sem protocolo de autorização registrado" }, 400);
    }

    const { data: empresa, error: empresaError } = await service
      .from("empresas")
      .select("cnpj")
      .eq("id", empresaId)
      .single();
    if (empresaError) throw empresaError;

    const wrapperResp = await fetch(wrapperUrl(`/mdfe/${empresaId}/${chaveAcesso}/encerrar`), {
      method: "POST",
      headers: { ...wrapperAuthHeader(), "Content-Type": "application/json" },
      body: JSON.stringify({
        municipio_codigo_ibge: municipioCodigoIbge,
        cnpj: empresa.cnpj,
        protocolo: doc.protocolo_autorizacao,
      }),
    });
    const resultado = await wrapperResp.json();

    if (!wrapperResp.ok || !resultado.ok) {
      return jsonResponse({ ok: false, erro: resultado.erro ?? "Falha ao encerrar MDF-e" }, 502);
    }

    await service
      .from("mdfe_documentos")
      .update({ status: "encerrado", encerrado_em: new Date().toISOString() })
      .eq("id", doc.id);

    return jsonResponse({ ok: true, resposta_acbr: resultado.resposta_acbr });
  } catch (e) {
    return errorResponse(e);
  }
});
