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


SET default_tablespace = '';

SET default_table_access_method = heap;

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
    CONSTRAINT movement_reason_present CHECK ((length(btrim((reason)::text)) > 0)),
    CONSTRAINT movement_valid_kind CHECK ((((kind)::text = ANY (ARRAY[('opening'::character varying)::text, ('receipt'::character varying)::text, ('adjustment'::character varying)::text])) AND (((kind)::text = 'adjustment'::text) OR (quantity_delta > 0)))),
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
-- Name: businesses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses ALTER COLUMN id SET DEFAULT nextval('public.businesses_id_seq'::regclass);


--
-- Name: inventory_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs ALTER COLUMN id SET DEFAULT nextval('public.inventory_logs_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


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
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


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
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: inventory_logs inventory_logs_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inventory_logs_append_only BEFORE DELETE OR UPDATE ON public.inventory_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_inventory_log_mutation();


--
-- Name: inventory_logs fk_rails_0b7495dd73; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT fk_rails_0b7495dd73 FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: inventory_logs fk_rails_13b89fea06; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs
    ADD CONSTRAINT fk_rails_13b89fea06 FOREIGN KEY (business_id, actor_id) REFERENCES public.businesses(id, owner_id);


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
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261025150001'),
('20261025150000'),
('20261025132224'),
('20261025132221');
