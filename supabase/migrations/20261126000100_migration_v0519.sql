-- =========================================================================
-- DITEO Orçamentos IA - Migration Unificada v0.5.19 (Supabase Local - Produção)
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. TABELAS BASE (COM BLINDAGEM NUMÉRICA ESTRITA CONTRA NaN E INFINITOS)
CREATE TABLE public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    trade_name TEXT,
    document TEXT,
    email TEXT,
    phone TEXT,
    logo_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.company_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner','admin','manager','sales','technician','viewer')),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, user_id),
    UNIQUE (company_id, id)
);

CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    document TEXT,
    email TEXT,
    phone TEXT,
    address JSONB NOT NULL DEFAULT '{}',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, id)
);

CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    document TEXT,
    contact TEXT,
    phone TEXT,
    email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, id)
);

CREATE TABLE public.catalog_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('material','service')),
    code TEXT,
    name TEXT NOT NULL,
    description TEXT,
    unit TEXT NOT NULL DEFAULT 'UN',
    purchase_cost NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (purchase_cost >= 0 AND purchase_cost::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    labor_cost NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (labor_cost >= 0 AND labor_cost::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, id)
);

CREATE TABLE public.price_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    catalog_item_id UUID NOT NULL,
    supplier_id UUID,
    purchase_price NUMERIC(14,2) NOT NULL CHECK (purchase_price >= 0 AND purchase_price::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    quantity NUMERIC(14,3) NOT NULL CHECK (quantity > 0 AND quantity::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    purchase_date DATE NOT NULL DEFAULT CURRENT_DATE,
    invoice_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (company_id, catalog_item_id) REFERENCES public.catalog_items(company_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (company_id, supplier_id) REFERENCES public.suppliers(company_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.quotes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    customer_id UUID NOT NULL,
    created_by UUID REFERENCES auth.users(id),
    quote_number BIGINT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','review','sent','approved','rejected','expired','cancelled')),
    valid_until DATE,
    subtotal NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0 AND subtotal::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    discount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (discount >= 0 AND discount::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    total_cost NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_cost >= 0 AND total_cost::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0 AND tax_amount::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    sale_total NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (sale_total >= 0 AND sale_total::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    estimated_profit NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (estimated_profit::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    applied_tax_rate NUMERIC(7,4) NOT NULL DEFAULT 0.06 CHECK (applied_tax_rate >= 0 AND applied_tax_rate::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    applied_commission_rate NUMERIC(7,4) NOT NULL DEFAULT 0.05 CHECK (applied_commission_rate >= 0 AND applied_commission_rate::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    applied_margin NUMERIC(7,4) NOT NULL DEFAULT 0.3500 CHECK (applied_margin >= 0 AND applied_margin::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, quote_number),
    UNIQUE (company_id, id),
    FOREIGN KEY (company_id, customer_id) REFERENCES public.customers(company_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.quote_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    quote_id UUID NOT NULL,
    catalog_item_id UUID,
    description TEXT NOT NULL,
    unit TEXT NOT NULL,
    quantity NUMERIC(14,3) NOT NULL CHECK (quantity > 0 AND quantity::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    unit_cost NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0 AND unit_cost::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    unit_sale_price NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (unit_sale_price >= 0 AND unit_sale_price::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    total_cost NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_cost >= 0 AND total_cost::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    total_sale NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_sale >= 0 AND total_sale::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    position INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (company_id, quote_id) REFERENCES public.quotes(company_id, id) ON DELETE CASCADE,
    FOREIGN KEY (company_id, catalog_item_id) REFERENCES public.catalog_items(company_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.quote_counters (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    next_number BIGINT NOT NULL DEFAULT 1 CHECK (next_number > 0)
);

CREATE TABLE public.company_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL UNIQUE REFERENCES public.companies(id) ON DELETE CASCADE,
    currency TEXT NOT NULL DEFAULT 'BRL',
    tax_config JSONB NOT NULL DEFAULT '{"tax_rate": 0.06, "commission_rate": 0.05}' CHECK (
        jsonb_typeof(tax_config) = 'object' AND
        (tax_config ? 'tax_rate') AND
        (tax_config ? 'commission_rate') AND
        jsonb_typeof(tax_config->'tax_rate') = 'number' AND
        jsonb_typeof(tax_config->'commission_rate') = 'number' AND
        ((tax_config->>'tax_rate')::NUMERIC >= 0 AND (tax_config->>'tax_rate')::NUMERIC <= 1) AND
        ((tax_config->>'commission_rate')::NUMERIC >= 0 AND (tax_config->>'commission_rate')::NUMERIC <= 1)
    ),
    default_margin NUMERIC(7,4) NOT NULL DEFAULT 0.3500 CHECK (default_margin >= 0 AND default_margin < 0.8900 AND default_margin::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    payment_terms JSONB NOT NULL DEFAULT '{}',
    proposal_template JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.quote_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    quote_id UUID NOT NULL,
    version_number INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','stored','issued','invalidated')),
    snapshot JSONB NOT NULL,
    pdf_path TEXT,
    pdf_hash TEXT,
    issued_at TIMESTAMPTZ,
    issued_by UUID REFERENCES auth.users(id),
    UNIQUE (company_id, quote_id, version_number),
    FOREIGN KEY (company_id, quote_id) REFERENCES public.quotes(company_id, id) ON DELETE CASCADE
);

CREATE TABLE public.margin_exceptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    quote_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    resulting_margin NUMERIC(7,4) NOT NULL CHECK (resulting_margin::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    minimum_margin NUMERIC(7,4) NOT NULL DEFAULT 0.1000 CHECK (minimum_margin::text NOT IN ('NaN', 'Infinity', '-Infinity')),
    justification TEXT NOT NULL CHECK (length(trim(justification)) >= 10),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (company_id, quote_id) REFERENCES public.quotes(company_id, id) ON DELETE CASCADE
);

CREATE TABLE public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    user_id UUID,
    operation TEXT NOT NULL,
    table_name TEXT NOT NULL,
    record_id UUID,
    old_data JSONB,
    new_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. FUNÇÕES DE SUPORTE E SEGURANÇA
CREATE OR REPLACE FUNCTION public.is_company_member(target_company UUID)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.company_members cm
        WHERE cm.company_id = target_company AND cm.user_id = auth.uid() AND cm.active = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.has_min_role(target_company UUID, min_role TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT cm.role INTO v_role FROM public.company_members cm
    WHERE cm.company_id = target_company AND cm.user_id = auth.uid() AND cm.active = TRUE;

    IF v_role IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN CASE min_role
        WHEN 'viewer' THEN v_role IN ('viewer','technician','sales','manager','admin','owner')
        WHEN 'technician' THEN v_role IN ('technician','sales','manager','admin','owner')
        WHEN 'sales' THEN v_role IN ('sales','manager','admin','owner')
        WHEN 'manager' THEN v_role IN ('manager','admin','owner')
        WHEN 'admin' THEN v_role IN ('admin','owner')
        WHEN 'owner' THEN v_role = 'owner'
        ELSE FALSE
    END;
END;
$$;

-- 3. FUNÇÃO CANÔNICA DE SNAPSHOT
CREATE OR REPLACE FUNCTION public.get_canonical_quote_snapshot(p_company_id UUID, p_quote_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_snapshot JSONB;
    v_customer_id UUID;
BEGIN
    IF NOT public.is_company_member(p_company_id) THEN
        RAISE EXCEPTION 'Acesso negado: Usuário não pertence à empresa solicitada.';
    END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;

    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT jsonb_build_object(
        'company', (SELECT jsonb_build_object('name', c.name, 'trade_name', c.trade_name, 'document', c.document, 'email', c.email, 'phone', c.phone, 'logo_path', c.logo_path) FROM public.companies c WHERE c.id = p_company_id),
        'customer', (SELECT jsonb_build_object('name', cu.name, 'document', cu.document, 'email', cu.email, 'phone', cu.phone, 'address', cu.address) FROM public.customers cu WHERE cu.id = q.customer_id),
        'quote', jsonb_build_object(
            'id', q.id, 'number', q.quote_number, 'title', q.title, 'description', q.description, 'valid_until', q.valid_until,
            'subtotal', q.subtotal, 'discount', q.discount, 'tax_amount', q.tax_amount, 'sale_total', q.sale_total, 'estimated_profit', q.estimated_profit,
            'applied_tax_rate', q.applied_tax_rate, 'applied_commission_rate', q.applied_commission_rate, 'applied_margin', q.applied_margin
        ),
        'settings', (SELECT jsonb_build_object('currency', cs.currency, 'payment_terms', cs.payment_terms, 'proposal_template', cs.proposal_template) FROM public.company_settings cs WHERE cs.company_id = p_company_id),
        'items', (SELECT jsonb_agg(jsonb_build_object(
            'catalog_item_id', qi.catalog_item_id, 'description', qi.description, 'unit', qi.unit, 'quantity', qi.quantity,
            'unit_cost', qi.unit_cost, 'unit_sale_price', qi.unit_sale_price, 'total_cost', qi.total_cost, 'total_sale', qi.total_sale
        ) ORDER BY qi.position ASC, qi.id ASC) FROM public.quote_items qi WHERE qi.quote_id = p_quote_id)
    ) INTO v_snapshot
    FROM public.quotes q WHERE q.id = p_quote_id AND q.company_id = p_company_id;

    IF v_snapshot IS NULL OR (v_snapshot->'quote'->>'id') IS NULL THEN
        RAISE EXCEPTION 'Orçamento não encontrado ou snapshot comercial indisponível.';
    END IF;

    RETURN v_snapshot;
END;
$$;

-- 4. TRIGGER DE AUDITORIA ROBUSTA
CREATE OR REPLACE FUNCTION public.process_audit_log()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_company_id UUID;
    v_record_id UUID;
    v_new_json JSONB;
    v_old_json JSONB;
    v_company_exists BOOLEAN;
BEGIN
    IF TG_TABLE_NAME = 'companies' THEN
        v_company_id := COALESCE(NEW.id, OLD.id);
        v_record_id := COALESCE(NEW.id, OLD.id);
        IF TG_OP = 'DELETE' THEN v_company_exists := FALSE; ELSE v_company_exists := TRUE; END IF;
    ELSIF TG_TABLE_NAME = 'quote_counters' THEN
        v_company_id := COALESCE(NEW.company_id, OLD.company_id);
        v_record_id := COALESCE(NEW.company_id, OLD.company_id);
        SELECT EXISTS (SELECT 1 FROM public.companies WHERE id = v_company_id) INTO v_company_exists;
    ELSE
        v_company_id := COALESCE(NEW.company_id, OLD.company_id);
        v_record_id := COALESCE(NEW.id, OLD.id);
        SELECT EXISTS (SELECT 1 FROM public.companies WHERE id = v_company_id) INTO v_company_exists;
    END IF;

    IF NOT v_company_exists THEN
        v_company_id := NULL;
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_new_json := to_jsonb(NEW);
        INSERT INTO public.audit_logs (company_id, user_id, operation, table_name, record_id, new_data)
        VALUES (v_company_id, auth.uid(), TG_OP, TG_TABLE_NAME, v_record_id, v_new_json);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_json := to_jsonb(OLD);
        v_new_json := to_jsonb(NEW);
        INSERT INTO public.audit_logs (company_id, user_id, operation, table_name, record_id, old_data, new_data)
        VALUES (v_company_id, auth.uid(), TG_OP, TG_TABLE_NAME, v_record_id, v_old_json, v_new_json);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        v_old_json := to_jsonb(OLD);
        INSERT INTO public.audit_logs (company_id, user_id, operation, table_name, record_id, old_data)
        VALUES (v_company_id, auth.uid(), TG_OP, TG_TABLE_NAME, v_record_id, v_old_json);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER audit_companies_changes AFTER INSERT OR UPDATE OR DELETE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_members_changes AFTER INSERT OR UPDATE OR DELETE ON public.company_members FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_settings_changes AFTER INSERT OR UPDATE OR DELETE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_counters_changes AFTER INSERT OR UPDATE OR DELETE ON public.quote_counters FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_quotes_changes AFTER INSERT OR UPDATE OR DELETE ON public.quotes FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_quote_items_changes AFTER INSERT OR UPDATE OR DELETE ON public.quote_items FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_quote_versions_changes AFTER INSERT OR UPDATE OR DELETE ON public.quote_versions FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_customers_changes AFTER INSERT OR UPDATE OR DELETE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_catalog_changes AFTER INSERT OR UPDATE OR DELETE ON public.catalog_items FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_suppliers_changes AFTER INSERT OR UPDATE OR DELETE ON public.suppliers FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_prices_changes AFTER INSERT OR UPDATE OR DELETE ON public.price_history FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();
CREATE TRIGGER audit_margin_exceptions_changes AFTER INSERT OR UPDATE OR DELETE ON public.margin_exceptions FOR EACH ROW EXECUTE FUNCTION public.process_audit_log();

-- 5. FUNÇÃO CENTRALIZADA DE INVALIDAÇÃO CADASTRAL E RPCs DE ESCRITA SEGURA
CREATE OR REPLACE FUNCTION public.invalidate_quote_versions_for_company(p_company_id UUID, p_customer_id UUID DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    IF p_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = p_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE company_id = p_company_id AND status IN ('draft', 'review') FOR UPDATE;

    UPDATE public.quote_versions qv
    SET status = 'invalidated'
    FROM public.quotes q
    WHERE qv.quote_id = q.id 
      AND q.company_id = p_company_id 
      AND (p_customer_id IS NULL OR q.customer_id = p_customer_id)
      AND q.status IN ('draft', 'review') 
      AND qv.status IN ('pending', 'stored');
END;
$$;

CREATE OR REPLACE FUNCTION public.update_customer(
    p_company_id UUID, p_customer_id UUID, p_name TEXT, p_document TEXT, p_email TEXT, p_phone TEXT, p_address JSONB, p_notes TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NOT public.has_min_role(p_company_id, 'sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.customers WHERE id = p_customer_id AND company_id = p_company_id FOR UPDATE;

    UPDATE public.customers
    SET name = p_name, document = p_document, email = p_email, phone = p_phone, address = p_address, notes = p_notes
    WHERE id = p_customer_id AND company_id = p_company_id;

    PERFORM public.invalidate_quote_versions_for_company(p_company_id, p_customer_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_company_settings(
    p_company_id UUID, p_currency TEXT, p_tax_config JSONB, p_default_margin NUMERIC, p_payment_terms JSONB, p_proposal_template JSONB
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NOT public.has_min_role(p_company_id, 'admin') THEN RAISE EXCEPTION 'Acesso negado: Requer privilégio administrativo.'; END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;

    UPDATE public.company_settings
    SET currency = p_currency, tax_config = p_tax_config, default_margin = p_default_margin, payment_terms = p_payment_terms, proposal_template = p_proposal_template
    WHERE company_id = p_company_id;

    PERFORM public.invalidate_quote_versions_for_company(p_company_id, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_company_info(
    p_company_id UUID, p_name TEXT, p_trade_name TEXT, p_document TEXT, p_email TEXT, p_phone TEXT, p_logo_path TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NOT public.has_min_role(p_company_id, 'owner') THEN RAISE EXCEPTION 'Acesso negado: Requer privilégio de proprietário.'; END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;

    UPDATE public.companies
    SET name = p_name, trade_name = p_trade_name, document = p_document, email = p_email, phone = p_phone, logo_path = p_logo_path, updated_at = now()
    WHERE id = p_company_id;

    PERFORM public.invalidate_quote_versions_for_company(p_company_id, NULL);
END;
$$;

-- 6. BLINDAGENS DE ID, TENANT E IMUTABILIDADE
CREATE OR REPLACE FUNCTION public.prevent_company_id_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
        RAISE EXCEPTION 'Operação negada: A transferência de registro entre empresas (company_id) é proibida.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_company_pk_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'Operação negada: A alteração do identificador da empresa é proibida.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_margin_exception_modification()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION 'Operação negada: Registros de exceção de margem são imutáveis e não podem ser alterados ou excluídos.';
END;
$$;

CREATE TRIGGER trg_lock_margin_exceptions BEFORE UPDATE OR DELETE ON public.margin_exceptions FOR EACH ROW EXECUTE FUNCTION public.prevent_margin_exception_modification();

CREATE TRIGGER trg_lock_company_pk BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.prevent_company_pk_change();
CREATE TRIGGER trg_lock_company_id_customers BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();
CREATE TRIGGER trg_lock_company_id_suppliers BEFORE UPDATE ON public.suppliers FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();
CREATE TRIGGER trg_lock_company_id_catalog BEFORE UPDATE ON public.catalog_items FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();
CREATE TRIGGER trg_lock_company_id_prices BEFORE UPDATE ON public.price_history FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();
CREATE TRIGGER trg_lock_company_id_quotes BEFORE UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();
CREATE TRIGGER trg_lock_company_id_quote_items BEFORE UPDATE ON public.quote_items FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();
CREATE TRIGGER trg_lock_company_id_versions BEFORE UPDATE ON public.quote_versions FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();
CREATE TRIGGER trg_lock_company_id_settings BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();
CREATE TRIGGER trg_lock_company_id_members BEFORE UPDATE ON public.company_members FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();

-- 7. BOOTSTRAP E GESTÃO DE MEMBROS
CREATE OR REPLACE FUNCTION public.bootstrap_company(
    p_name TEXT,
    p_trade_name TEXT DEFAULT NULL,
    p_document TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_user_id UUID;
    v_company_id UUID;
    v_user_companies_count INT;
    v_clean_name TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Usuário não autenticado.'; END IF;

    v_clean_name := trim(COALESCE(p_name, ''));
    IF length(v_clean_name) < 2 THEN RAISE EXCEPTION 'O nome da empresa é obrigatório.'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

    SELECT COUNT(*) INTO v_user_companies_count
    FROM public.company_members cm
    JOIN public.companies c ON c.id = cm.company_id
    WHERE cm.user_id = v_user_id AND cm.role = 'owner' AND cm.active = TRUE;

    IF v_user_companies_count >= 3 THEN
        RAISE EXCEPTION 'Limite atingido: Máximo de 3 empresas ativas como proprietário.';
    END IF;

    INSERT INTO public.companies (name, trade_name, document)
    VALUES (v_clean_name, p_trade_name, p_document)
    RETURNING id INTO v_company_id;

    INSERT INTO public.quote_counters (company_id, next_number) VALUES (v_company_id, 1)
    ON CONFLICT (company_id) DO NOTHING;

    INSERT INTO public.company_settings (company_id) VALUES (v_company_id)
    ON CONFLICT (company_id) DO NOTHING;

    INSERT INTO public.company_members (company_id, user_id, role, active) 
    VALUES (v_company_id, v_user_id, 'owner', TRUE)
    ON CONFLICT (company_id, user_id) DO UPDATE SET active = TRUE;

    RETURN v_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.manage_company_member(
    p_company_id UUID,
    p_target_user_id UUID,
    p_role TEXT,
    p_active BOOLEAN
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_caller_role TEXT;
    v_target_current_role TEXT;
    v_member_id UUID;
BEGIN
    IF p_role NOT IN ('owner','admin','manager','sales','technician','viewer') THEN
        RAISE EXCEPTION 'Papel inválido.';
    END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;

    SELECT role INTO v_caller_role FROM public.company_members
    WHERE company_id = p_company_id AND user_id = auth.uid() AND active = TRUE;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('owner', 'admin') THEN
        RAISE EXCEPTION 'Acesso negado: Requer privilégio administrativo.';
    END IF;

    SELECT role INTO v_target_current_role FROM public.company_members
    WHERE company_id = p_company_id AND user_id = p_target_user_id;

    IF v_caller_role = 'admin' AND (p_role = 'owner' OR v_target_current_role = 'owner') THEN
        RAISE EXCEPTION 'Administradores não podem gerenciar proprietários.';
    END IF;

    INSERT INTO public.company_members (company_id, user_id, role, active)
    VALUES (p_company_id, p_target_user_id, p_role, p_active)
    ON CONFLICT (company_id, user_id) DO UPDATE
    SET role = EXCLUDED.role, active = EXCLUDED.active
    RETURNING id INTO v_member_id;

    RETURN v_member_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_owner_lockout()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_active_owners INT;
    v_target_company UUID;
BEGIN
    v_target_company := COALESCE(OLD.company_id, NEW.company_id);
    PERFORM 1 FROM public.companies WHERE id = v_target_company FOR UPDATE;

    IF (TG_OP = 'DELETE' AND OLD.role = 'owner' AND OLD.active = TRUE) OR
       (TG_OP = 'UPDATE' AND OLD.role = 'owner' AND (NEW.role != 'owner' OR NEW.active = FALSE)) THEN

        SELECT COUNT(*) INTO v_active_owners
        FROM public.company_members
        WHERE company_id = v_target_company AND role = 'owner' AND active = TRUE AND id != OLD.id;

        IF v_active_owners < 1 THEN
            RAISE EXCEPTION 'Operação negada: A empresa deve possuir ao menos um proprietário ativo.';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_last_owner BEFORE UPDATE OR DELETE ON public.company_members FOR EACH ROW EXECUTE FUNCTION public.prevent_owner_lockout();

-- 8. MOTOR FINANCEIRO E FUNÇÕES DE ORÇAMENTO
CREATE OR REPLACE FUNCTION public.recalculate_quote_totals(p_company_id UUID, p_quote_id UUID, p_justification TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_subtotal NUMERIC(14,2) := 0;
    v_total_cost NUMERIC(14,2) := 0;
    v_discount NUMERIC(14,2) := 0;
    v_sale_total NUMERIC(14,2) := 0;
    v_tax_amount NUMERIC(14,2) := 0;
    v_commission_amount NUMERIC(14,2) := 0;
    v_profit NUMERIC(14,2) := 0;
    v_applied_tax_rate NUMERIC(7,4);
    v_applied_commission_rate NUMERIC(7,4);
    v_applied_margin NUMERIC(7,4);
    v_min_net_margin NUMERIC(7,4) := 0.10;
    v_resulting_margin NUMERIC(7,4);
    v_caller_role TEXT;
    v_customer_id UUID;
BEGIN
    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT discount, applied_tax_rate, applied_commission_rate, applied_margin
    INTO v_discount, v_applied_tax_rate, v_applied_commission_rate, v_applied_margin
    FROM public.quotes
    WHERE id = p_quote_id AND company_id = p_company_id;

    IF v_discount < 0 OR v_discount::text IN ('NaN', 'Infinity', '-Infinity') THEN RAISE EXCEPTION 'Desconto inválido.'; END IF;
    IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;

    SELECT COALESCE(SUM(total_sale), 0), COALESCE(SUM(total_cost), 0)
    INTO v_subtotal, v_total_cost
    FROM public.quote_items
    WHERE quote_id = p_quote_id AND company_id = p_company_id;

    IF v_discount > v_subtotal THEN RAISE EXCEPTION 'O desconto não pode ser superior ao subtotal.'; END IF;

    v_sale_total := GREATEST(0, v_subtotal - v_discount);
    v_tax_amount := ROUND(v_sale_total * v_applied_tax_rate, 2);
    v_commission_amount := ROUND(v_sale_total * v_applied_commission_rate, 2);
    v_profit := v_sale_total - v_total_cost - v_tax_amount - v_commission_amount;

    IF v_sale_total > 0 THEN
        v_resulting_margin := v_profit / v_sale_total;
        IF v_resulting_margin IS NULL OR v_resulting_margin::text IN ('NaN', 'Infinity', '-Infinity') THEN
            RAISE EXCEPTION 'Erro de cálculo numérico (NaN/Infinito).';
        END IF;

        IF v_resulting_margin < v_min_net_margin THEN
            SELECT role INTO v_caller_role FROM public.company_members WHERE company_id = p_company_id AND user_id = auth.uid() AND active = TRUE;
            IF v_caller_role IS NULL OR v_caller_role NOT IN ('owner', 'admin', 'manager') THEN
                RAISE EXCEPTION 'Desconto bloqueado: Margem líquida inferior ao mínimo regulamentado de 10%.';
            END IF;
            IF length(trim(COALESCE(p_justification, ''))) < 10 THEN
                RAISE EXCEPTION 'Exigência de Auditoria: Margem abaixo de 10% requer justificativa gerencial válida.';
            END IF;
            INSERT INTO public.margin_exceptions (company_id, quote_id, user_id, resulting_margin, minimum_margin, justification)
            VALUES (p_company_id, p_quote_id, auth.uid(), v_resulting_margin, v_min_net_margin, trim(p_justification));
        END IF;
    END IF;

    UPDATE public.quotes
    SET subtotal = v_subtotal, total_cost = v_total_cost, tax_amount = v_tax_amount,
        sale_total = v_sale_total, estimated_profit = v_profit, updated_at = now()
    WHERE id = p_quote_id AND company_id = p_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_quote_with_number(
    p_company_id UUID, p_customer_id UUID, p_title TEXT, p_description TEXT DEFAULT NULL, p_valid_until DATE DEFAULT NULL
)
RETURNS TABLE(quote_id UUID, quote_number BIGINT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_next_number BIGINT;
    v_new_quote_id UUID;
    v_clean_title TEXT;
    v_default_margin NUMERIC(7,4);
    v_tax_config JSONB;
    v_tax_rate NUMERIC(7,4) := 0.06;
    v_commission_rate NUMERIC(7,4) := 0.05;
BEGIN
    IF NOT public.has_min_role(p_company_id, 'sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;
    v_clean_title := trim(COALESCE(p_title, ''));
    IF length(v_clean_title) < 2 THEN RAISE EXCEPTION 'O título é obrigatório.'; END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.customers WHERE id = p_customer_id AND company_id = p_company_id FOR UPDATE;

    SELECT default_margin, tax_config INTO v_default_margin, v_tax_config FROM public.company_settings WHERE company_id = p_company_id;
    IF v_tax_config IS NOT NULL THEN
        v_tax_rate := COALESCE((v_tax_config->>'tax_rate')::NUMERIC, 0.06);
        v_commission_rate := COALESCE((v_tax_config->>'commission_rate')::NUMERIC, 0.05);
    END IF;

    SELECT next_number INTO v_next_number FROM public.quote_counters WHERE company_id = p_company_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Contador não encontrado.'; END IF;
    UPDATE public.quote_counters SET next_number = next_number + 1 WHERE company_id = p_company_id;

    INSERT INTO public.quotes (
        company_id, customer_id, created_by, quote_number, title, description, valid_until,
        applied_tax_rate, applied_commission_rate, applied_margin
    )
    VALUES (
        p_company_id, p_customer_id, auth.uid(), v_next_number, v_clean_title, p_description, p_valid_until,
        v_tax_rate, v_commission_rate, COALESCE(v_default_margin, 0.35)
    )
    RETURNING id INTO v_new_quote_id;

    RETURN QUERY SELECT v_new_quote_id, v_next_number;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_quote_item(
    p_company_id UUID, p_quote_id UUID, p_catalog_item_id UUID, p_quantity NUMERIC, p_position INT DEFAULT 0
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_quote_status TEXT;
    v_item_id UUID;
    v_catalog_cost NUMERIC(14,2);
    v_catalog_labor NUMERIC(14,2);
    v_catalog_name TEXT;
    v_catalog_unit TEXT;
    v_applied_margin NUMERIC(7,4);
    v_applied_tax_rate NUMERIC(7,4);
    v_applied_commission_rate NUMERIC(7,4);
    v_unit_cost NUMERIC(14,2);
    v_unit_sale_price NUMERIC(14,2);
    v_total_cost NUMERIC(14,2);
    v_total_sale NUMERIC(14,2);
    v_denominator NUMERIC(10,6);
    v_customer_id UUID;
BEGIN
    IF NOT public.has_min_role(p_company_id, 'sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;
    IF p_quantity <= 0 OR p_quantity IS NULL OR p_quantity::text IN ('NaN', 'Infinity', '-Infinity') THEN 
        RAISE EXCEPTION 'Quantidade numérica inválida.'; 
    END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT status, applied_margin, applied_tax_rate, applied_commission_rate 
    INTO v_quote_status, v_applied_margin, v_applied_tax_rate, v_applied_commission_rate 
    FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    
    IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;
    IF v_quote_status NOT IN ('draft', 'review') THEN RAISE EXCEPTION 'Orçamento imutável.'; END IF;

    SELECT purchase_cost, labor_cost, name, unit 
    INTO v_catalog_cost, v_catalog_labor, v_catalog_name, v_catalog_unit
    FROM public.catalog_items 
    WHERE id = p_catalog_item_id AND company_id = p_company_id AND active = TRUE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Item de catálogo não encontrado.'; END IF;

    v_unit_cost := v_catalog_cost + v_catalog_labor;
    v_denominator := 1.0 - v_applied_margin - v_applied_tax_rate - v_applied_commission_rate;
    IF v_denominator <= 0.05 THEN RAISE EXCEPTION 'Denominador financeiro inválido.'; END IF;

    v_unit_sale_price := ROUND(v_unit_cost / v_denominator, 2);
    v_total_cost := p_quantity * v_unit_cost;
    v_total_sale := p_quantity * v_unit_sale_price;

    INSERT INTO public.quote_items (
        company_id, quote_id, catalog_item_id, description, unit, 
        quantity, unit_cost, unit_sale_price, total_cost, total_sale, position
    )
    VALUES (
        p_company_id, p_quote_id, p_catalog_item_id, v_catalog_name, v_catalog_unit, 
        p_quantity, v_unit_cost, v_unit_sale_price, v_total_cost, v_total_sale, p_position
    )
    RETURNING id INTO v_item_id;

    UPDATE public.quote_versions SET status = 'invalidated' WHERE quote_id = p_quote_id AND status IN ('pending', 'stored');
    PERFORM public.recalculate_quote_totals(p_company_id, p_quote_id, NULL);
    RETURN v_item_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_quote_item_quantity(
    p_company_id UUID, p_quote_id UUID, p_item_id UUID, p_quantity NUMERIC
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_quote_status TEXT;
    v_unit_cost NUMERIC(14,2);
    v_unit_sale_price NUMERIC(14,2);
    v_customer_id UUID;
BEGIN
    IF NOT public.has_min_role(p_company_id, 'sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;
    IF p_quantity <= 0 OR p_quantity IS NULL OR p_quantity::text IN ('NaN', 'Infinity', '-Infinity') THEN 
        RAISE EXCEPTION 'Quantidade numérica inválida.'; 
    END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT status INTO v_quote_status FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;
    IF v_quote_status NOT IN ('draft', 'review') THEN RAISE EXCEPTION 'Orçamento imutável.'; END IF;

    SELECT unit_cost, unit_sale_price INTO v_unit_cost, v_unit_sale_price
    FROM public.quote_items WHERE id = p_item_id AND quote_id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Item não encontrado.'; END IF;

    UPDATE public.quote_items
    SET quantity = p_quantity,
        total_cost = p_quantity * v_unit_cost,
        total_sale = p_quantity * v_unit_sale_price
    WHERE id = p_item_id AND quote_id = p_quote_id AND company_id = p_company_id;

    UPDATE public.quote_versions SET status = 'invalidated' WHERE quote_id = p_quote_id AND status IN ('pending', 'stored');
    PERFORM public.recalculate_quote_totals(p_company_id, p_quote_id, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_quote_item(
    p_company_id UUID, p_quote_id UUID, p_item_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_quote_status TEXT;
    v_deleted_count INT;
    v_customer_id UUID;
BEGIN
    IF NOT public.has_min_role(p_company_id, 'sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT status INTO v_quote_status FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;
    IF v_quote_status NOT IN ('draft', 'review') THEN RAISE EXCEPTION 'Orçamento imutável.'; END IF;

    DELETE FROM public.quote_items 
    WHERE id = p_item_id AND quote_id = p_quote_id AND company_id = p_company_id;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    IF v_deleted_count = 0 THEN RAISE EXCEPTION 'Item não encontrado para remoção.'; END IF;

    UPDATE public.quote_versions SET status = 'invalidated' WHERE quote_id = p_quote_id AND status IN ('pending', 'stored');
    PERFORM public.recalculate_quote_totals(p_company_id, p_quote_id, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_quote_discount(
    p_company_id UUID, p_quote_id UUID, p_discount NUMERIC, p_justification TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_quote_status TEXT;
    v_customer_id UUID;
BEGIN
    IF NOT public.has_min_role(p_company_id, 'sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;
    IF p_discount < 0 OR p_discount IS NULL OR p_discount::text IN ('NaN', 'Infinity', '-Infinity') THEN 
        RAISE EXCEPTION 'Desconto numérico inválido.'; 
    END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT status INTO v_quote_status FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;
    IF v_quote_status NOT IN ('draft', 'review') THEN RAISE EXCEPTION 'Orçamento imutável.'; END IF;

    UPDATE public.quotes
    SET discount = p_discount, updated_at = now()
    WHERE id = p_quote_id AND company_id = p_company_id;

    UPDATE public.quote_versions SET status = 'invalidated' WHERE quote_id = p_quote_id AND status IN ('pending', 'stored');
    PERFORM public.recalculate_quote_totals(p_company_id, p_quote_id, p_justification);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_quote_basic_info(
    p_company_id UUID, p_quote_id UUID, p_title TEXT, p_description TEXT, p_valid_until DATE
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_quote_status TEXT;
    v_clean_title TEXT;
    v_customer_id UUID;
BEGIN
    IF NOT public.has_min_role(p_company_id, 'sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;

    v_clean_title := trim(COALESCE(p_title, ''));
    IF length(v_clean_title) < 2 THEN RAISE EXCEPTION 'Título obrigatório.'; END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT status INTO v_quote_status FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;
    IF v_quote_status NOT IN ('draft', 'review') THEN RAISE EXCEPTION 'Orçamento imutável.'; END IF;

    UPDATE public.quotes
    SET title = v_clean_title, description = p_description, valid_until = p_valid_until, updated_at = now()
    WHERE id = p_quote_id AND company_id = p_company_id;

    UPDATE public.quote_versions SET status = 'invalidated' WHERE quote_id = p_quote_id AND status IN ('pending', 'stored');
END;
$$;

-- 9. VERSIONAMENTO E CONFIRMAÇÃO ATÔMICA BLINDADA CONTRA CORRIDA
CREATE OR REPLACE FUNCTION public.emit_quote_version(p_company_id UUID, p_quote_id UUID)
RETURNS TABLE(version_number INTEGER, pdf_path TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_next_version INT;
    v_generated_pdf_path TEXT;
    v_server_snapshot JSONB;
    v_quote_status TEXT;
    v_pending_count INT;
    v_items_count INT;
    v_sale_total NUMERIC(14,2);
    v_customer_id UUID;
BEGIN
    IF NOT public.has_min_role(p_company_id, 'sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT status, sale_total INTO v_quote_status, v_sale_total FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;
    IF v_quote_status != 'review' THEN RAISE EXCEPTION 'Orçamento deve estar em review.'; END IF;
    IF v_sale_total <= 0 THEN RAISE EXCEPTION 'Impossível emitir orçamento sem valor comercial positivo.'; END IF;

    SELECT COUNT(*) INTO v_items_count FROM public.quote_items WHERE quote_id = p_quote_id;
    IF v_items_count = 0 THEN RAISE EXCEPTION 'Impossível emitir orçamento sem itens.'; END IF;

    SELECT COUNT(*) INTO v_pending_count FROM public.quote_versions WHERE quote_id = p_quote_id AND status = 'pending';
    IF v_pending_count > 0 THEN RAISE EXCEPTION 'Já existe versão pendente.'; END IF;

    UPDATE public.quote_versions SET status = 'invalidated' WHERE quote_id = p_quote_id AND status IN ('pending', 'stored');

    SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_version
    FROM public.quote_versions WHERE company_id = p_company_id AND quote_id = p_quote_id;

    v_generated_pdf_path := p_company_id::text || '/quotes/' || p_quote_id::text || '/version_' || v_next_version::text || '.pdf';
    v_server_snapshot := public.get_canonical_quote_snapshot(p_company_id, p_quote_id);

    INSERT INTO public.quote_versions (company_id, quote_id, version_number, status, snapshot, pdf_path)
    VALUES (p_company_id, p_quote_id, v_next_version, 'pending', v_server_snapshot, v_generated_pdf_path);

    RETURN QUERY SELECT v_next_version, v_generated_pdf_path;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_quote_version_stored(
    p_company_id UUID, p_quote_id UUID, p_version_number INT, p_verified_backend_sha256 TEXT, p_actor_user_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_pdf_path TEXT;
    v_current_status TEXT;
    v_file_exists BOOLEAN;
    v_updated_rows INT;
    v_member_role TEXT;
    v_member_active BOOLEAN;
BEGIN
    IF p_actor_user_id IS NULL THEN
        RAISE EXCEPTION 'Ator da operação não identificado.';
    END IF;

    IF p_verified_backend_sha256 !~ '^[a-fA-F0-9]{64}$' THEN
        RAISE EXCEPTION 'Hash SHA-256 verificado pelo backend é inválido.';
    END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT role, active INTO v_member_role, v_member_active
    FROM public.company_members
    WHERE company_id = p_company_id AND user_id = p_actor_user_id
    FOR UPDATE;

    IF v_member_role IS NULL OR v_member_active IS NOT TRUE OR v_member_role NOT IN ('sales', 'manager', 'admin', 'owner') THEN
        RAISE EXCEPTION 'Acesso negado na confirmação atômica: Associação revogada ou papel insuficiente.';
    END IF;

    SELECT pdf_path, status INTO v_pdf_path, v_current_status
    FROM public.quote_versions
    WHERE company_id = p_company_id AND quote_id = p_quote_id AND version_number = p_version_number
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Versão não encontrada.'; END IF;
    IF v_current_status != 'pending' THEN RAISE EXCEPTION 'Conflito de estado: A versão não está pendente.'; END IF;

    SELECT EXISTS (
        SELECT 1 FROM storage.objects WHERE bucket_id = 'proposals' AND name = v_pdf_path
    ) INTO v_file_exists;

    IF NOT v_file_exists THEN RAISE EXCEPTION 'Arquivo PDF ausente no Storage.'; END IF;

    UPDATE public.quote_versions
    SET status = 'stored', pdf_hash = lower(trim(p_verified_backend_sha256))
    WHERE company_id = p_company_id AND quote_id = p_quote_id AND version_number = p_version_number AND status = 'pending';

    GET DIAGNOSTICS v_updated_rows = ROW_COUNT;
    IF v_updated_rows = 0 THEN RAISE EXCEPTION 'Falha na confirmação atômica.'; END IF;
END;
$$;

-- 10. IMUTABILIDADE COMERCIAL E MÁQUINA DE ESTADOS
CREATE OR REPLACE FUNCTION public.prevent_sent_quote_modification()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_has_stored_versions BOOLEAN;
BEGIN
    SELECT EXISTS (SELECT 1 FROM public.quote_versions WHERE quote_id = OLD.id AND status IN ('stored', 'issued')) INTO v_has_stored_versions;
    
    IF TG_OP = 'DELETE' AND v_has_stored_versions THEN
        RAISE EXCEPTION 'Operação negada: Orçamento emitido não pode ser excluído.';
    END IF;

    IF OLD.status IN ('sent', 'approved', 'rejected', 'expired', 'cancelled') THEN
        IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
            IF OLD.title IS DISTINCT FROM NEW.title OR
               OLD.customer_id IS DISTINCT FROM NEW.customer_id OR
               OLD.description IS DISTINCT FROM NEW.description OR
               OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
               OLD.sale_total IS DISTINCT FROM NEW.sale_total OR
               OLD.discount IS DISTINCT FROM NEW.discount OR
               OLD.total_cost IS DISTINCT FROM NEW.total_cost OR
               OLD.tax_amount IS DISTINCT FROM NEW.tax_amount OR
               OLD.estimated_profit IS DISTINCT FROM NEW.estimated_profit OR
               OLD.quote_number IS DISTINCT FROM NEW.quote_number OR
               OLD.created_by IS DISTINCT FROM NEW.created_by OR
               OLD.company_id IS DISTINCT FROM NEW.company_id OR
               OLD.valid_until IS DISTINCT FROM NEW.valid_until THEN
                RAISE EXCEPTION 'Operação negada: Modificação comercial proibida após emissão.';
            END IF;
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'Operação negada: Orçamento em estado imutável.';
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_lock_sent_quotes BEFORE UPDATE OR DELETE ON public.quotes FOR EACH ROW EXECUTE FUNCTION public.prevent_sent_quote_modification();

CREATE OR REPLACE FUNCTION public.transition_quote_status(p_company_id UUID, p_quote_id UUID, p_new_status TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_current_status TEXT;
    v_user_role TEXT;
    v_stored_version_id UUID;
    v_snapshot JSONB;
    v_current_canonical_snapshot JSONB;
    v_customer_id UUID;
BEGIN
    SELECT role INTO v_user_role FROM public.company_members WHERE company_id = p_company_id AND user_id = auth.uid() AND active = TRUE;
    IF v_user_role IS NULL THEN RAISE EXCEPTION 'Acesso negado.'; END IF;

    PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
    PERFORM 1 FROM public.company_settings WHERE company_id = p_company_id FOR UPDATE;
    SELECT customer_id INTO v_customer_id FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF v_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE id = v_customer_id AND company_id = p_company_id FOR UPDATE;
    END IF;
    PERFORM 1 FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id FOR UPDATE;

    SELECT status INTO v_current_status FROM public.quotes WHERE id = p_quote_id AND company_id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Orçamento não encontrado.'; END IF;

    IF v_current_status IN ('approved', 'rejected', 'expired', 'cancelled') THEN
        RAISE EXCEPTION 'Orçamento em estado terminal.';
    END IF;

    IF v_current_status = 'draft' THEN
        IF p_new_status = 'review' AND v_user_role IN ('owner','admin','manager','sales') THEN NULL;
        ELSIF p_new_status = 'cancelled' AND v_user_role IN ('owner','admin','manager') THEN NULL;
        ELSE RAISE EXCEPTION 'Transição inválida.'; END IF;
    ELSIF v_current_status = 'review' THEN
        IF p_new_status = 'draft' AND v_user_role IN ('owner','admin','manager','sales') THEN NULL;
        ELSIF p_new_status = 'cancelled' AND v_user_role IN ('owner','admin','manager') THEN NULL;
        ELSIF p_new_status = 'sent' THEN
            IF v_user_role NOT IN ('owner','admin','manager','sales') THEN RAISE EXCEPTION 'Acesso negado.'; END IF;
            
            SELECT id, snapshot INTO v_stored_version_id, v_snapshot 
            FROM public.quote_versions 
            WHERE quote_id = p_quote_id AND status = 'stored' 
            ORDER BY version_number DESC LIMIT 1 FOR UPDATE;

            IF v_stored_version_id IS NULL THEN RAISE EXCEPTION 'Exige versão stored válida.'; END IF;

            v_current_canonical_snapshot := public.get_canonical_quote_snapshot(p_company_id, p_quote_id);

            IF v_snapshot IS DISTINCT FROM v_current_canonical_snapshot THEN
                RAISE EXCEPTION 'Emissão rejeitada: O snapshot do PDF armazenado diverge do estado comercial canônico atual.';
            END IF;

            UPDATE public.quote_versions 
            SET status = 'issued', issued_at = now(), issued_by = auth.uid() 
            WHERE id = v_stored_version_id;
        ELSE RAISE EXCEPTION 'Transição inválida.'; END IF;
    ELSIF v_current_status = 'sent' THEN
        IF p_new_status IN ('approved', 'rejected', 'expired', 'cancelled') AND v_user_role IN ('owner','admin','manager') THEN NULL;
        ELSE RAISE EXCEPTION 'Transição inválida.'; END IF;
    ELSE RAISE EXCEPTION 'Estado desconhecido.'; END IF;

    UPDATE public.quotes SET status = p_new_status, updated_at = now() WHERE id = p_quote_id AND company_id = p_company_id;
END;
$$;

-- 11. STORAGE E POLÍTICAS DE BUCKET
DO $$
BEGIN
    INSERT INTO storage.buckets (id, name, public) 
    VALUES ('proposals', 'proposals', FALSE)
    ON CONFLICT (id) DO UPDATE SET public = FALSE;
END $$;

CREATE POLICY storage_proposals_read ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id = 'proposals' AND public.is_company_member((storage.foldername(name))[1]::uuid));

CREATE POLICY storage_proposals_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'proposals' AND
    public.has_min_role((storage.foldername(name))[1]::uuid, 'sales') AND
    (storage.foldername(name))[2] = 'quotes' AND
    EXISTS (
        SELECT 1 FROM public.quote_versions qv
        WHERE qv.company_id::text = (storage.foldername(name))[1]
          AND qv.quote_id::text = (storage.foldername(name))[3]
          AND qv.pdf_path = name
          AND qv.status = 'pending'
    )
);

CREATE POLICY storage_proposals_no_update ON storage.objects FOR UPDATE TO authenticated USING (FALSE);
CREATE POLICY storage_proposals_no_delete ON storage.objects FOR DELETE TO authenticated USING (FALSE);

-- 12. REVOKE E GRANTS
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.is_company_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_min_role(UUID, TEXT) TO authenticated;

GRANT SELECT ON public.companies, public.company_members, public.customers, public.suppliers, public.catalog_items, public.price_history, public.quotes, public.quote_items, public.company_settings, public.quote_counters, public.quote_versions, public.margin_exceptions, public.audit_logs TO authenticated;

GRANT INSERT, DELETE ON public.customers TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.suppliers, public.catalog_items, public.price_history TO authenticated;
GRANT SELECT ON public.margin_exceptions TO authenticated;

GRANT EXECUTE ON FUNCTION public.update_customer(UUID, UUID, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_company_settings(UUID, TEXT, JSONB, NUMERIC, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_company_info(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bootstrap_company(TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.manage_company_member(UUID, UUID, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_quote_with_number(UUID, UUID, TEXT, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_quote_item(UUID, UUID, UUID, NUMERIC, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_quote_item_quantity(UUID, UUID, UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_quote_item(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_quote_discount(UUID, UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_quote_basic_info(UUID, UUID, TEXT, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emit_quote_version(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_quote_status(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_quote_version_stored(UUID, UUID, INT, TEXT, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_canonical_quote_snapshot(UUID, UUID) TO service_role;

-- 13. RLS E POLÍTICAS UNIVERSAIS DE ISOLAMENTO
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.margin_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY companies_select ON public.companies FOR SELECT TO authenticated USING (public.is_company_member(id));
CREATE POLICY members_select ON public.company_members FOR SELECT TO authenticated USING (public.is_company_member(company_id));

CREATE POLICY customers_select ON public.customers FOR SELECT TO authenticated USING (public.is_company_member(company_id));
CREATE POLICY customers_insert ON public.customers FOR INSERT TO authenticated WITH CHECK (public.has_min_role(company_id, 'sales'));
CREATE POLICY customers_delete ON public.customers FOR DELETE TO authenticated USING (public.has_min_role(company_id, 'manager'));

CREATE POLICY suppliers_select ON public.suppliers FOR SELECT TO authenticated USING (public.is_company_member(company_id));
CREATE POLICY suppliers_insert ON public.suppliers FOR INSERT TO authenticated WITH CHECK (public.has_min_role(company_id, 'manager'));
CREATE POLICY suppliers_update ON public.suppliers FOR UPDATE TO authenticated USING (public.has_min_role(company_id, 'manager')) WITH CHECK (public.has_min_role(company_id, 'manager'));
CREATE POLICY suppliers_delete ON public.suppliers FOR DELETE TO authenticated USING (public.has_min_role(company_id, 'admin'));

CREATE POLICY catalog_select ON public.catalog_items FOR SELECT TO authenticated USING (public.is_company_member(company_id));
CREATE POLICY catalog_insert ON public.catalog_items FOR INSERT TO authenticated WITH CHECK (public.has_min_role(company_id, 'manager'));
CREATE POLICY catalog_update ON public.catalog_items FOR UPDATE TO authenticated USING (public.has_min_role(company_id, 'manager')) WITH CHECK (public.has_min_role(company_id, 'manager'));

CREATE POLICY prices_select ON public.price_history FOR SELECT TO authenticated USING (public.is_company_member(company_id));
CREATE POLICY prices_insert ON public.price_history FOR INSERT TO authenticated WITH CHECK (public.has_min_role(company_id, 'manager'));

CREATE POLICY quotes_select ON public.quotes FOR SELECT TO authenticated USING (public.is_company_member(company_id));
CREATE POLICY quote_items_select ON public.quote_items FOR SELECT TO authenticated USING (public.is_company_member(company_id));

CREATE POLICY settings_select ON public.company_settings FOR SELECT TO authenticated USING (public.is_company_member(company_id));
CREATE POLICY counters_select ON public.quote_counters FOR SELECT TO authenticated USING (public.is_company_member(company_id));
CREATE POLICY versions_select ON public.quote_versions FOR SELECT TO authenticated USING (public.is_company_member(company_id));
CREATE POLICY exceptions_select ON public.margin_exceptions FOR SELECT TO authenticated USING (public.has_min_role(company_id, 'manager'));
CREATE POLICY audit_select ON public.audit_logs FOR SELECT TO authenticated USING (public.has_min_role(company_id, 'manager'));
