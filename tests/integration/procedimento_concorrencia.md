Passo 1: Preparação da Massa e Obtenção dos IDs
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_cust UUID := gen_random_uuid();
    v_quote UUID := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'conc_' || v_usr::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Concorrência v0.5.19');
    INSERT INTO public.company_settings (company_id) VALUES (v_comp);
    INSERT INTO public.company_members (company_id, user_id, role, active) VALUES (v_comp, v_usr, 'sales', TRUE);
    INSERT INTO public.customers (id, company_id, name) VALUES (v_cust, v_comp, 'Cliente Inicial');
    INSERT INTO public.quotes (id, company_id, customer_id, created_by, quote_number, title, status, sale_total)
    VALUES (v_quote, v_comp, v_cust, v_usr, 1, 'Orçamento Concorrência', 'review', 2500.00);
    INSERT INTO public.quote_items (company_id, quote_id, description, unit, quantity, unit_cost, unit_sale_price, total_cost, total_sale, position)
    VALUES (v_comp, v_quote, 'Serviço Base', 'UN', 1, 1000.00, 2500.00, 1000.00, 2500.00, 1);

    RAISE NOTICE 'USER_ID=% | COMP_ID=% | CUST_ID=% | QUOTE_ID=%', v_usr, v_comp, v_cust, v_quote;
END $$;
Passo 2: Sessão 1 (Conexão A — Inicia Transação, Emite Versão e Mantém Locks Abertos)
BEGIN;
SELECT pg_backend_pid() AS sessao_1_pid;
SELECT set_config('request.jwt.claim.sub', '<USER_ID>', true);
SELECT * FROM public.emit_quote_version('<COMP_ID>'::uuid, '<QUOTE_ID>'::uuid);
-- NÃO EXECUTAR COMMIT AINDA: a transação mantém os locks adquiridos em companies, settings, customers e quotes.
Passo 3: Sessão 2 (Conexão B — Inicia Após a Sessão 1 Executar emit_quote_version)
BEGIN;
SELECT pg_backend_pid() AS sessao_2_pid;
SELECT set_config('request.jwt.claim.sub', '<USER_ID>', true);
-- Esta chamada ficará aguardando o lock da Sessão 1 enquanto a Sessão 1 estiver aberta
SELECT public.update_customer(
    '<COMP_ID>'::uuid,
    '<CUST_ID>'::uuid,
    'Cliente Atualizado Concorrência',
    '11223344000155',
    'conc@diteo.local',
    '51988880000',
    '{"bairro":"Centro"}'::jsonb,
    'Atualização concorrente'
);
Passo 4: Comprovação Operacional de Que a Sessão 2 Está Bloqueada Pela Sessão 1
Em uma terceira consulta de inspeção antes do COMMIT da Sessão 1:
SELECT pid, state, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE pid IN (<SESSAO_1_PID>, <SESSAO_2_PID>);
•	Confirmação: A Sessao_2 aparece com wait_event_type = 'Lock' aguardando o lock retido pela Sessao_1.
•	Em seguida, execute COMMIT; na Sessão 1, e depois execute COMMIT; na Sessão 2.
Passo 5: Consultas Finais de Verificação
-- 1. Estado da versão emitida na Sessão 1 após a alteração cadastral na Sessão 2 (deve constar 'invalidated')
SELECT version_number, status, pdf_path
FROM public.quote_versions
WHERE quote_id = '<QUOTE_ID>'::uuid
ORDER BY version_number DESC;

-- 2. Atualização cadastral concluída na Sessão 2
SELECT id, name
FROM public.customers
WHERE id = '<CUST_ID>'::uuid;

-- 3. Confirmação de ausência de deadlocks registrados no banco
SELECT datname, deadlocks
FROM pg_stat_database
WHERE datname = current_database();
