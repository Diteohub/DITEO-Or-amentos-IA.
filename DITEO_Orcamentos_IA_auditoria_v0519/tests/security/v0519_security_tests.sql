BEGIN;

DO $$
DECLARE
    v_user_a UUID := gen_random_uuid();
    v_user_b UUID := gen_random_uuid();
    v_comp_a UUID := gen_random_uuid();
    v_comp_b UUID := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id, email) VALUES 
        (v_user_a, 'rls_a_' || v_user_a::text || '@diteo.local'),
        (v_user_b, 'rls_b_' || v_user_b::text || '@diteo.local');

    INSERT INTO public.companies (id, name) VALUES 
        (v_comp_a, 'Empresa A RLS'),
        (v_comp_b, 'Empresa B RLS');

    INSERT INTO public.company_members (company_id, user_id, role, active) VALUES 
        (v_comp_a, v_user_a, 'owner', TRUE),
        (v_comp_b, v_user_b, 'owner', TRUE);

    INSERT INTO public.customers (company_id, name, document) VALUES 
        (v_comp_a, 'Cliente Isolado A', '10000000001'),
        (v_comp_b, 'Cliente Isolado B', '20000000002');

    PERFORM set_config('app.test_user_a', v_user_a::text, true);
    PERFORM set_config('app.test_comp_a', v_comp_a::text, true);
    PERFORM set_config('app.test_comp_b', v_comp_b::text, true);
END $$;

SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', current_setting('app.test_user_a'), true);
SET ROLE authenticated;

DO $$
DECLARE
    v_comp_a UUID := current_setting('app.test_comp_a')::uuid;
    v_comp_b UUID := current_setting('app.test_comp_b')::uuid;
    v_qtd_a INT;
    v_qtd_b INT;
BEGIN
    SELECT COUNT(*) INTO v_qtd_a FROM public.customers WHERE company_id = v_comp_a;
    SELECT COUNT(*) INTO v_qtd_b FROM public.customers WHERE company_id = v_comp_b;

    IF v_qtd_a != 1 THEN
        RAISE EXCEPTION 'FALHA RLS (TESTE 1): Esperado 1 registro na Empresa A, retornado %.', v_qtd_a;
    END IF;
    IF v_qtd_b != 0 THEN
        RAISE EXCEPTION 'FALHA RLS (TESTE 1): Vazamento cross-tenant! Retornados % registros da Empresa B.', v_qtd_b;
    END IF;
END $$;

RESET ROLE;
ROLLBACK;
5.2 Testes 2 a 9 e 11 a 15 (Suíte SQL Repetível com Rollback)
BEGIN;

-- Teste 2: Rejeição específica de get_canonical_quote_snapshot sem associação à empresa
DO $$
DECLARE
    v_user_outro UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_cust UUID := gen_random_uuid();
    v_quote UUID := gen_random_uuid();
    v_msg TEXT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_user_outro, 'outro_' || v_user_outro::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 2');
    INSERT INTO public.customers (id, company_id, name) VALUES (v_cust, v_comp, 'Cliente Teste 2');
    INSERT INTO public.quotes (id, company_id, customer_id, quote_number, title) VALUES (v_quote, v_comp, v_cust, 1, 'Orçamento Teste 2');

    PERFORM set_config('request.jwt.claim.sub', v_user_outro::text, true);

    BEGIN
        PERFORM public.get_canonical_quote_snapshot(v_comp, v_quote);
        RAISE EXCEPTION 'FALHA TESTE 2: Deveria ter bloqueado usuário sem vínculo.';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF position('Acesso negado' in v_msg) = 0 THEN
            RAISE EXCEPTION 'FALHA TESTE 2: Mensagem inesperada: %', v_msg;
        END IF;
    END;
END $$;

-- Teste 3: Proteção do último owner ativo
DO $$
DECLARE
    v_owner UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_msg TEXT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_owner, 'owner_' || v_owner::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 3');
    INSERT INTO public.company_members (company_id, user_id, role, active) VALUES (v_comp, v_owner, 'owner', TRUE);

    BEGIN
        DELETE FROM public.company_members WHERE company_id = v_comp AND user_id = v_owner;
        RAISE EXCEPTION 'FALHA TESTE 3: Remoção do último owner não foi bloqueada.';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF position('ao menos um proprietário ativo' in v_msg) = 0 THEN
            RAISE EXCEPTION 'FALHA TESTE 3: Mensagem inesperada: %', v_msg;
        END IF;
    END;
END $$;

