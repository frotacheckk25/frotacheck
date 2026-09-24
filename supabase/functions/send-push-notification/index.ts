// Edge Function: send-push-notification
//
// Disparada pelo gatilho public.notify_new_event() (via pg_net) sempre que
// uma linha nova entra em fuelings/occurrences/multas/manutencoes/viagens/
// checklists/alerts.
// Busca quem é ADMIN_EMPRESA/GESTOR da empresa do registro, pega os tokens
// FCM deles em device_tokens, e envia a notificação via Firebase Admin SDK.
//
// Variáveis de ambiente necessárias (Supabase → Edge Functions → Secrets):
//   SUPABASE_URL                 (já disponível automaticamente)
//   SUPABASE_SERVICE_ROLE_KEY    (já disponível automaticamente)
//   FIREBASE_SERVICE_ACCOUNT     (JSON da service account do Firebase, como string)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.111.0";
import { initializeApp, cert, getApps } from "npm:firebase-admin@12.7.0/app";
import { getMessaging } from "npm:firebase-admin@12.7.0/messaging";

interface Contexto {
  placa: string | null;
  veiculoDescricao: string | null;
  motorista: string | null;
}

// Monta o trecho "— veículo ABC-1234 (Fiat Strada), motorista João Silva" a
// partir do que estiver disponível (nem todo registro tem os dois vinculados).
function sufixoContexto(ctx: Contexto): string {
  const partes: string[] = [];
  if (ctx.veiculoDescricao) partes.push(`veículo ${ctx.veiculoDescricao}`);
  if (ctx.motorista) partes.push(`motorista ${ctx.motorista}`);
  return partes.length > 0 ? ` — ${partes.join(", ")}` : "";
}

const MENSAGENS: Record<string, { title: string | ((r: any) => string); body: (r: any, ctx: Contexto) => string }> = {
  fuelings: {
    title: "Novo abastecimento registrado",
    body: (r, ctx) => `Abastecimento de R$ ${Number(r.total_value ?? 0).toFixed(2)} registrado${sufixoContexto(ctx)}.`,
  },
  occurrences: {
    title: "Nova ocorrência registrada",
    body: (r, ctx) => `Ocorrência: ${r.problem_type ?? "novo problema"} — prioridade ${r.priority ?? "não informada"}${sufixoContexto(ctx)}.`,
  },
  multas: {
    title: "Nova multa registrada",
    body: (r, ctx) => `Multa: ${r.tipo ?? "infração"} registrada${sufixoContexto(ctx)}.`,
  },
  manutencoes: {
    title: "Manutenção registrada",
    // Sem valor aqui de propósito: na criação cost/valor são sempre 0 —
    // o valor real só é preenchido depois, no fluxo de "Marcar como Resolvido".
    body: (r, ctx) => `${r.tipo ?? "Manutenção"} registrada${sufixoContexto(ctx)}.`,
  },
  viagens: {
    title: "Viagem iniciada",
    body: (r, ctx) => `De ${r.origem ?? "?"} para ${r.destino ?? "?"}${sufixoContexto(ctx)}.`,
  },
  checklists: {
    title: (r) => (r.tipo === "retorno" ? "Checklist de retorno registrado" : "Checklist de saída registrado"),
    body: (r, ctx) =>
      `Checklist de ${r.tipo === "retorno" ? "retorno" : "saída"} registrado${sufixoContexto(ctx)}.`,
  },
  alerts: {
    title: "Novo alerta",
    // alerts não tem coluna "message" — o texto real está em description/descricao
    // (ou title/titulo, dependendo de quando o alerta foi criado).
    body: (r, ctx) =>
      (r.description ?? r.descricao ?? r.title ?? r.titulo ?? "Um novo alerta foi gerado para sua frota") +
      sufixoContexto(ctx),
  },
};

function getFirebaseApp() {
  const existing = getApps();
  if (existing.length > 0) return existing[0];

  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT não configurado");
  const serviceAccount = JSON.parse(raw);

  return initializeApp({ credential: cert(serviceAccount) });
}

// Só o gatilho do banco (notify_new_event, que envia a service_role key do
// Vault) pode disparar push. Antes qualquer usuário logado conseguia chamar
// esta função e mandar notificação com texto livre para gestores de qualquer
// empresa. PUSH_TRIGGER_SECRET é opcional (caso o Vault guarde outra chave).
function chamadorAutorizado(req: Request): boolean {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return false;
  const aceitos = [
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    Deno.env.get("PUSH_TRIGGER_SECRET"),
  ].filter((v): v is string => !!v);
  return aceitos.includes(token);
}

