-- DITEO Orçamentos IA — v0.5.20
-- Restringe leitura direta de campos financeiros internos.
-- Os campos removidos da leitura direta devem ser consumidos por RPCs autorizadas
-- ou por operações server-side; não expor por views SECURITY DEFINER sem autorização.

BEGIN;

-- Orçamentos: permitir dados comerciais, não custos, lucro ou taxas internas.
REVOKE SELECT ON public.quotes FROM authenticated;
GRANT SELECT (
  id, company_id, customer_id, created_by, quote_number, title, description,
  status, valid_until, subtotal, discount, tax_amount, sale_total, created_at, updated_at
) ON public.quotes TO authenticated;

-- Itens: ocultar custos unitários/totais; manter descrição e valores comerciais.
REVOKE SELECT ON public.quote_items FROM authenticated;
GRANT SELECT (
  id, company_id, quote_id, catalog_item_id, description, unit, quantity,
  unit_sale_price, total_sale, position
) ON public.quote_items TO authenticated;

-- Catálogo: custo de compra e mão de obra não ficam disponíveis por SELECT direto.
REVOKE SELECT ON public.catalog_items FROM authenticated;
GRANT SELECT (
  id, company_id, type, code, name, description, unit, active, deleted_at, created_at
) ON public.catalog_items TO authenticated;

-- Histórico de preços: preço de compra restrito a operações internas/RPCs.
REVOKE SELECT ON public.price_history FROM authenticated;
GRANT SELECT (
  id, company_id, catalog_item_id, supplier_id, quantity, purchase_date,
  invoice_reference, created_at
) ON public.price_history TO authenticated;

-- Versões: o snapshot pode conter custos e margens; não liberar sua leitura direta.
REVOKE SELECT ON public.quote_versions FROM authenticated;
GRANT SELECT (
  id, company_id, quote_id, version_number, status, issued_at, issued_by
) ON public.quote_versions TO authenticated;

-- Configurações: ocultar configuração tributária e margem padrão do acesso direto.
REVOKE SELECT ON public.company_settings FROM authenticated;
GRANT SELECT (
  id, company_id, currency, payment_terms, proposal_template, created_at
) ON public.company_settings TO authenticated;

-- Catálogo usa exclusão lógica (active/deleted_at); remover DELETE físico.
REVOKE DELETE ON public.catalog_items FROM authenticated;

-- Histórico de compra é trilha histórica: somente INSERT, sem UPDATE/DELETE direto.
REVOKE UPDATE, DELETE ON public.price_history FROM authenticated;

COMMIT;
