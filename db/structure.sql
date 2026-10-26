SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: prevent_inventory_log_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_inventory_log_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'Inventory history is append-only';
END;
$$;


--
-- Name: protect_sale_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_sale_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE parent_state text;
BEGIN
  IF TG_TABLE_NAME = 'orders' THEN
    IF OLD.state <> 'draft' THEN
      IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Recorded sales cannot be deleted'; END IF;
      IF NOT (OLD.state = 'confirmed' AND NEW.state = 'voided' AND
        (to_jsonb(OLD) - ARRAY['state','voided_at','voided_by_id','void_reason','updated_at']) =
        (to_jsonb(NEW) - ARRAY['state','voided_at','voided_by_id','void_reason','updated_at'])) THEN
        RAISE EXCEPTION 'Recorded sales are immutable';
      END IF;
    ELSIF TG_OP = 'UPDATE' AND (NEW.business_id <> OLD.business_id OR NEW.submission_key <> OLD.submission_key OR NEW.creation_digest <> OLD.creation_digest) THEN
      RAISE EXCEPTION 'Sale submission identity is immutable';
    END IF;
  ELSE
    IF TG_OP <> 'INSERT' THEN
      SELECT state INTO parent_state FROM orders WHERE id = OLD.order_id FOR UPDATE;
      IF parent_state <> 'draft' THEN RAISE EXCEPTION 'Recorded sale items are immutable'; END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
      SELECT state INTO parent_state FROM orders WHERE id = NEW.order_id FOR UPDATE;
      IF parent_state <> 'draft' THEN RAISE EXCEPTION 'Recorded sale items are immutable'; END IF;
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END; $$;


