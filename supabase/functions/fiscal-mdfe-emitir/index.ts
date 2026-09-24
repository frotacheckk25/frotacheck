// Edge Function: fiscal-mdfe-emitir
//
// Monta e emite um MDF-e real via o wrapper ACBr, agrupando um ou mais CT-e
// já autorizados da mesma empresa. Mesmo padrão de fiscal-cte-emitir:
// síncrona e fail-closed.
//
// Body esperado (JSON):
// {
//   empresa_id?: string (obrigatório se MASTER),
//   cte_ids: string[] (ids de cte_documentos já autorizados desta empresa),
//   veiculo_tracao: { placa, uf, renavam, tara?, cap_kg?, cap_m3?, tipo_rodado?, tipo_carroceria? },
//   motorista: { nome, cpf },
//   municipio_carregamento: { codigo_ibge, nome, cep? },
//   municipio_descarregamento: { codigo_ibge, nome, cep? },
//   uf_ini, uf_fim,
//   carga: { valor, peso_bruto, produto_predominante, tipo_carga?, ncm? },
//   seguro?: { responsavel?, seguradora_nome?, seguradora_cnpj?, numero_apolice?, numero_averbacao? },
//   contratante?: { cnpj, razao_social }
// }

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
    const cteIds: string[] = body.cte_ids ?? [];
    if (!cteIds.length) {
      return jsonResponse({ ok: false, erro: "cte_ids é obrigatório (ao menos um CT-e autorizado)" }, 400);
    }

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
        "mdfe_habilitado, certificado_status, ambiente_fiscal, " +
        "fiscal_logradouro, fiscal_numero, fiscal_complemento, fiscal_bairro, " +
        "fiscal_municipio_codigo_ibge, fiscal_municipio_nome, fiscal_cep, fiscal_fone",
      )
      .eq("empresa_id", empresaId)
      .maybeSingle();
    if (settingsError) throw settingsError;

    if (!settings?.mdfe_habilitado) {
      return jsonResponse({ ok: false, erro: "MDF-e não está habilitado para esta empresa" }, 400);
    }
    if (settings.certificado_status !== "ativo") {
      return jsonResponse({ ok: false, erro: "Certificado digital não configurado ou inválido" }, 400);
    }

    // Os CT-e referenciados precisam existir, ser desta empresa e já estarem
    // autorizados pela SEFAZ — um MDF-e nunca pode agrupar rascunho/rejeitado.
    const { data: ctes, error: ctesError } = await service
      .from("cte_documentos")
      .select("id, chave_acesso, status")
      .in("id", cteIds)
      .eq("empresa_id", empresaId);
    if (ctesError) throw ctesError;
    if (!ctes || ctes.length !== cteIds.length) {
      return jsonResponse({ ok: false, erro: "Um ou mais CT-e informados não pertencem a esta empresa" }, 400);
    }
    const naoAutorizados = ctes.filter((c) => c.status !== "autorizado");
    if (naoAutorizados.length > 0) {
      return jsonResponse({ ok: false, erro: "Só é possível incluir CT-e já autorizados pela SEFAZ no MDF-e" }, 400);
    }

    const ambienteNum = settings.ambiente_fiscal === "producao" ? 1 : 2;

    const { data: numeroMdfe, error: numeroError } = await service.rpc("fiscal_proximo_numero", {
      p_empresa_id: empresaId,
      p_tipo: "mdfe",
      p_serie: 1,
    });
    if (numeroError) throw numeroError;

    const { data: mdfeRow, error: insertError } = await service
      .from("mdfe_documentos")
      .insert({
        empresa_id: empresaId,
        numero_mdfe: numeroMdfe,
        serie: 1,
        ambiente: settings.ambiente_fiscal,
        status: "enviando",
        criado_por: caller.userId,
      })
      .select("id")
      .single();
    if (insertError) throw insertError;
    const mdfeId = mdfeRow.id;

    const { error: juncaoError } = await service
      .from("mdfe_cte")
      .insert(cteIds.map((cteId) => ({ mdfe_id: mdfeId, cte_id: cteId })));
    if (juncaoError) {
      // Não deixa o MDF-e preso em "enviando" sem os CT-e vinculados.
      await service.from("mdfe_documentos")
        .update({ status: "erro", motivo_rejeicao: "Falha ao vincular os CT-e ao MDF-e" })
        .eq("id", mdfeId);
      throw juncaoError;
    }

    const wrapperPayload = {
      ambiente: ambienteNum,
      numero_mdfe: numeroMdfe,
      serie: 1,
      uf_ini: body.uf_ini,
      uf_fim: body.uf_fim,
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
      veiculo_tracao: body.veiculo_tracao,
      motorista: body.motorista,
      municipio_carregamento: body.municipio_carregamento,
      municipio_descarregamento: body.municipio_descarregamento,
      ctes: ctes.map((c) => ({ chave: c.chave_acesso })),
      carga: body.carga,
      seguro: body.seguro,
      contratante: body.contratante,
    };

    const resultado = await chamarWrapper(`/mdfe/${empresaId}/emitir`, wrapperPayload);

    if (resultado.status === "autorizado") {
      let xmlUrl: string | null = null;
      if (resultado.xml_base64) {
        const xmlBytes = Uint8Array.from(atob(resultado.xml_base64), (c) => c.charCodeAt(0));
        const path = `${empresaId}/mdfe/${resultado.chave_acesso}.xml`;
        const { error: uploadError } = await service.storage
          .from("documentos-fiscais")
          .upload(path, xmlBytes, { contentType: "application/xml", upsert: true });
        if (!uploadError) xmlUrl = path;
      }

      await service
        .from("mdfe_documentos")
        .update({
          status: "autorizado",
          chave_acesso: resultado.chave_acesso,
          protocolo_autorizacao: resultado.protocolo,
          xml_autorizado_url: xmlUrl,
          autorizado_em: new Date().toISOString(),
        })
        .eq("id", mdfeId);

      return jsonResponse({ ok: true, status: "autorizado", chave_acesso: resultado.chave_acesso, protocolo: resultado.protocolo });
    }

    if (resultado.status === "rejeitado") {
      await service
        .from("mdfe_documentos")
        .update({ status: "rejeitado", motivo_rejeicao: resultado.motivo ?? "Rejeitado pela SEFAZ" })
        .eq("id", mdfeId);
      return jsonResponse({ ok: false, status: "rejeitado", motivo: resultado.motivo });
    }

    // Erro (wrapper inacessível, falha de validação local, timeout, etc.) —
    // fica em 'erro' com um botão manual de "Consultar situação" na tela,
    // nunca assumimos falha silenciosamente.
    await service
      .from("mdfe_documentos")
      .update({ status: "erro", motivo_rejeicao: resultado.erro ?? "Erro desconhecido ao emitir" })
      .eq("id", mdfeId);
    return jsonResponse({ ok: false, status: "erro", erro: resultado.erro }, 502);
  } catch (e) {
    return errorResponse(e);
  }
});
