// Edge Function: send-push-notification
//
// Disparada pelo gatilho public.notify_new_event() (via pg_net) sempre que
// uma linha nova entra em fuelings/occurrences/multas/oil_changes/alerts.
// Busca quem é ADMIN_EMPRESA/GESTOR da empresa do registro, pega os tokens
// FCM deles em device_tokens, e envia a notificação via Firebase Admin SDK.
//
// Variáveis de ambiente necessárias (Supabase → Edge Functions → Secrets):
//   SUPABASE_URL                 (já disponível automaticamente)
//   SUPABASE_SERVICE_ROLE_KEY    (já disponível automaticamente)
//   FIREBASE_SERVICE_ACCOUNT     (JSON da service account do Firebase, como string)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { initializeApp, cert, getApps } from "npm:firebase-admin@12/app";
import { getMessaging } from "npm:firebase-admin@12/messaging";

interface Contexto {
  placa: string | null;
  motorista: string | null;
}

// Monta o trecho "— veículo ABC-1234, motorista João Silva" a partir do que
// estiver disponível (nem todo registro tem os dois vinculados).
function sufixoContexto(ctx: Contexto): string {
  const partes: string[] = [];
  if (ctx.placa) partes.push(`veículo ${ctx.placa}`);
  if (ctx.motorista) partes.push(`motorista ${ctx.motorista}`);
  return partes.length > 0 ? ` — ${partes.join(", ")}` : "";
}

const MENSAGENS: Record<string, { title: string; body: (r: any, ctx: Contexto) => string }> = {
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
  oil_changes: {
    title: "Manutenção registrada",
    body: (_r, ctx) => `Troca de óleo/manutenção registrada${sufixoContexto(ctx)}.`,
  },
  alerts: {
    title: "Novo alerta",
    body: (r, ctx) => (r.message ?? "Um novo alerta foi gerado para sua frota") + sufixoContexto(ctx),
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

Deno.serve(async (req) => {
  try {
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

    // 3) Busca placa do veículo e nome do motorista para dar contexto na mensagem.
    const ctx: Contexto = { placa: null, motorista: null };
    if (record.vehicle_id) {
      const { data: veic } = await supabase.from("vehicles").select("plate").eq("id", record.vehicle_id).maybeSingle();
      ctx.placa = veic?.plate ?? null;
    }
    if (record.driver_id) {
      const { data: drv } = await supabase.from("drivers").select("name").eq("id", record.driver_id).maybeSingle();
      ctx.motorista = drv?.name ?? null;
    }

    // 4) Monta e envia a notificação.
    const cfg = MENSAGENS[table] ?? {
      title: "FrotaCheck",
      body: () => "Nova atividade registrada na sua frota.",
    };

    const app = getFirebaseApp();
    const messaging = getMessaging(app);

    const resultados = await Promise.allSettled(
      tokens.map((t) =>
        messaging.send({
          token: t.fcm_token,
          notification: { title: cfg.title, body: cfg.body(record, ctx) },
          data: { table, record_id: String(record.id ?? "") },
        })
      ),
    );

    const falhas = resultados.filter((r) => r.status === "rejected").length;

    return new Response(
      JSON.stringify({ enviados: tokens.length - falhas, falhas }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("send-push-notification error:", e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
