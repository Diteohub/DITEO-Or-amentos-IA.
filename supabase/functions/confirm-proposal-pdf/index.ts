// =========================================================================
// Edge Function: confirm-proposal-pdf (v0.5.19 - Deno Runtime)
// =========================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.0"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_PDF_SIZE_BYTES = 10 * 1024 * 1024; // 10 MB

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Método não permitido' }), { 
        status: 405, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Token de autorização ausente' }), { 
        status: 401, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const body = await req.json().catch(() => ({}))
    const { company_id, quote_id, version_number } = body
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

    if (!company_id || !uuidRegex.test(company_id) || !quote_id || !uuidRegex.test(quote_id) || typeof version_number !== 'number' || !Number.isInteger(version_number) || version_number <= 0) {
      return new Response(JSON.stringify({ error: 'Parâmetros de entrada inválidos (version_number deve ser inteiro positivo)' }), { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const supabaseUserClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: userError } = await supabaseUserClient.auth.getUser()
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Usuário não autenticado' }), { 
        status: 401, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const { data: hasAccess, error: accessError } = await supabaseUserClient.rpc('has_min_role', {
      target_company: company_id,
      min_role: 'sales'
    })

    if (accessError || !hasAccess) {
      return new Response(JSON.stringify({ error: 'Acesso negado: Associação inválida ou papel insuficiente' }), { 
        status: 403, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { data: versionData, error: versionError } = await supabaseAdmin
      .from('quote_versions')
      .select('pdf_path, status')
      .eq('company_id', company_id)
      .eq('quote_id', quote_id)
      .eq('version_number', version_number)
      .single()

    if (versionError || !versionData || versionData.status !== 'pending' || !versionData.pdf_path) {
      return new Response(JSON.stringify({ error: 'Versão pendente não encontrada' }), { 
        status: 404, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const canonicalPdfPath = versionData.pdf_path
    const expectedPrefix = `${company_id}/quotes/${quote_id}/`
    if (!canonicalPdfPath.startsWith(expectedPrefix) || !canonicalPdfPath.endsWith('.pdf')) {
      return new Response(JSON.stringify({ error: 'Caminho canônico inválido' }), { 
        status: 403, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const { data: fileData, error: downloadError } = await supabaseAdmin.storage
      .from('proposals')
      .download(canonicalPdfPath)

    if (downloadError || !fileData) {
      return new Response(JSON.stringify({ error: 'Erro ao baixar arquivo do Storage' }), { 
        status: 404, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const fileBuffer = await fileData.arrayBuffer()

    if (fileBuffer.byteLength > MAX_PDF_SIZE_BYTES) {
      return new Response(JSON.stringify({ error: 'Arquivo excede o limite máximo permitido de 10MB' }), { 
        status: 413, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const headerBytes = new Uint8Array(fileBuffer.slice(0, 5))
    const pdfMagicHeader = new TextDecoder().decode(headerBytes)
    if (!pdfMagicHeader.startsWith('%PDF-')) {
      return new Response(JSON.stringify({ error: 'Formato de arquivo inválido: O arquivo não é um PDF legítimo' }), { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    const hashBuffer = await crypto.subtle.digest('SHA-256', fileBuffer)
    const hashArray = Array.from(new Uint8Array(hashBuffer))
    const realSha256 = hashArray.map(b => b.toString(16).padStart(2, '0')).join('')

    // user.id extraído exclusivamente do JWT validado via getUser(), nunca do body
    const { error: rpcError } = await supabaseAdmin.rpc('confirm_quote_version_stored', {
      p_company_id: company_id,
      p_quote_id: quote_id,
      p_version_number: version_number,
      p_verified_backend_sha256: realSha256,
      p_actor_user_id: user.id
    })

    if (rpcError) {
      return new Response(JSON.stringify({ error: 'Falha na confirmação atômica (autorização revogada ou conflito de estado)' }), { 
        status: 403, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    return new Response(JSON.stringify({ success: true, verified_sha256: realSha256 }), { 
      status: 200, 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    })

  } catch {
    return new Response(JSON.stringify({ error: 'Erro interno na Edge Function' }), { 
      status: 500, 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    })
  }
})