-- Teste 4: Imutabilidade comercial de orçamento emitido (sent)
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_cust UUID := gen_random_uuid();
    v_quote UUID := gen_random_uuid();
    v_msg TEXT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'sent_' || v_usr::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 4');
    INSERT INTO public.customers (id, company_id, name) VALUES (v_cust, v_comp, 'Cliente Teste 4');
    INSERT INTO public.quotes (id, company_id, customer_id, created_by, quote_number, title, status)
    VALUES (v_quote, v_comp, v_cust, v_usr, 1, 'Orçamento Sent', 'sent');

    BEGIN
        UPDATE public.quotes SET sale_total = 9999.00 WHERE id = v_quote;
        RAISE EXCEPTION 'FALHA TESTE 4: Alteração em orçamento sent não foi bloqueada.';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF position('imutável' in v_msg) = 0 AND position('proibida' in v_msg) = 0 THEN
            RAISE EXCEPTION 'FALHA TESTE 4: Mensagem inesperada: %', v_msg;
        END IF;
    END;
END $$;

-- Teste 5: Transição válida de estados (draft -> review)
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_cust UUID := gen_random_uuid();
    v_quote UUID := gen_random_uuid();
    v_status TEXT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'st_' || v_usr::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 5');
    INSERT INTO public.company_members (company_id, user_id, role, active) VALUES (v_comp, v_usr, 'sales', TRUE);
    INSERT INTO public.customers (id, company_id, name) VALUES (v_cust, v_comp, 'Cliente Teste 5');
    INSERT INTO public.quotes (id, company_id, customer_id, created_by, quote_number, title, status, sale_total)
    VALUES (v_quote, v_comp, v_cust, v_usr, 1, 'Orçamento Draft', 'draft', 2000.00);

    PERFORM set_config('request.jwt.claim.sub', v_usr::text, true);
    PERFORM public.transition_quote_status(v_comp, v_quote, 'review');

    SELECT status INTO v_status FROM public.quotes WHERE id = v_quote;
    IF v_status != 'review' THEN
        RAISE EXCEPTION 'FALHA TESTE 5: Status esperado era review, obtido %.', v_status;
    END IF;
END $$;

-- Teste 6: Invalidação cadastral via RPC update_customer
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_cust UUID := gen_random_uuid();
    v_quote UUID := gen_random_uuid();
    v_ver_status TEXT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'inv_' || v_usr::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 6');
    INSERT INTO public.company_settings (company_id) VALUES (v_comp);
    INSERT INTO public.company_members (company_id, user_id, role, active) VALUES (v_comp, v_usr, 'sales', TRUE);
    INSERT INTO public.customers (id, company_id, name) VALUES (v_cust, v_comp, 'Cliente Antes');
    INSERT INTO public.quotes (id, company_id, customer_id, created_by, quote_number, title, status)
    VALUES (v_quote, v_comp, v_cust, v_usr, 1, 'Orçamento Inv', 'review');
    INSERT INTO public.quote_versions (company_id, quote_id, version_number, status, snapshot, pdf_path)
    VALUES (v_comp, v_quote, 1, 'stored', '{}'::jsonb, v_comp::text || '/quotes/' || v_quote::text || '/version_1.pdf');

    PERFORM set_config('request.jwt.claim.sub', v_usr::text, true);
    PERFORM public.update_customer(v_comp, v_cust, 'Cliente Depois', '999', 'd@d.local', '51999990000', '{}'::jsonb, NULL);

    SELECT status INTO v_ver_status FROM public.quote_versions WHERE quote_id = v_quote AND version_number = 1;
    IF v_ver_status != 'invalidated' THEN
        RAISE EXCEPTION 'FALHA TESTE 6: Versão não foi invalidada (status=%).', v_ver_status;
    END IF;
END $$;

