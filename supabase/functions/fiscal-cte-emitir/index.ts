// Edge Function: fiscal-cte-emitir
//
// Monta e emite um CT-e real via o wrapper ACBr no servidor próprio. Ao
// contrário de send-push-notification (fire-and-forget, fail-open), esta é
// síncrona e fail-closed: um CT-e existe na SEFAZ ou não existe, o estado
// nunca fica ambíguo no banco.
//
// Body esperado (JSON):
// {
//   empresa_id?: string (obrigatório se MASTER),
//   cte_documento_id?: string (rascunho existente, criado pela Nova Viagem — se
//     omitido, cria um novo registro do zero),
//   viagem_id?, veiculo_id?, motorista_id?,
//   remetente: { documento, nome, ie?, email?, endereco: {...} },
//   destinatario: { documento, nome, ie?, endereco: {...} },
//   carga: { natureza, valor, peso_bruto, produto_predominante },
//   valores: { valor_frete },
//   documento_fiscal: { tipo: 'nfe'|'nf', ... },
//   municipio_inicio: { codigo_ibge, nome, uf },
//   municipio_fim: { codigo_ibge, nome, uf },
//   veiculo?: { placa, renavam, uf },
//   tomador_indice?: 0|1|2|3
// }
//
// Variáveis de ambiente necessárias (Supabase → Edge Functions → Secrets):
//   FISCAL_WRAPPER_URL, FISCAL_WRAPPER_TOKEN

