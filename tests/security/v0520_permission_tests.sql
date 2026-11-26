-- Testes adicionais v0.5.20 — permissões de leitura sensível e escrita
-- Executar após aplicar a migration v0.5.20 em banco Supabase local/de teste.
BEGIN;

DO $$
DECLARE
  item RECORD;
BEGIN
  FOR item IN
    SELECT * FROM (VALUES
      ('quotes','total_cost'),
      ('quotes','estimated_profit'),
      ('quotes','applied_tax_rate'),
      ('quotes','applied_commission_rate'),
      ('quotes','applied_margin'),
      ('quote_items','unit_cost'),
      ('quote_items','total_cost'),
      ('catalog_items','purchase_cost'),
      ('catalog_items','labor_cost'),
      ('price_history','purchase_price'),
      ('quote_versions','snapshot'),
      ('company_settings','tax_config'),
      ('company_settings','default_margin')
    ) AS sensitive(table_name, column_name)
  LOOP
    IF has_column_privilege('authenticated', format('public.%I', item.table_name), item.column_name, 'SELECT') THEN
      RAISE EXCEPTION 'FALHA v0.5.20: authenticated ainda pode ler %.%', item.table_name, item.column_name;
    END IF;
  END LOOP;

  IF has_table_privilege('authenticated', 'public.catalog_items', 'DELETE') THEN
    RAISE EXCEPTION 'FALHA v0.5.20: DELETE físico de catalog_items continua concedido.';
  END IF;
  IF has_table_privilege('authenticated', 'public.price_history', 'UPDATE') OR
     has_table_privilege('authenticated', 'public.price_history', 'DELETE') THEN
    RAISE EXCEPTION 'FALHA v0.5.20: UPDATE/DELETE de price_history continua concedido.';
  END IF;
END $$;

ROLLBACK;
