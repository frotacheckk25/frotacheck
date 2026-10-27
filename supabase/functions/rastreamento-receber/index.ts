// Edge Function: rastreamento-receber
//
// Recebe posições do rastreador do caminhão (ou da central de rastreamento) e
// grava na Torre de Controle. Autenticação pelo token de integração da
// empresa (Torre de Controle → Integração com rastreador), enviado em
// "Authorization: Bearer fc_..." ou "x-token: fc_...". O banco guarda só o
// hash do token. Chamada por sistemas de fora, então verify_jwt = false.
//
// Corpo (JSON), até 1000 posições por envio:
// { "posicoes": [ { "placa": "ABC1D23", "latitude": -21.89, "longitude": -45.59,
//                   "velocidade": 72, "data_hora": "2026-10-27T14:00:00-03:00",
//                   "ignicao": true, "rumo": 180 } ] }
// Resposta: { ok, recebidas, gravadas, invalidas, placas_desconhecidas }
import { getServiceClient } from "../_shared/fiscal.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-token, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

async function sha256Hex(texto: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const placaNormal = (p: unknown) => String(p ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");

function numero(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, erro: "Use POST" }, 405);
  try {
    const auth = req.headers.get("authorization") ?? "";
    const token = (auth.toLowerCase().startsWith("bearer ") ? auth.slice(7) : req.headers.get("x-token") ?? "").trim();
    if (!token.startsWith("fc_")) return json({ ok: false, erro: "Token de integração ausente ou inválido" }, 401);

    const service = getServiceClient();
    const { data: integ, error: erroToken } = await service
      .from("rastreamento_integracoes")
      .select("id, empresa_id, ativo")
      .eq("token_hash", await sha256Hex(token))
      .maybeSingle();
    if (erroToken) throw erroToken;
    if (!integ || !integ.ativo) return json({ ok: false, erro: "Token de integração inválido ou revogado" }, 401);

    const corpo = await req.json().catch(() => null);
    const lista = Array.isArray(corpo) ? corpo : Array.isArray(corpo?.posicoes) ? corpo.posicoes : null;
    if (!lista) return json({ ok: false, erro: 'Envie {"posicoes": [...]}' }, 400);
    if (lista.length > 1000) return json({ ok: false, erro: "Máximo de 1000 posições por envio" }, 413);

    const { data: veiculos, error: erroVeic } = await service.from("vehicles").select("id, plate").eq("empresa_id", integ.empresa_id);
    if (erroVeic) throw erroVeic;
    const porPlaca = new Map((veiculos ?? []).map((v) => [placaNormal(v.plate), v.id as string]));

    const agora = Date.now();
    const linhas: Record<string, unknown>[] = [];
    const desconhecidas = new Set<string>();
    let invalidas = 0;
    for (const p of lista) {
      const vehicleId = porPlaca.get(placaNormal(p?.placa));
      if (!vehicleId) {
        desconhecidas.add(String(p?.placa ?? ""));
        continue;
      }
      const lat = numero(p?.latitude ?? p?.lat);
      const lng = numero(p?.longitude ?? p?.lng ?? p?.lon);
      const quando = new Date(p?.data_hora ?? p?.registrado_em ?? agora);
      const t = quando.getTime();
      // mesma janela do banco: até 10 min no futuro e 7 dias no passado
      if (lat === null || lng === null || Math.abs(lat) > 90 || Math.abs(lng) > 180 ||
          !Number.isFinite(t) || t > agora + 10 * 60e3 || t < agora - 7 * 86400e3) {
        invalidas++;
        continue;
      }
      const vel = numero(p?.velocidade ?? p?.velocidade_kmh);
      const rumo = numero(p?.rumo ?? p?.direcao);
      linhas.push({
        empresa_id: integ.empresa_id,
        vehicle_id: vehicleId,
        latitude: lat,
        longitude: lng,
        velocidade_kmh: vel !== null && vel >= 0 && vel <= 300 ? vel : null,
        rumo: rumo !== null && rumo >= 0 && rumo <= 360 ? rumo : null,
        ignicao: typeof p?.ignicao === "boolean" ? p.ignicao : null,
        origem: "rastreador",
        registrado_em: quando.toISOString(),
      });
    }
    // em ordem de horário: "parado desde" e última posição saem certos
    linhas.sort((a, b) => String(a.registrado_em).localeCompare(String(b.registrado_em)));
    if (linhas.length) {
      const { error } = await service.from("rastreamento_posicoes").insert(linhas);
      if (error) return json({ ok: false, erro: error.message }, 400);
    }
    await service.from("rastreamento_integracoes").update({ ultimo_uso: new Date().toISOString() }).eq("id", integ.id);
    return json({ ok: true, recebidas: lista.length, gravadas: linhas.length, invalidas, placas_desconhecidas: [...desconhecidas] });
  } catch (e) {
    return json({ ok: false, erro: e instanceof Error ? e.message : String(e) }, 500);
  }
});