-- Teste 7: Auditoria real de exceção de margem (< 10%) com item real e desconto
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_cust UUID := gen_random_uuid();
    v_quote UUID := gen_random_uuid();
    v_exc_qtd INT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'mrg_' || v_usr::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 7');
    INSERT INTO public.company_settings (company_id, default_margin, tax_config)
    VALUES (v_comp, 0.3500, '{"tax_rate": 0.06, "commission_rate": 0.05}'::jsonb);
    INSERT INTO public.company_members (company_id, user_id, role, active) VALUES (v_comp, v_usr, 'manager', TRUE);
    INSERT INTO public.customers (id, company_id, name) VALUES (v_cust, v_comp, 'Cliente Teste 7');
    INSERT INTO public.quotes (id, company_id, customer_id, created_by, quote_number, title, status, applied_tax_rate, applied_commission_rate, applied_margin)
    VALUES (v_quote, v_comp, v_cust, v_usr, 1, 'Orçamento Margem', 'draft', 0.06, 0.05, 0.3500);

    INSERT INTO public.quote_items (company_id, quote_id, description, unit, quantity, unit_cost, unit_sale_price, total_cost, total_sale, position)
    VALUES (v_comp, v_quote, 'Cabo e Disjuntor', 'UN', 1, 700.00, 1000.00, 700.00, 1000.00, 1);

    PERFORM set_config('request.jwt.claim.sub', v_usr::text, true);
    PERFORM public.update_quote_discount(v_comp, v_quote, 200.00, 'Desconto negociado para fechamento de obra.');

    SELECT COUNT(*) INTO v_exc_qtd FROM public.margin_exceptions WHERE quote_id = v_quote AND user_id = v_usr;
    IF v_exc_qtd != 1 THEN
        RAISE EXCEPTION 'FALHA TESTE 7: Esperado 1 registro em margin_exceptions, obtido %.', v_exc_qtd;
    END IF;
END $$;

-- Teste 8: Rejeição de NaN e Infinity via Check Constraints
DO $$
DECLARE
    v_comp UUID := gen_random_uuid();
    v_code TEXT;
BEGIN
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 8');
    BEGIN
        INSERT INTO public.catalog_items (company_id, type, name, purchase_cost)
        VALUES (v_comp, 'material', 'Item Inválido', 'Infinity'::numeric);
        RAISE EXCEPTION 'FALHA TESTE 8: Infinity não deveria ser aceito.';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_code = RETURNED_SQLSTATE;
        IF v_code != '23514' THEN
            RAISE EXCEPTION 'FALHA TESTE 8: SQLSTATE inesperado %.', v_code;
        END IF;
    END;
END $$;

-- Teste 9: Validação detalhada de RLS e operações/condições nas 13 tabelas da migration
DO $$
DECLARE
    v_tables TEXT[] := ARRAY[
        'companies', 'company_members', 'customers', 'suppliers',
        'catalog_items', 'price_history', 'quotes', 'quote_items',
        'quote_counters', 'company_settings', 'quote_versions',
        'margin_exceptions', 'audit_logs'
    ];
    v_tbl TEXT;
    v_rls BOOLEAN;
    v_has_select BOOLEAN;
    v_has_cond BOOLEAN;
BEGIN
    FOREACH v_tbl IN ARRAY v_tables LOOP
        SELECT rowsecurity INTO v_rls
        FROM pg_tables
        WHERE schemaname = 'public' AND tablename = v_tbl;

        IF v_rls IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION 'FALHA TESTE 9: RLS desabilitado em public.%', v_tbl;
        END IF;

        SELECT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'public' AND tablename = v_tbl AND cmd = 'SELECT'
        ) INTO v_has_select;

        IF NOT v_has_select THEN
            RAISE EXCEPTION 'FALHA TESTE 9: Política SELECT ausente em public.%', v_tbl;
        END IF;

        SELECT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'public' AND tablename = v_tbl
              AND (qual IS NOT NULL OR with_check IS NOT NULL)
        ) INTO v_has_cond;

        IF NOT v_has_cond THEN
            RAISE EXCEPTION 'FALHA TESTE 9: Política sem condição qual/with_check em public.%', v_tbl;
        END IF;
    END LOOP;

    -- Conferência específica de operações de escrita em tabelas com políticas diretas
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'customers' AND cmd = 'INSERT')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'customers' AND cmd = 'DELETE') THEN
        RAISE EXCEPTION 'FALHA TESTE 9: Políticas INSERT/DELETE esperadas em customers não encontradas.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'suppliers' AND cmd = 'UPDATE')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'suppliers' AND cmd = 'DELETE') THEN
        RAISE EXCEPTION 'FALHA TESTE 9: Políticas UPDATE/DELETE esperadas em suppliers não encontradas.';
    END IF;
END $$;

-- Teste 11: Rejeição específica de hash SHA-256 inválido
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_msg TEXT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'hsh_' || v_usr::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 11');
    INSERT INTO public.company_members (company_id, user_id, role, active) VALUES (v_comp, v_usr, 'sales', TRUE);

    BEGIN
        PERFORM public.confirm_quote_version_stored(v_comp, gen_random_uuid(), 1, 'abc123', v_usr);
        RAISE EXCEPTION 'FALHA TESTE 11: Hash curto deveria ser rejeitado.';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF position('SHA-256' in v_msg) = 0 THEN
            RAISE EXCEPTION 'FALHA TESTE 11: Mensagem inesperada: %', v_msg;
        END IF;
    END;
