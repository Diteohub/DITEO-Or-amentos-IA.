#!/usr/bin/env bash
# Teste real de Storage + Edge Function; somente Supabase local/isolado.
set -Eeuo pipefail
: "$SUPABASE_URL"
: "$USER_JWT"
: "$COMPANY_ID"
: "$QUOTE_ID"
VERSION_NUM="$VERSION_NUM"
if [[ "$SUPABASE_URL" != http://127.0.0.1:* && "$SUPABASE_URL" != http://localhost:* ]]; then echo "ERRO: use somente Supabase local." >&2; exit 2; fi
if [[ ! "$COMPANY_ID" =~ ^[0-9a-fA-F-]{36}$ || ! "$QUOTE_ID" =~ ^[0-9a-fA-F-]{36}$ || ! "$VERSION_NUM" =~ ^[1-9][0-9]*$ ]]; then echo "ERRO: IDs/versão inválidos." >&2; exit 2; fi
for cmd in curl jq sha256sum; do command -v "$cmd" >/dev/null || { echo "ERRO: $cmd não encontrado." >&2; exit 2; }; done
PDF_PATH="$COMPANY_ID/quotes/$QUOTE_ID/version_$VERSION_NUM.pdf"
TMP_DIR="$(mktemp -d)"
TMP_PDF="$TMP_DIR/proposal.pdf"
UPLOAD_DONE=0
cleanup() {
  local rc=$?
  if [[ "$UPLOAD_DONE" -eq 1 ]]; then
    curl --silent --show-error --fail-with-body -X DELETE "$SUPABASE_URL/storage/v1/object/proposals/$PDF_PATH" -H "Authorization: Bearer $USER_JWT" >/dev/null || { echo "AVISO: falha ao remover objeto de teste." >&2; rc=1; }
  fi
  rm -rf "$TMP_DIR"
  exit "$rc"
}
trap cleanup EXIT
printf '%%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%%%EOF\n' > "$TMP_PDF"
LOCAL_SHA256="$(sha256sum "$TMP_PDF" | awk '{print $1}')"
UPLOAD_STATUS="$(curl --silent --show-error --output "$TMP_DIR/upload.json" --write-out '%{http_code}' -X POST "$SUPABASE_URL/storage/v1/object/proposals/$PDF_PATH" -H "Authorization: Bearer $USER_JWT" -H "Content-Type: application/pdf" --data-binary "@$TMP_PDF")"
if [[ ! "$UPLOAD_STATUS" =~ ^2[0-9][0-9]$ ]]; then cat "$TMP_DIR/upload.json" >&2; echo "ERRO: upload HTTP $UPLOAD_STATUS." >&2; exit 1; fi
UPLOAD_DONE=1
FUNCTION_STATUS="$(curl --silent --show-error --output "$TMP_DIR/function.json" --write-out '%{http_code}' -X POST "$SUPABASE_URL/functions/v1/confirm-proposal-pdf" -H "Authorization: Bearer $USER_JWT" -H "Content-Type: application/json" -d "{\"company_id\":\"$COMPANY_ID\",\"quote_id\":\"$QUOTE_ID\",\"version_number\":$VERSION_NUM}")"
if [[ ! "$FUNCTION_STATUS" =~ ^2[0-9][0-9]$ ]]; then cat "$TMP_DIR/function.json" >&2; echo "ERRO: Edge Function HTTP $FUNCTION_STATUS." >&2; exit 1; fi
REMOTE_SHA256="$(jq -er '.verified_sha256 | strings' "$TMP_DIR/function.json")"
if [[ ! "$REMOTE_SHA256" =~ ^[0-9a-f]{64}$ || "$REMOTE_SHA256" != "$LOCAL_SHA256" ]]; then echo "ERRO: SHA-256 ausente, inválido ou divergente." >&2; cat "$TMP_DIR/function.json" >&2; exit 1; fi
echo "OK: upload HTTP $UPLOAD_STATUS; Edge Function HTTP $FUNCTION_STATUS; SHA-256 confere: $LOCAL_SHA256"
