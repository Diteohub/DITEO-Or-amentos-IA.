-- DITEO Orçamentos IA — testes de privilégios em colunas v0.5.20.1
-- Executar em Supabase local/de teste após migrations v0.5.19 e v0.5.20.
-- Verifica privilégios SQL; não substitui testes RLS com usuários/JWTs reais.
BEGIN;
DO $$
DECLARE item RECORD;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('quotes','total_cost'),('quotes','estimated_profit'),('quotes','applied_tax_rate'),
    ('quotes','applied_commission_rate'),('quotes','applied_margin'),
    ('quote_items','unit_cost'),('quote_items','total_cost'),
    ('catalog_items','purchase_cost'),('catalog_items','labor_cost'),
    ('price_history','purchase_price'),('quote_versions','snapshot'),
    ('company_settings','tax_config'),('company_settings','default_margin')
  ) AS sensitive(table_name,column_name)
  LOOP
    IF has_column_privilege('authenticated',format('public.%I',item.table_name),item.column_name,'SELECT') THEN
      RAISE EXCEPTION 'FALHA: authenticated ainda pode ler %.%',item.table_name,item.column_name;
    END IF;
  END LOOP;
  FOR item IN SELECT * FROM (VALUES
    ('quotes','id'),('quotes','company_id'),('quotes','customer_id'),('quotes','quote_number'),
    ('quotes','title'),('quotes','status'),('quotes','sale_total'),
    ('quote_items','description'),('quote_items','quantity'),('quote_items','unit_sale_price'),
    ('quote_items','total_sale'),('catalog_items','name'),('catalog_items','type'),
    ('catalog_items','unit'),('quote_versions','version_number'),('quote_versions','status'),
    ('company_settings','currency'),('company_settings','payment_terms')
  ) AS allowed(table_name,column_name)
  LOOP
    IF NOT has_column_privilege('authenticated',format('public.%I',item.table_name),item.column_name,'SELECT') THEN
      RAISE EXCEPTION 'FALHA: authenticated perdeu leitura comercial em %.%',item.table_name,item.column_name;
    END IF;
  END LOOP;
  IF has_table_privilege('authenticated','public.catalog_items','DELETE') THEN
    RAISE EXCEPTION 'FALHA: DELETE físico de catalog_items continua concedido.';
  END IF;
  IF has_table_privilege('authenticated','public.price_history','UPDATE')
     OR has_table_privilege('authenticated','public.price_history','DELETE') THEN
    RAISE EXCEPTION 'FALHA: UPDATE/DELETE de price_history continua concedido.';
  END IF;
END $$;
ROLLBACK;