Deno.serve(async (req) => {
  try {
    if (!chamadorAutorizado(req)) {
      return new Response(JSON.stringify({ error: "não autorizado" }), { status: 401 });
    }

    const { table, record } = await req.json();
    if (!table || !record?.empresa_id) {
      return new Response(JSON.stringify({ skipped: "sem tabela ou empresa_id" }), { status: 200 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1) Quem deve ser avisado: ADMIN_EMPRESA e GESTOR da mesma empresa.
    const { data: perfis, error: perfisError } = await supabase
      .from("user_profiles")
      .select("user_id")
      .eq("empresa_id", record.empresa_id)
      .eq("status", "ativo")
      .in("role", ["ADMIN_EMPRESA", "GESTOR"]);

    if (perfisError) throw perfisError;
    if (!perfis || perfis.length === 0) {
      return new Response(JSON.stringify({ skipped: "sem admin/gestor na empresa" }), { status: 200 });
    }

    const userIds = perfis.map((p) => p.user_id);

    // 2) Tokens de notificação desses usuários.
    const { data: tokens, error: tokensError } = await supabase
      .from("device_tokens")
      .select("fcm_token")
      .in("user_id", userIds);

    if (tokensError) throw tokensError;
    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ skipped: "sem tokens cadastrados" }), { status: 200 });
    }

    // 3) Busca placa/modelo do veículo e nome do motorista para dar contexto
    // na mensagem. viagens/checklists usam veiculo_id/motorista_id em vez de
    // vehicle_id/driver_id.
    const vehicleId = record.vehicle_id ?? record.veiculo_id;
    let driverId = record.driver_id ?? record.motorista_id;
    const ctx: Contexto = { placa: null, veiculoDescricao: null, motorista: null };
    if (vehicleId) {
      const { data: veic } = await supabase
        .from("vehicles")
        .select("plate, brand, model, driver_id")
        .eq("id", vehicleId)
        .maybeSingle();
      if (veic) {
        ctx.placa = veic.plate ?? null;
        const modelo = [veic.brand, veic.model].filter(Boolean).join(" ");
        ctx.veiculoDescricao = modelo ? `${veic.plate ?? "?"} (${modelo})` : veic.plate ?? null;
        // manutencoes/alerts não têm coluna de motorista própria — usa o
        // motorista atualmente atribuído ao veículo.
        if (!driverId) driverId = veic.driver_id;
      }
    }
    if (driverId) {
      const { data: drv } = await supabase.from("drivers").select("name").eq("id", driverId).maybeSingle();
      ctx.motorista = drv?.name ?? null;
    }

    // 4) Monta e envia a notificação.
    const cfg = MENSAGENS[table] ?? {
      title: "FrotaCheck",
      body: () => "Nova atividade registrada na sua frota.",
    };
    const titulo = typeof cfg.title === "function" ? cfg.title(record) : cfg.title;

    const app = getFirebaseApp();
    const messaging = getMessaging(app);

    const resultados = await Promise.allSettled(
      tokens.map((t) =>
        messaging.send({
          token: t.fcm_token,
          notification: { title: titulo, body: cfg.body(record, ctx) },
          data: { table, record_id: String(record.id ?? "") },
        })
      ),
    );

    const falhas = resultados.filter((r) => r.status === "rejected").length;

    // Remove tokens de aparelhos que desinstalaram o app / trocaram de conta,
    // para não acumular lixo nem mandar push para o aparelho errado.
    const tokensInvalidos = tokens
      .filter((_, i) => {
        const r = resultados[i];
        // deno-lint-ignore no-explicit-any
        const code = r.status === "rejected" ? (r.reason as any)?.code ?? (r.reason as any)?.errorInfo?.code : null;
        return code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token";
      })
      .map((t) => t.fcm_token);
    if (tokensInvalidos.length > 0) {
      await supabase.from("device_tokens").delete().in("fcm_token", tokensInvalidos);
    }

    return new Response(
      JSON.stringify({ enviados: tokens.length - falhas, falhas }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("send-push-notification error:", e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