END $$;

-- Teste 12: Numeração sequencial por empresa
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_cust UUID := gen_random_uuid();
    v_n1 BIGINT;
    v_n2 BIGINT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'seq_' || v_usr::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 12');
    INSERT INTO public.company_settings (company_id) VALUES (v_comp);
    INSERT INTO public.quote_counters (company_id, next_number) VALUES (v_comp, 1);
    INSERT INTO public.company_members (company_id, user_id, role, active) VALUES (v_comp, v_usr, 'sales', TRUE);
    INSERT INTO public.customers (id, company_id, name) VALUES (v_cust, v_comp, 'Cliente Teste 12');

    PERFORM set_config('request.jwt.claim.sub', v_usr::text, true);
    SELECT quote_number INTO v_n1 FROM public.create_quote_with_number(v_comp, v_cust, 'Q1');
    SELECT quote_number INTO v_n2 FROM public.create_quote_with_number(v_comp, v_cust, 'Q2');

    IF v_n1 != 1 OR v_n2 != 2 THEN
        RAISE EXCEPTION 'FALHA TESTE 12: Esperado 1 e 2, obtido % e %.', v_n1, v_n2;
    END IF;
END $$;

-- Teste 13: Bootstrap completo de empresa
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID;
    v_role TEXT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'boot_' || v_usr::text || '@diteo.local');
    PERFORM set_config('request.jwt.claim.sub', v_usr::text, true);

    v_comp := public.bootstrap_company('Empresa Boot Teste 13');
    SELECT role INTO v_role FROM public.company_members WHERE company_id = v_comp AND user_id = v_usr AND active = TRUE;

    IF v_comp IS NULL OR v_role IS DISTINCT FROM 'owner' THEN
        RAISE EXCEPTION 'FALHA TESTE 13: Bootstrap inválido (comp=%, role=%).', v_comp, v_role;
    END IF;
END $$;

-- Teste 14: Exclusão de empresa mantém audit_logs com company_id NULL
DO $$
DECLARE
    v_comp UUID := gen_random_uuid();
    v_log UUID;
    v_cid UUID;
BEGIN
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 14');
    INSERT INTO public.audit_logs (company_id, operation, table_name) VALUES (v_comp, 'INSERT', 'companies') RETURNING id INTO v_log;

    DELETE FROM public.companies WHERE id = v_comp;

    SELECT company_id INTO v_cid FROM public.audit_logs WHERE id = v_log;
    IF NOT FOUND OR v_cid IS NOT NULL THEN
        RAISE EXCEPTION 'FALHA TESTE 14: company_id em audit_logs deveria ser NULL, obtido %.', v_cid;
    END IF;
END $$;

-- Teste 15: Imutabilidade de margin_exceptions (6 colunas e 6 valores explícitos no INSERT em quotes)
DO $$
DECLARE
    v_usr UUID := gen_random_uuid();
    v_comp UUID := gen_random_uuid();
    v_cust UUID := gen_random_uuid();
    v_quote UUID := gen_random_uuid();
    v_exc UUID;
    v_msg TEXT;
BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_usr, 'exc_' || v_usr::text || '@diteo.local');
    INSERT INTO public.companies (id, name) VALUES (v_comp, 'Empresa Teste 15');
    INSERT INTO public.customers (id, company_id, name) VALUES (v_cust, v_comp, 'Cliente Teste 15');
    INSERT INTO public.quotes (id, company_id, customer_id, created_by, quote_number, title)
    VALUES (v_quote, v_comp, v_cust, v_usr, 1, 'Orçamento Exc');

    INSERT INTO public.margin_exceptions (company_id, quote_id, user_id, resulting_margin, minimum_margin, justification)
    VALUES (v_comp, v_quote, v_usr, 0.0400, 0.1000, 'Justificativa gerencial válida.')
    RETURNING id INTO v_exc;

    BEGIN
        UPDATE public.margin_exceptions SET justification = 'Alteração proibida.' WHERE id = v_exc;
        RAISE EXCEPTION 'FALHA TESTE 15: UPDATE em margin_exceptions não deveria ocorrer.';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF position('imutáveis' in v_msg) = 0 THEN
            RAISE EXCEPTION 'FALHA TESTE 15: Mensagem inesperada: %', v_msg;
        END IF;
    END;
END $$;

ROLLBACK;
