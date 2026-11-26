// Edge Function: confirm-proposal-pdf (v0.5.20)
// Confirma um PDF pendente após validar JWT, autorização, caminho, tamanho e SHA-256.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.0";

const MAX_PDF_SIZE_BYTES = 10 * 1024 * 1024;
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function readLimitedBody(response: Response, maxBytes: number): Promise<Uint8Array> {
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new Error("PDF_TOO_LARGE");
  }
  if (!response.body) throw new Error("EMPTY_BODY");

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel();
        throw new Error("PDF_TOO_LARGE");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Token de autorização ausente" }, 401);

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json({ error: "Corpo JSON inválido" }, 400);
    }

    const { company_id, quote_id, version_number } = body;
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (
      typeof company_id !== "string" || !uuidRegex.test(company_id) ||
      typeof quote_id !== "string" || !uuidRegex.test(quote_id) ||
      typeof version_number !== "number" || !Number.isSafeInteger(version_number) || version_number <= 0
    ) return json({ error: "Parâmetros de entrada inválidos" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceKey) {
      console.error("Variáveis obrigatórias da Edge Function não configuradas.");
      return json({ error: "Serviço indisponível" }, 503);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return json({ error: "Usuário não autenticado" }, 401);

    const { data: hasAccess, error: accessError } = await userClient.rpc("has_min_role", {
      target_company: company_id,
      min_role: "sales",
    });
    if (accessError || !hasAccess) return json({ error: "Acesso negado" }, 403);

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: version, error: versionError } = await admin
      .from("quote_versions")
      .select("pdf_path, status")
      .eq("company_id", company_id)
      .eq("quote_id", quote_id)
      .eq("version_number", version_number)
      .maybeSingle();

    if (versionError || !version || version.status !== "pending" || !version.pdf_path) {
      return json({ error: "Versão pendente não encontrada" }, 404);
    }

    const expectedPath = `${company_id}/quotes/${quote_id}/version_${version_number}.pdf`;
    if (version.pdf_path !== expectedPath) return json({ error: "Caminho canônico inválido" }, 403);

    // URL assinada privada; fetch com leitura limitada evita materializar arquivo ilimitado.
    const { data: signed, error: signedError } = await admin.storage
      .from("proposals")
      .createSignedUrl(version.pdf_path, 60);
    if (signedError || !signed?.signedUrl) return json({ error: "Erro ao acessar arquivo no Storage" }, 404);

    const fileResponse = await fetch(signed.signedUrl);
    if (!fileResponse.ok) return json({ error: "Erro ao baixar arquivo do Storage" }, 404);

    let bytes: Uint8Array;
    try {
      bytes = await readLimitedBody(fileResponse, MAX_PDF_SIZE_BYTES);
    } catch (error) {
      if (error instanceof Error && error.message === "PDF_TOO_LARGE") {
        return json({ error: "Arquivo excede o limite máximo de 10 MB" }, 413);
      }
      throw error;
    }

    if (bytes.byteLength < 5 || new TextDecoder().decode(bytes.subarray(0, 5)) !== "%PDF-") {
      return json({ error: "Formato de arquivo inválido" }, 400);
    }

    const digest = await crypto.subtle.digest("SHA-256", bytes);
    const sha256 = Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");

    const { error: rpcError } = await admin.rpc("confirm_quote_version_stored", {
      p_company_id: company_id,
      p_quote_id: quote_id,
      p_version_number: version_number,
      p_verified_backend_sha256: sha256,
      p_actor_user_id: user.id,
    });
    if (rpcError) {
      console.error("Confirmação atômica recusada:", rpcError.message);
      return json({ error: "Falha na confirmação atômica" }, 409);
    }

    return json({ success: true, verified_sha256: sha256 });
  } catch (error) {
    console.error("Erro interno em confirm-proposal-pdf:", error);
    return json({ error: "Erro interno na Edge Function" }, 500);
  }
});