--
-- Name: protect_sale_submission(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_sale_submission() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Sale submission identities are retained'; END IF;
  IF (to_jsonb(OLD) - 'order_id') <> (to_jsonb(NEW) - 'order_id') OR NEW.order_id IS NOT NULL THEN
    RAISE EXCEPTION 'Sale submission identity is immutable';
  END IF;
  RETURN NEW;
END; $$;


--
-- Name: validate_recorded_sale(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_recorded_sale() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE sale_id bigint; sale orders%ROWTYPE; item_count bigint;
BEGIN
  IF TG_TABLE_NAME = 'orders' THEN sale_id := COALESCE(NEW.id, OLD.id);
  ELSIF TG_TABLE_NAME = 'order_items' THEN sale_id := COALESCE(NEW.order_id, OLD.order_id);
  ELSE SELECT order_id INTO sale_id FROM order_items WHERE id = NEW.order_item_id;
  END IF;
  SELECT * INTO sale FROM orders WHERE id = sale_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT count(*) INTO item_count FROM order_items WHERE order_id = sale_id;
  IF item_count = 0 THEN RAISE EXCEPTION 'A sale requires items'; END IF;
  IF sale.state = 'draft' THEN
    IF EXISTS (SELECT 1 FROM order_items i LEFT JOIN inventory_logs l ON l.order_item_id = i.id
               WHERE i.order_id = sale_id AND (i.unit_price_minor IS NOT NULL OR l.id IS NOT NULL)) THEN
      RAISE EXCEPTION 'Drafts cannot have recorded snapshots or stock movements';
    END IF;
  ELSE
    IF EXISTS (SELECT 1 FROM order_items WHERE order_id = sale_id AND unit_price_minor IS NULL)
       OR sale.total_minor <> (SELECT sum(line_total_minor) FROM order_items WHERE order_id = sale_id) THEN
      RAISE EXCEPTION 'Sale snapshots and total must agree';
    END IF;
    IF (SELECT count(*) FROM inventory_logs l JOIN order_items i ON i.id = l.order_item_id
        WHERE i.order_id = sale_id AND l.kind = 'sale' AND l.quantity_delta = -i.quantity AND l.actor_id = sale.confirmed_by_id) <> item_count THEN
      RAISE EXCEPTION 'Sale deductions must match every item';
    END IF;
    IF (SELECT count(*) FROM inventory_logs l JOIN order_items i ON i.id = l.order_item_id
        JOIN inventory_logs original ON original.id = l.reversal_of_id AND original.kind = 'sale'
        WHERE i.order_id = sale_id AND l.kind = 'sale_void' AND l.quantity_delta = i.quantity AND l.actor_id = sale.voided_by_id)
        <> (CASE WHEN sale.state = 'voided' THEN item_count ELSE 0 END) THEN
      RAISE EXCEPTION 'Sale reversals must match the void state and every item';
    END IF;
  END IF;
  RETURN NULL;
END; $$;


--
-- Name: validate_sale_movement_link(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_sale_movement_link() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE sale_state text; sold_quantity integer; original_kind text;
BEGIN
  IF NEW.order_item_id IS NULL THEN RETURN NULL; END IF;
  SELECT o.state, i.quantity INTO sale_state, sold_quantity
    FROM order_items i JOIN orders o ON o.id = i.order_id WHERE i.id = NEW.order_item_id;
  IF NEW.kind = 'sale' THEN
    IF sale_state NOT IN ('confirmed', 'voided') OR NEW.quantity_delta <> -sold_quantity THEN
      RAISE EXCEPTION 'Sale movement must deduct the recorded quantity of a confirmed sale';
    END IF;
  ELSE
    SELECT kind INTO original_kind FROM inventory_logs WHERE id = NEW.reversal_of_id;
    IF sale_state <> 'voided' OR NEW.quantity_delta <> sold_quantity OR original_kind <> 'sale' THEN
      RAISE EXCEPTION 'Sale reversal must restore the recorded quantity of a voided sale';
    END IF;
  END IF;
  RETURN NULL;
END; $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: businesses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.businesses (
    id bigint NOT NULL,
    owner_id bigint NOT NULL,
    name character varying(120) NOT NULL,
    currency character varying(3) DEFAULT 'NGN'::character varying NOT NULL,
    timezone character varying(100) DEFAULT 'Africa/Lagos'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT business_name_present CHECK ((length(btrim((name)::text)) > 0)),
    CONSTRAINT business_supported_defaults CHECK ((((currency)::text = 'NGN'::text) AND ((timezone)::text = 'Africa/Lagos'::text)))
);


--
-- Name: businesses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.businesses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: businesses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.businesses_id_seq OWNED BY public.businesses.id;


--
-- Name: inventory_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_logs (
    id bigint NOT NULL,
    business_id bigint NOT NULL,
    product_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    operation_key uuid NOT NULL,
    kind character varying(16) NOT NULL,
    quantity_delta integer NOT NULL,
    resulting_balance integer NOT NULL,
    reason character varying(500) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    order_item_id bigint,
    reversal_of_id bigint,
    CONSTRAINT movement_reason_present CHECK ((length(btrim((reason)::text)) > 0)),
    CONSTRAINT movement_valid_kind CHECK (((((kind)::text = ANY ((ARRAY['opening'::character varying, 'receipt'::character varying, 'adjustment'::character varying])::text[])) AND (order_item_id IS NULL) AND (reversal_of_id IS NULL) AND (((kind)::text = 'adjustment'::text) OR (quantity_delta > 0))) OR (((kind)::text = 'sale'::text) AND (order_item_id IS NOT NULL) AND (reversal_of_id IS NULL) AND (quantity_delta < 0)) OR (((kind)::text = 'sale_void'::text) AND (order_item_id IS NOT NULL) AND (reversal_of_id IS NOT NULL) AND (quantity_delta > 0)))),
    CONSTRAINT movement_valid_quantities CHECK (((quantity_delta <> 0) AND (resulting_balance >= 0)))
);


--
-- Name: inventory_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_logs_id_seq OWNED BY public.inventory_logs.id;


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id bigint NOT NULL,
    business_id bigint NOT NULL,
    order_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity integer NOT NULL,
    product_name character varying(160),
    product_sku character varying(64),
    unit_price_minor bigint,
    line_total_minor bigint,
    CONSTRAINT sale_item_positive_quantity CHECK ((quantity > 0)),
    CONSTRAINT sale_item_valid_snapshot CHECK ((((product_name IS NULL) AND (product_sku IS NULL) AND (unit_price_minor IS NULL) AND (line_total_minor IS NULL)) OR ((product_name IS NOT NULL) AND (length(btrim((product_name)::text)) > 0) AND (product_sku IS NOT NULL) AND (length(btrim((product_sku)::text)) > 0) AND (unit_price_minor IS NOT NULL) AND ((unit_price_minor >= 1) AND (unit_price_minor <= '999999999999'::bigint)) AND (line_total_minor IS NOT NULL) AND (line_total_minor > 0) AND ((line_total_minor)::numeric = ((quantity)::numeric * (unit_price_minor)::numeric)))))
);


--
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.order_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.order_items_id_seq OWNED BY public.order_items.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id bigint NOT NULL,
    business_id bigint NOT NULL,
    submission_key uuid NOT NULL,
    creation_digest character varying(64) NOT NULL,
    state character varying(16) DEFAULT 'draft'::character varying NOT NULL,
    revision integer DEFAULT 0 NOT NULL,
    review_token uuid NOT NULL,
    quote jsonb NOT NULL,
    total_minor bigint NOT NULL,
    confirmed_at timestamp(6) without time zone,
    confirmed_by_id bigint,
    voided_at timestamp(6) without time zone,
    voided_by_id bigint,
    void_reason character varying(500),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT order_valid_review CHECK (((revision >= 0) AND ((total_minor >= 1) AND (total_minor <= '9223372036854775807'::bigint)) AND (jsonb_typeof(quote) = 'array'::text))),
    CONSTRAINT order_valid_state CHECK (((((state)::text = 'draft'::text) AND (confirmed_at IS NULL) AND (confirmed_by_id IS NULL) AND (voided_at IS NULL) AND (voided_by_id IS NULL) AND (void_reason IS NULL)) OR (((state)::text = 'confirmed'::text) AND (confirmed_at IS NOT NULL) AND (confirmed_by_id IS NOT NULL) AND (voided_at IS NULL) AND (voided_by_id IS NULL) AND (void_reason IS NULL)) OR (((state)::text = 'voided'::text) AND (confirmed_at IS NOT NULL) AND (confirmed_by_id IS NOT NULL) AND (voided_at IS NOT NULL) AND (voided_at >= confirmed_at) AND (voided_by_id IS NOT NULL) AND (void_reason IS NOT NULL) AND (length(btrim((void_reason)::text)) > 0))))
);


--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id bigint NOT NULL,
    business_id bigint NOT NULL,
    name character varying(160) NOT NULL,
    sku character varying(64) NOT NULL,
    price_minor bigint NOT NULL,
    quantity integer DEFAULT 0 NOT NULL,
    low_stock_threshold integer DEFAULT 0 NOT NULL,
    archived_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT product_name_present CHECK ((length(btrim((name)::text)) > 0)),
    CONSTRAINT product_normalized_sku CHECK (((sku)::text ~ '^[A-Z0-9][A-Z0-9._-]*$'::text)),
    CONSTRAINT product_price_range CHECK (((price_minor >= 1) AND (price_minor <= '999999999999'::bigint))),
    CONSTRAINT product_stock_nonnegative CHECK (((quantity >= 0) AND (low_stock_threshold >= 0)))
);


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: sale_submissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_submissions (
    id bigint NOT NULL,
    business_id bigint NOT NULL,
    submission_key uuid NOT NULL,
    creation_digest character varying(64) NOT NULL,
    order_id bigint
);


