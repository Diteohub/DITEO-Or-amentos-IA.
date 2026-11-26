# Variáveis do ambiente Supabase de teste (substituir pelos valores reais)
SUPABASE_URL="http://127.0.0.1:54321"
USER_JWT="<JWT_DO_USUARIO_SALES_MEMBER>"
COMPANY_ID="<UUID_EMPRESA>"
QUOTE_ID="<UUID_ORCAMENTO_EM_REVIEW>"
VERSION_NUM=1
PDF_PATH="${COMPANY_ID}/quotes/${QUOTE_ID}/version_${VERSION_NUM}.pdf"
TMP_PDF="/tmp/proposta_teste_0519.pdf"

# 1. Gera PDF válido e calcula SHA-256 local dos bytes reais
printf '%%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%%%EOF\n' > "$TMP_PDF"
LOCAL_SHA256=$(sha256sum "$TMP_PDF" | awk '{print $1}')

# 2. Upload efetivo do arquivo binário no bucket privado 'proposals'
curl -sS -X POST "${SUPABASE_URL}/storage/v1/object/proposals/${PDF_PATH}" \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/pdf" \
  --data-binary "@${TMP_PDF}"

# 3. Invoca a Edge Function (que baixa os bytes reais do Storage, valida %PDF-, calcula SHA-256 e chama a RPC)
RESP=$(curl -sS -X POST "${SUPABASE_URL}/functions/v1/confirm-proposal-pdf" \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/json" \
  -d "{\"company_id\":\"${COMPANY_ID}\",\"quote_id\":\"${QUOTE_ID}\",\"version_number\":${VERSION_NUM}}")

echo "Resposta Edge Function: $RESP"
# Conferir no retorno que verified_sha256 == $LOCAL_SHA256 e que quote_versions.pdf_hash == $LOCAL_SHA256

# 4. Limpeza do objeto de teste no Storage
curl -sS -X DELETE "${SUPABASE_URL}/storage/v1/object/proposals/${PDF_PATH}" \
  -H "Authorization: Bearer ${USER_JWT}"
rm -f "$TMP_PDF"