import {
  chamarWrapper,
  errorResponse,
  getCaller,
  getServiceClient,
  jsonResponse,
  requireManageDocs,
  resolveEmpresaId,
} from "../_shared/fiscal.ts";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return errorResponse("Método não suportado", 405);

    const caller = await getCaller(req);
    requireManageDocs(caller);

    const body = await req.json();
    const empresaId = resolveEmpresaId(caller, body.empresa_id);

    const service = getServiceClient();

    const { data: empresa, error: empresaError } = await service
      .from("empresas")
      .select("razao_social, nome, cnpj, inscricao_estadual, rntrc, uf")
      .eq("id", empresaId)
      .single();
    if (empresaError) throw empresaError;

    const { data: settings, error: settingsError } = await service
      .from("company_settings")
      .select(
        "cte_habilitado, certificado_status, ambiente_fiscal, fiscal_regime_tributario, " +
        "fiscal_logradouro, fiscal_numero, fiscal_complemento, fiscal_bairro, " +
        "fiscal_municipio_codigo_ibge, fiscal_municipio_nome, fiscal_cep, fiscal_fone",
      )
      .eq("empresa_id", empresaId)
      .maybeSingle();
    if (settingsError) throw settingsError;

    if (!settings?.cte_habilitado) {
      return jsonResponse({ ok: false, erro: "CT-e não está habilitado para esta empresa" }, 400);
    }
    if (settings.certificado_status !== "ativo") {
      return jsonResponse({ ok: false, erro: "Certificado digital não configurado ou inválido" }, 400);
    }

    const ambienteNum = settings.ambiente_fiscal === "producao" ? 1 : 2;

    // Só reaproveita registro que ainda não virou documento fiscal válido —
    // nunca sobrescreve um CT-e autorizado/cancelado/em envio.
    if (body.cte_documento_id) {
      const { data: existente, error: existenteError } = await service
        .from("cte_documentos")
        .select("status")
        .eq("id", body.cte_documento_id)
        .eq("empresa_id", empresaId)
        .maybeSingle();
      if (existenteError) throw existenteError;
      if (!existente) return jsonResponse({ ok: false, erro: "CT-e não encontrado para esta empresa" }, 404);
      if (!["rascunho", "erro", "rejeitado"].includes(existente.status)) {
        return jsonResponse({ ok: false, erro: `Este CT-e não pode ser reemitido (status atual: ${existente.status})` }, 409);
      }
    }

    // Veículo/motorista/viagem informados precisam ser da mesma empresa.
    const vinculos: Array<[string, string | undefined]> = [
      ["vehicles", body.veiculo_id],
      ["drivers", body.motorista_id],
      ["viagens", body.viagem_id],
    ];
    for (const [tabela, id] of vinculos) {
      if (!id) continue;
      const { data: ref } = await service.from(tabela).select("id").eq("id", id).eq("empresa_id", empresaId).maybeSingle();
      if (!ref) return jsonResponse({ ok: false, erro: `Vínculo inválido (${tabela}) para esta empresa` }, 400);
    }

    const { data: numeroCte, error: numeroError } = await service.rpc("fiscal_proximo_numero", {
      p_empresa_id: empresaId,
      p_tipo: "cte",
      p_serie: 1,
    });
    if (numeroError) throw numeroError;

    // Registro em "enviando" antes de chamar o wrapper — nunca deixamos o
    // estado ambíguo se a chamada travar/cair no meio.
    const registroBase = {
      empresa_id: empresaId,
      viagem_id: body.viagem_id ?? null,
      veiculo_id: body.veiculo_id ?? null,
      motorista_id: body.motorista_id ?? null,
      numero_cte: numeroCte,
      serie: 1,
      ambiente: settings.ambiente_fiscal,
      remetente_nome: body.remetente?.nome ?? null,
      remetente_doc: body.remetente?.documento ?? null,
      destinatario_nome: body.destinatario?.nome ?? null,
      destinatario_doc: body.destinatario?.documento ?? null,
      natureza_carga: body.carga?.natureza ?? null,
      valor_carga: body.carga?.valor ?? null,
      valor_frete: body.valores?.valor_frete ?? null,
      peso_bruto: body.carga?.peso_bruto ?? null,
      status: "enviando",
      criado_por: caller.userId,
    };

    let cteId: string;
    if (body.cte_documento_id) {
      const { data, error } = await service
        .from("cte_documentos")
        .update(registroBase)
        .eq("id", body.cte_documento_id)
        .eq("empresa_id", empresaId)
        .select("id")
        .single();
      if (error) throw error;
      cteId = data.id;
    } else {
      const { data, error } = await service
        .from("cte_documentos")
        .insert(registroBase)
        .select("id")
        .single();
      if (error) throw error;
      cteId = data.id;
    }

    const wrapperPayload = {
      ambiente: ambienteNum,
      numero_cte: numeroCte,
      serie: 1,
      regime_tributario: settings.fiscal_regime_tributario ?? "simples_nacional",
      emitente: {
        cnpj: empresa.cnpj,
        ie: empresa.inscricao_estadual,
        razao_social: empresa.razao_social ?? empresa.nome,
        rntrc: empresa.rntrc,
        endereco: {
          logradouro: settings.fiscal_logradouro,
          numero: settings.fiscal_numero,
          complemento: settings.fiscal_complemento,
          bairro: settings.fiscal_bairro,
          municipio_codigo_ibge: settings.fiscal_municipio_codigo_ibge,
          municipio_nome: settings.fiscal_municipio_nome,
          uf: empresa.uf,
          cep: settings.fiscal_cep,
          fone: settings.fiscal_fone,
        },
      },
      remetente: body.remetente,
      destinatario: body.destinatario,
      carga: body.carga,
      valores: body.valores,
      veiculo: body.veiculo,
      municipio_inicio: body.municipio_inicio,
      municipio_fim: body.municipio_fim,
      documento_fiscal: body.documento_fiscal,
      tomador_indice: body.tomador_indice ?? 0,
      icms: body.icms,
    };

    const resultado = await chamarWrapper(`/cte/${empresaId}/emitir`, wrapperPayload);

    if (resultado.status === "autorizado") {
      let xmlUrl: string | null = null;
      if (resultado.xml_base64) {
        const xmlBytes = Uint8Array.from(atob(resultado.xml_base64), (c) => c.charCodeAt(0));
        const path = `${empresaId}/cte/${resultado.chave_acesso}.xml`;
        const { error: uploadError } = await service.storage
          .from("documentos-fiscais")
          .upload(path, xmlBytes, { contentType: "application/xml", upsert: true });
        if (!uploadError) xmlUrl = path;
      }

      await service
        .from("cte_documentos")
        .update({
          status: "autorizado",
          chave_acesso: resultado.chave_acesso,
          protocolo_autorizacao: resultado.protocolo,
          xml_autorizado_url: xmlUrl,
          autorizado_em: new Date().toISOString(),
        })
        .eq("id", cteId);

      return jsonResponse({ ok: true, status: "autorizado", chave_acesso: resultado.chave_acesso, protocolo: resultado.protocolo });
    }

    if (resultado.status === "rejeitado") {
      await service
        .from("cte_documentos")
        .update({ status: "rejeitado", motivo_rejeicao: resultado.motivo ?? "Rejeitado pela SEFAZ" })
        .eq("id", cteId);
      return jsonResponse({ ok: false, status: "rejeitado", motivo: resultado.motivo });
    }

    // Erro (wrapper inacessível, falha de validação local, timeout, etc.) —
    // fica em 'erro' com um botão manual de "Consultar situação" na tela,
    // nunca assumimos falha silenciosamente.
    await service
      .from("cte_documentos")
      .update({ status: "erro", motivo_rejeicao: resultado.erro ?? "Erro desconhecido ao emitir" })
      .eq("id", cteId);
    return jsonResponse({ ok: false, status: "erro", erro: resultado.erro }, 502);
  } catch (e) {
    return errorResponse(e);
  }
});