--
-- Name: sale_submissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sale_submissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sale_submissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sale_submissions_id_seq OWNED BY public.sale_submissions.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT user_normalized_email CHECK ((((email_address)::text = lower(btrim((email_address)::text))) AND ((length((email_address)::text) >= 3) AND (length((email_address)::text) <= 254))))
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: businesses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses ALTER COLUMN id SET DEFAULT nextval('public.businesses_id_seq'::regclass);


--
-- Name: inventory_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs ALTER COLUMN id SET DEFAULT nextval('public.inventory_logs_id_seq'::regclass);


--
-- Name: order_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items ALTER COLUMN id SET DEFAULT nextval('public.order_items_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: sale_submissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_submissions ALTER COLUMN id SET DEFAULT nextval('public.sale_submissions_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: businesses businesses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses
    ADD CONSTRAINT businesses_pkey PRIMARY KEY (id);


--
-- Name: inventory_logs inventory_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT inventory_logs_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: sale_submissions sale_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_submissions
    ADD CONSTRAINT sale_submissions_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_businesses_on_id_and_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_businesses_on_id_and_owner_id ON public.businesses USING btree (id, owner_id);


--
-- Name: index_businesses_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_businesses_on_owner_id ON public.businesses USING btree (owner_id);


--
-- Name: index_inventory_logs_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_logs_on_actor_id ON public.inventory_logs USING btree (actor_id);


--
-- Name: index_inventory_logs_on_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_logs_on_business_id ON public.inventory_logs USING btree (business_id);


--
-- Name: index_inventory_logs_on_business_id_and_operation_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_logs_on_business_id_and_operation_key ON public.inventory_logs USING btree (business_id, operation_key);


--
-- Name: index_inventory_logs_on_business_id_and_product_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_logs_on_business_id_and_product_id_and_id ON public.inventory_logs USING btree (business_id, product_id, id);


--
-- Name: index_inventory_logs_on_order_item_id_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_logs_on_order_item_id_and_kind ON public.inventory_logs USING btree (order_item_id, kind) WHERE (order_item_id IS NOT NULL);


--
-- Name: index_inventory_logs_on_reversal_of_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_logs_on_reversal_of_id ON public.inventory_logs USING btree (reversal_of_id) WHERE (reversal_of_id IS NOT NULL);


--
-- Name: index_order_items_on_business_id_and_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_order_items_on_business_id_and_id_and_product_id ON public.order_items USING btree (business_id, id, product_id);


--
-- Name: index_order_items_on_order_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_order_items_on_order_id_and_product_id ON public.order_items USING btree (order_id, product_id);


--
-- Name: index_orders_on_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_business_id ON public.orders USING btree (business_id);


--
-- Name: index_orders_on_business_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_orders_on_business_id_and_id ON public.orders USING btree (business_id, id);


--
-- Name: index_orders_on_business_id_and_state_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_business_id_and_state_and_id ON public.orders USING btree (business_id, state, id);


--
-- Name: index_orders_on_business_id_and_submission_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_orders_on_business_id_and_submission_key ON public.orders USING btree (business_id, submission_key);


--
-- Name: index_products_on_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_business_id ON public.products USING btree (business_id);


--
-- Name: index_products_on_business_id_and_archived_at_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_business_id_and_archived_at_and_name ON public.products USING btree (business_id, archived_at, name);


--
-- Name: index_products_on_business_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_products_on_business_id_and_id ON public.products USING btree (business_id, id);


--
-- Name: index_products_on_business_id_and_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_products_on_business_id_and_sku ON public.products USING btree (business_id, sku);


--
-- Name: index_sale_submissions_on_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sale_submissions_on_business_id ON public.sale_submissions USING btree (business_id);


--
-- Name: index_sale_submissions_on_business_id_and_submission_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sale_submissions_on_business_id_and_submission_key ON public.sale_submissions USING btree (business_id, submission_key);


--
-- Name: index_sale_submissions_on_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sale_submissions_on_order_id ON public.sale_submissions USING btree (order_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: movement_sale_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX movement_sale_identity ON public.inventory_logs USING btree (business_id, order_item_id, product_id, id);


--
-- Name: inventory_logs inventory_logs_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inventory_logs_append_only BEFORE DELETE OR UPDATE ON public.inventory_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_inventory_log_mutation();


--
-- Name: order_items order_items_consistent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER order_items_consistent AFTER INSERT OR DELETE OR UPDATE ON public.order_items DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_recorded_sale();


--
-- Name: order_items order_items_protect_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER order_items_protect_history BEFORE INSERT OR DELETE OR UPDATE ON public.order_items FOR EACH ROW EXECUTE FUNCTION public.protect_sale_history();


--
-- Name: orders orders_consistent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER orders_consistent AFTER INSERT OR UPDATE ON public.orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_recorded_sale();


--
-- Name: orders orders_protect_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER orders_protect_history BEFORE DELETE OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.protect_sale_history();


--
-- Name: inventory_logs sale_movement_valid_link; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER sale_movement_valid_link AFTER INSERT ON public.inventory_logs DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_sale_movement_link();


--
-- Name: inventory_logs sale_movements_consistent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER sale_movements_consistent AFTER INSERT ON public.inventory_logs DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_recorded_sale();


--
-- Name: sale_submissions sale_submissions_retained; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sale_submissions_retained BEFORE DELETE OR UPDATE ON public.sale_submissions FOR EACH ROW EXECUTE FUNCTION public.protect_sale_submission();


--
-- Name: inventory_logs fk_rails_0b7495dd73; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT fk_rails_0b7495dd73 FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: orders fk_rails_105a300374; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_105a300374 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: inventory_logs fk_rails_13b89fea06; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT fk_rails_13b89fea06 FOREIGN KEY (business_id, actor_id) REFERENCES public.businesses(id, owner_id);


--
-- Name: order_items fk_rails_1bc1649c8d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_rails_1bc1649c8d FOREIGN KEY (business_id, order_id) REFERENCES public.orders(business_id, id);


--
-- Name: sale_submissions fk_rails_2a2a35876d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_submissions
    ADD CONSTRAINT fk_rails_2a2a35876d FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: inventory_logs fk_rails_3b522f7d0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT fk_rails_3b522f7d0b FOREIGN KEY (business_id, product_id) REFERENCES public.products(business_id, id);


--
-- Name: products fk_rails_64b1679e02; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_64b1679e02 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: orders fk_rails_87121388ee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_87121388ee FOREIGN KEY (business_id, voided_by_id) REFERENCES public.businesses(id, owner_id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: orders fk_rails_a1e4ebe8aa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_a1e4ebe8aa FOREIGN KEY (business_id, confirmed_by_id) REFERENCES public.businesses(id, owner_id);


--
-- Name: order_items fk_rails_b18c757e10; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_rails_b18c757e10 FOREIGN KEY (business_id, product_id) REFERENCES public.products(business_id, id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: sale_submissions fk_rails_e07741e8fa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_submissions
    ADD CONSTRAINT fk_rails_e07741e8fa FOREIGN KEY (business_id, order_id) REFERENCES public.orders(business_id, id);


--
-- Name: inventory_logs fk_rails_e7d19e84ff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT fk_rails_e7d19e84ff FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: businesses fk_rails_e8a8d012a2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses
    ADD CONSTRAINT fk_rails_e8a8d012a2 FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: inventory_logs fk_rails_f1a01977d7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT fk_rails_f1a01977d7 FOREIGN KEY (business_id, order_item_id, product_id) REFERENCES public.order_items(business_id, id, product_id);


--
-- Name: inventory_logs movement_reverses_same_item; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT movement_reverses_same_item FOREIGN KEY (business_id, order_item_id, product_id, reversal_of_id) REFERENCES public.inventory_logs(business_id, order_item_id, product_id, id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261026194000'),
('20261025162000'),
('20261025161000'),
('20261025160000'),
('20261025150001'),
('20261025150000'),
('20261025132224'),
('20261025132221');
