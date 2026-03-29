create_statement
"CREATE TABLE public.active_storage_blobs (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	key VARCHAR NOT NULL,
	filename VARCHAR NOT NULL,
	content_type VARCHAR NULL,
	metadata STRING NULL,
	service_name VARCHAR NOT NULL,
	byte_size INT8 NOT NULL,
	checksum VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_active_storage_blobs_on_key (key ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.active_storage_attachments (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	name VARCHAR NOT NULL,
	record_type VARCHAR NOT NULL,
	record_id UUID NOT NULL,
	blob_id UUID NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id ASC),
	INDEX index_active_storage_attachments_on_blob_id (blob_id ASC),
	UNIQUE INDEX index_active_storage_attachments_uniqueness (record_type ASC, record_id ASC, name ASC, blob_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.active_storage_variant_records (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	blob_id UUID NOT NULL,
	variation_digest VARCHAR NOT NULL,
	CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_active_storage_variant_records_uniqueness (blob_id ASC, variation_digest ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zones (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	name VARCHAR NULL,
	city VARCHAR NULL,
	status BOOL NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	zone_code VARCHAR NULL,
	zone_type VARCHAR NULL,
	lat_min DECIMAL(10,6) NULL,
	lat_max DECIMAL(10,6) NULL,
	lng_min DECIMAL(10,6) NULL,
	lng_max DECIMAL(10,6) NULL,
	priority INT8 NULL DEFAULT 0:::INT8,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	boundary GEOGRAPHY(POLYGON,4326) NULL,
	center_point GEOGRAPHY(POINT,4326) NULL,
	radius_m INT8 NULL,
	geometry_type VARCHAR NULL DEFAULT 'bbox':::STRING,
	fuel_surcharge_pct DECIMAL(5,2) NULL DEFAULT 0.00:::DECIMAL,
	zone_multiplier DECIMAL(5,3) NULL DEFAULT 1.000:::DECIMAL,
	is_oda BOOL NULL DEFAULT false,
	special_location_surcharge_paise INT8 NULL DEFAULT 0:::INT8,
	oda_surcharge_pct DECIMAL(5,2) NULL DEFAULT 5.00:::DECIMAL,
	h3_indexes_r7 VARCHAR[] NULL DEFAULT ARRAY[]:::VARCHAR[],
	h3_indexes_r9 VARCHAR[] NULL DEFAULT ARRAY[]:::VARCHAR[],
	auto_generated BOOL NULL DEFAULT false,
	generation_version INT8 NULL,
	cell_count INT8 NULL DEFAULT 0:::INT8,
	parent_zone_code VARCHAR NULL,
	boundary_geojson JSONB NULL,
	center_lat DECIMAL(10,7) NULL,
	center_lng DECIMAL(10,7) NULL,
	min_fare_overrides JSONB NULL,
	cancellation_rate_pct FLOAT8 NULL,
	CONSTRAINT zones_pkey PRIMARY KEY (id ASC),
	INVERTED INDEX idx_zones_boundary_gist (boundary),
	INVERTED INDEX idx_zones_center_gist (center_point),
	UNIQUE INDEX index_zones_on_city_and_zone_code (city ASC, zone_code ASC),
	INDEX index_zones_on_city_and_zone_type (city ASC, zone_type ASC),
	INDEX index_zones_on_geometry_type (geometry_type ASC),
	INDEX index_zones_on_is_oda (is_oda ASC),
	INDEX index_zones_on_zone_type (zone_type ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.users (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	name VARCHAR NULL,
	email VARCHAR NULL,
	phone VARCHAR NULL,
	password_digest VARCHAR NULL,
	status INT8 NULL,
	current_location_id UUID NULL,
	country_id UUID NULL,
	region_id UUID NULL,
	zone_location_id UUID NULL,
	locale VARCHAR NULL,
	currency_pref VARCHAR NULL,
	last_login_at TIMESTAMP(6) NULL,
	referral_code VARCHAR NULL,
	zone_id INT8 NULL,
	subscription_type VARCHAR NULL,
	first_name VARCHAR NULL,
	last_name VARCHAR NULL,
	date_of_birth DATE NULL,
	gender VARCHAR NULL,
	bio STRING NULL,
	email_verified BOOL NULL DEFAULT false,
	phone_verified BOOL NULL DEFAULT false,
	notification_preferences JSONB NULL,
	theme_preference VARCHAR NULL DEFAULT 'light':::STRING,
	language_preference VARCHAR NULL DEFAULT 'en':::STRING,
	swaps_count INT8 NULL DEFAULT 0:::INT8,
	last_swap_at TIMESTAMP(6) NULL,
	""role"" VARCHAR NULL DEFAULT 'user':::STRING,
	account_type VARCHAR NULL DEFAULT 'basic':::STRING,
	referred_by UUID NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	password_confirmation VARCHAR NULL,
	agreed_tos_privacy_policy BOOL NOT NULL DEFAULT false,
	password VARCHAR NOT NULL DEFAULT '':::STRING,
	interests VARCHAR[] NULL DEFAULT ARRAY[]:::VARCHAR[],
	profile_picture_url VARCHAR NULL,
	CONSTRAINT users_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_users_on_email (email ASC),
	INDEX index_users_on_phone (phone ASC),
	UNIQUE INDEX index_users_on_referral_code (referral_code ASC),
	INDEX index_users_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.locations (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	user_id INT8 NULL,
	address_line STRING NULL,
	latitude DECIMAL NULL,
	longitude DECIMAL NULL,
	city VARCHAR NULL,
	state VARCHAR NULL,
	country VARCHAR NULL,
	pin_code VARCHAR NULL,
	is_primary BOOL NULL DEFAULT false,
	location_type VARCHAR NULL DEFAULT 'home':::STRING,
	address_line_2 VARCHAR NULL,
	formatted_address VARCHAR NULL,
	is_default BOOL NULL DEFAULT false,
	location_name VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT locations_pkey PRIMARY KEY (id ASC),
	INDEX index_locations_on_user_id (user_id ASC),
	UNIQUE INDEX uniq_locations_primary_per_user (user_id ASC) WHERE is_primary
) WITH (schema_locked = true);"
"CREATE TABLE public.address_contacts (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	location_id INT8 NOT NULL,
	full_name VARCHAR NULL,
	phone VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT address_contacts_pkey PRIMARY KEY (id ASC),
	INDEX index_address_contacts_on_location_id (location_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.admin_coin_overrides (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	user_id INT8 NOT NULL,
	adjusted_coin_balance DECIMAL(10,2) NULL DEFAULT 0.00:::DECIMAL,
	reason STRING NULL,
	admin_user VARCHAR NULL,
	start_balance DECIMAL(10,2) NULL DEFAULT 0.00:::DECIMAL,
	final_balance DECIMAL(10,2) NULL DEFAULT 0.00:::DECIMAL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT admin_coin_overrides_pkey PRIMARY KEY (id ASC),
	INDEX index_admin_coin_overrides_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.admins (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	name VARCHAR NULL,
	email VARCHAR NULL,
	phone VARCHAR NULL,
	""role"" VARCHAR NULL,
	active BOOL NOT NULL DEFAULT true,
	zone_id INT8 NULL,
	password_digest VARCHAR NULL,
	password VARCHAR NOT NULL DEFAULT '':::STRING,
	password_confirmation VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT admins_pkey PRIMARY KEY (id ASC),
	INDEX index_admins_on_active (active ASC),
	UNIQUE INDEX index_admins_on_email (email ASC),
	INDEX index_admins_on_phone (phone ASC),
	INDEX index_admins_on_role (""role"" ASC),
	INDEX index_admins_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.attachments (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	attachable_type VARCHAR NOT NULL,
	attachable_id UUID NOT NULL,
	file_url VARCHAR NOT NULL,
	file_type VARCHAR NOT NULL,
	""position"" INT8 NULL,
	metadata JSONB NOT NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	status VARCHAR NOT NULL DEFAULT 'ready':::STRING,
	active_storage_blob_id UUID NULL,
	CONSTRAINT attachments_pkey PRIMARY KEY (id ASC),
	INDEX index_attachments_on_active_storage_blob_id (active_storage_blob_id ASC),
	UNIQUE INDEX index_attachments_on_attachable_and_position (attachable_type ASC, attachable_id ASC, ""position"" ASC),
	INDEX index_attachments_on_attachable_and_status (attachable_type ASC, attachable_id ASC, status ASC),
	INDEX index_attachments_on_attachable (attachable_type ASC, attachable_id ASC),
	INDEX index_attachments_on_file_type (file_type ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.blocked_users (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	blocker_id INT8 NOT NULL,
	blocked_id INT8 NOT NULL,
	reason STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT blocked_users_pkey PRIMARY KEY (id ASC),
	INDEX index_blocked_users_on_blocked_id (blocked_id ASC),
	INDEX index_blocked_users_on_blocker_id (blocker_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.categories (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	name VARCHAR NOT NULL,
	slug VARCHAR NOT NULL,
	parent_id UUID NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT categories_pkey PRIMARY KEY (id ASC),
	INDEX index_categories_on_parent_id (parent_id ASC),
	UNIQUE INDEX index_categories_on_slug (slug ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.category_translations (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	category_id UUID NOT NULL,
	locale VARCHAR NOT NULL,
	name VARCHAR NOT NULL,
	description STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT category_translations_pkey PRIMARY KEY (id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.coin_earning_rules (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	activity_type VARCHAR NULL,
	coins_earned INT8 NULL,
	user_type VARCHAR NULL,
	criteria STRING NULL,
	status VARCHAR NULL,
	user_id INT8 NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT coin_earning_rules_pkey PRIMARY KEY (id ASC),
	INDEX index_coin_earning_rules_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.coin_expiry_settings (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	user_id INT8 NOT NULL,
	coin_type VARCHAR NULL DEFAULT 'referral_coin':::STRING,
	expiry_period INT8 NULL,
	status VARCHAR NULL,
	awarded_at TIMESTAMP(6) NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT coin_expiry_settings_pkey PRIMARY KEY (id ASC),
	INDEX index_coin_expiry_settings_on_user_id_and_coin_type (user_id ASC, coin_type ASC),
	INDEX index_coin_expiry_settings_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.delivery_addresses (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	address_line VARCHAR NOT NULL,
	address_line_2 VARCHAR NULL,
	landmark VARCHAR NULL,
	latitude DECIMAL(10,6) NULL,
	longitude DECIMAL(10,6) NULL,
	city VARCHAR NOT NULL,
	state VARCHAR NOT NULL,
	country VARCHAR NOT NULL DEFAULT 'India':::STRING,
	pin_code VARCHAR NOT NULL,
	contact_name VARCHAR NULL,
	contact_phone VARCHAR NULL,
	address_type VARCHAR NULL DEFAULT 'home':::STRING,
	is_default BOOL NULL DEFAULT false,
	is_active BOOL NULL DEFAULT true,
	label VARCHAR NULL,
	delivery_instructions JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT delivery_addresses_pkey PRIMARY KEY (id ASC),
	INDEX index_delivery_addresses_on_pin_code (pin_code ASC),
	INDEX index_delivery_addresses_on_user_id_and_is_active (user_id ASC, is_active ASC),
	INDEX index_delivery_addresses_on_user_id_and_is_default (user_id ASC, is_default ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.delivery_partners (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	name VARCHAR NULL,
	contact_info VARCHAR NULL,
	service_area VARCHAR NULL,
	service_types STRING NULL,
	cost_structure STRING NULL,
	delivery_speed VARCHAR NULL,
	performance_metrics STRING NULL,
	status VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	code VARCHAR NULL,
	integration_type VARCHAR NULL,
	api_base_url VARCHAR NULL,
	api_credentials JSONB NULL DEFAULT '{}':::JSONB,
	webhook_secret VARCHAR NULL,
	callback_url VARCHAR NULL,
	vehicle_types JSONB NULL DEFAULT '[]':::JSONB,
	is_active BOOL NULL DEFAULT false,
	CONSTRAINT delivery_partners_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_delivery_partners_on_code (code ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.delivery_orders (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	swap_request_id VARCHAR NULL,
	giveaway_claim_id VARCHAR NULL,
	sender_id INT8 NOT NULL,
	receiver_id INT8 NOT NULL,
	pickup_address_id UUID NOT NULL,
	drop_address_id UUID NOT NULL,
	delivery_partner VARCHAR NULL,
	tracking_id VARCHAR NULL,
	delivery_status VARCHAR NOT NULL DEFAULT 'pending':::STRING,
	quoted_price DECIMAL(12,2) NULL,
	final_price DECIMAL(12,2) NULL,
	discount_applied DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	pickup_scheduled_at TIMESTAMP(6) NULL,
	picked_up_at TIMESTAMP(6) NULL,
	in_transit_at TIMESTAMP(6) NULL,
	out_for_delivery_at TIMESTAMP(6) NULL,
	delivered_at TIMESTAMP(6) NULL,
	failed_at TIMESTAMP(6) NULL,
	cancelled_at TIMESTAMP(6) NULL,
	delivery_person_details JSONB NULL DEFAULT '{}':::JSONB,
	delivery_otp VARCHAR NULL,
	otp_verified BOOL NULL DEFAULT false,
	delivery_signature_url VARCHAR NULL,
	delivery_photo_url VARCHAR NULL,
	partner_response JSONB NULL DEFAULT '{}':::JSONB,
	delivery_notes STRING NULL,
	cancellation_reason STRING NULL,
	package_type VARCHAR NULL,
	package_weight DECIMAL(6,2) NULL,
	package_dimensions JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	delivery_partner_id INT8 NULL,
	vehicle_type VARCHAR NULL,
	partner_order_id VARCHAR NULL,
	partner_tracking_url VARCHAR NULL,
	estimated_delivery_at TIMESTAMP(6) NULL,
	booking_type VARCHAR NULL DEFAULT 'auto':::STRING,
	admin_notes STRING NULL,
	CONSTRAINT delivery_orders_pkey PRIMARY KEY (id ASC),
	INDEX index_delivery_orders_on_delivery_partner_id (delivery_partner_id ASC),
	INDEX index_delivery_orders_on_delivery_status_and_created_at (delivery_status ASC, created_at ASC),
	INDEX index_delivery_orders_on_delivery_status (delivery_status ASC),
	INDEX index_delivery_orders_on_giveaway_claim_id (giveaway_claim_id ASC),
	INDEX index_delivery_orders_on_partner_order_id (partner_order_id ASC),
	INDEX index_delivery_orders_on_receiver_id (receiver_id ASC),
	INDEX index_delivery_orders_on_sender_id (sender_id ASC),
	INDEX index_delivery_orders_on_swap_request_id (swap_request_id ASC),
	INDEX index_delivery_orders_on_tracking_id (tracking_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.delivery_partner_callbacks (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	delivery_order_id UUID NOT NULL,
	event_type VARCHAR NULL,
	status_update_payload JSONB NOT NULL,
	processed BOOL NULL DEFAULT false,
	processed_at TIMESTAMP(6) NULL,
	processing_error STRING NULL,
	partner_event_id VARCHAR NULL,
	delivery_partner VARCHAR NULL,
	received_at TIMESTAMP(6) NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT delivery_partner_callbacks_pkey PRIMARY KEY (id ASC),
	INDEX idx_on_delivery_order_id_received_at_a48d4e8180 (delivery_order_id ASC, received_at DESC),
	UNIQUE INDEX index_delivery_partner_callbacks_on_partner_event_id (partner_event_id ASC),
	INDEX index_delivery_partner_callbacks_on_processed_and_created_at (processed ASC, created_at ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.wallets (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	balance DECIMAL(12,2) NOT NULL DEFAULT 0.00:::DECIMAL,
	locked_balance DECIMAL(12,2) NOT NULL DEFAULT 0.00:::DECIMAL,
	currency VARCHAR NOT NULL DEFAULT 'INR':::STRING,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT wallets_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_wallets_on_user_id (user_id ASC),
	CONSTRAINT wallets_balance_non_negative CHECK (balance >= 0:::DECIMAL),
	CONSTRAINT wallets_locked_within_balance CHECK (locked_balance <= balance),
	CONSTRAINT wallets_locked_balance_non_negative CHECK (locked_balance >= 0:::DECIMAL)
) WITH (schema_locked = true);"
"CREATE TABLE public.escrow_holds (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	wallet_id UUID NOT NULL,
	amount DECIMAL(12,2) NOT NULL,
	hold_type VARCHAR NOT NULL,
	linked_reference_type VARCHAR NULL,
	linked_reference_id VARCHAR NULL,
	status VARCHAR NOT NULL DEFAULT 'active':::STRING,
	held_at TIMESTAMP(6) NOT NULL,
	expires_at TIMESTAMP(6) NULL,
	released_at TIMESTAMP(6) NULL,
	release_reason STRING NULL,
	released_by_id INT8 NULL,
	released_by_role VARCHAR NULL,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT escrow_holds_pkey PRIMARY KEY (id ASC),
	INDEX index_escrow_holds_on_hold_type_and_status (hold_type ASC, status ASC),
	INDEX idx_on_linked_reference_type_linked_reference_id_b2c06009a9 (linked_reference_type ASC, linked_reference_id ASC),
	INDEX index_escrow_holds_on_status_and_expires_at (status ASC, expires_at ASC),
	INDEX index_escrow_holds_on_user_id_and_status (user_id ASC, status ASC),
	INDEX index_escrow_holds_on_wallet_id_and_status (wallet_id ASC, status ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.feature_flags (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	name VARCHAR NOT NULL,
	description STRING NULL,
	enabled BOOL NULL DEFAULT false,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT feature_flags_pkey PRIMARY KEY (id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.fraud_rules (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	rule_name VARCHAR NULL,
	description STRING NULL,
	active BOOL NULL,
	threshold_value DECIMAL NULL,
	flag_action VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT fraud_rules_pkey PRIMARY KEY (id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.give_away_claims (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	listing_id UUID NOT NULL,
	pickup_type VARCHAR NOT NULL DEFAULT 'self_pickup':::STRING,
	delivery_address_id UUID NULL,
	status VARCHAR NOT NULL DEFAULT 'pending':::STRING,
	pickup_confirmed_by_claimer BOOL NOT NULL DEFAULT false,
	pickup_confirmed_by_owner BOOL NOT NULL DEFAULT false,
	note VARCHAR NULL,
	approved_at TIMESTAMP NULL,
	rejected_at TIMESTAMP NULL,
	cancelled_at TIMESTAMP NULL,
	completed_at TIMESTAMP NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	owner_id INT8 NOT NULL,
	claimer_id INT8 NOT NULL,
	CONSTRAINT give_away_claims_pkey PRIMARY KEY (id ASC),
	INDEX index_give_away_claims_on_claimer_id_and_status_and_created_at (claimer_id ASC, status ASC, created_at DESC),
	INDEX index_give_away_claims_on_listing_id_and_status (listing_id ASC, status ASC),
	INDEX index_give_away_claims_on_owner_id_and_status_and_created_at (owner_id ASC, status ASC, created_at DESC),
	CONSTRAINT chk_pickup_type_valid CHECK (pickup_type IN ('self_pickup':::STRING, 'swapzen_delivery':::STRING)),
	CONSTRAINT chk_status_valid CHECK (status IN ('pending':::STRING, 'approved':::STRING, 'rejected':::STRING, 'cancelled':::STRING, 'completed':::STRING, 'in_delivery':::STRING))
) WITH (schema_locked = true);"
"CREATE TABLE public.h3_supply_density (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	h3_index_r7 VARCHAR NOT NULL,
	city_code VARCHAR NOT NULL,
	time_band VARCHAR NOT NULL,
	avg_pickup_distance_m INT8 NULL DEFAULT 3000:::INT8,
	estimated_driver_count INT8 NULL DEFAULT 0:::INT8,
	zone_type_default BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT h3_supply_density_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX idx_h3_supply_density_unique (h3_index_r7 ASC, city_code ASC, time_band ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.h3_surge_buckets (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	h3_index VARCHAR NOT NULL,
	city_code VARCHAR NOT NULL,
	h3_resolution INT8 NOT NULL DEFAULT 9:::INT8,
	demand_score FLOAT8 NULL DEFAULT 0.0:::FLOAT8,
	supply_score FLOAT8 NULL DEFAULT 0.0:::FLOAT8,
	surge_multiplier FLOAT8 NULL DEFAULT 1.0:::FLOAT8,
	time_band VARCHAR NULL,
	expires_at TIMESTAMP(6) NULL,
	source VARCHAR NULL,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT h3_surge_buckets_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX idx_surge_city_hex_band (city_code ASC, h3_index ASC, time_band ASC),
	INDEX index_h3_surge_buckets_on_city_code_and_h3_resolution (city_code ASC, h3_resolution ASC),
	INDEX index_h3_surge_buckets_on_expires_at (expires_at ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_locations (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	zone_id INT8 NOT NULL,
	name VARCHAR NULL,
	pincode VARCHAR NULL,
	lattitude DECIMAL NULL,
	longitude VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT zone_locations_pkey PRIMARY KEY (id ASC),
	INDEX index_zone_locations_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.listings (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	listing_type_id UUID NOT NULL,
	title VARCHAR NULL,
	description STRING NULL,
	delivery_type VARCHAR NULL,
	status VARCHAR NOT NULL DEFAULT 'draft':::STRING,
	approved BOOL NULL DEFAULT false,
	rejection_reason_code VARCHAR NULL,
	rejection_reason_text STRING NULL,
	reviewed_by_id UUID NULL,
	reviewed_at TIMESTAMP NULL,
	swap_completed BOOL NULL DEFAULT false,
	swap_completed_at TIMESTAMP NULL,
	swap_request_id UUID NULL,
	giveaway_claim_id UUID NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	user_id INT8 NOT NULL,
	zone_location_id INT8 NULL,
	item_location_id INT8 NULL,
	pickup_location_id INT8 NULL,
	CONSTRAINT listings_pkey PRIMARY KEY (id ASC),
	INDEX index_listings_on_listing_type_status (listing_type_id ASC, status ASC, created_at ASC),
	INDEX index_listings_on_user_id_and_status (user_id ASC, status ASC),
	INDEX index_listings_on_user_id (user_id ASC),
	INDEX index_listings_on_zone_location_id (zone_location_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.listing_items (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	listing_id UUID NOT NULL,
	name VARCHAR NOT NULL,
	category_id UUID NOT NULL,
	condition VARCHAR NOT NULL,
	usage_duration VARCHAR NULL,
	requires_dismantling BOOL NULL DEFAULT false,
	delivery_vehicle_type VARCHAR NULL,
	description STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT listing_items_pkey PRIMARY KEY (id ASC),
	INDEX index_listing_items_on_category_id (category_id ASC),
	INDEX index_listing_items_on_listing_and_category (listing_id ASC, category_id ASC),
	INDEX index_listing_items_on_listing_id (listing_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.image_hashes (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	listing_id UUID NOT NULL,
	listing_item_id UUID NOT NULL,
	attachment_id UUID NOT NULL,
	phash VARCHAR NOT NULL,
	user_id UUID NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT image_hashes_pkey PRIMARY KEY (id ASC),
	INDEX index_image_hashes_on_listing_id (listing_id ASC),
	INDEX index_image_hashes_on_phash_and_user_id (phash ASC, user_id ASC),
	INDEX index_image_hashes_on_phash (phash ASC),
	INDEX index_image_hashes_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.payment_intents (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	swap_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	platform_fee DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	delivery_charges DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	subtotal DECIMAL(12,2) NOT NULL,
	gst_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	amount DECIMAL(12,2) NOT NULL,
	amount_received DECIMAL(12,2) NULL,
	currency VARCHAR NOT NULL DEFAULT 'INR':::STRING,
	status VARCHAR NOT NULL DEFAULT 'requires_payment_method':::STRING,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	gateway VARCHAR NULL DEFAULT 'razorpay':::STRING,
	gateway_intent_id VARCHAR NULL,
	client_secret VARCHAR NULL,
	last_payment_error JSONB NULL,
	cancellation_reason VARCHAR NULL,
	setup_future_usage VARCHAR NULL,
	receipt_email VARCHAR NULL,
	payment_method_types STRING[] NULL DEFAULT ARRAY[]:::STRING[],
	confirmed_at TIMESTAMP(6) NULL,
	succeeded_at TIMESTAMP(6) NULL,
	cancelled_at TIMESTAMP(6) NULL,
	failed_at TIMESTAMP(6) NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT payment_intents_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_payment_intents_on_gateway_intent_id (gateway_intent_id ASC),
	INDEX index_payment_intents_on_status_and_created_at (status ASC, created_at DESC),
	INDEX index_payment_intents_on_user_id_and_status (user_id ASC, status ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.invoices (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	swap_request_id VARCHAR NULL,
	delivery_order_id VARCHAR NULL,
	payment_intent_id UUID NULL,
	invoice_number VARCHAR NOT NULL,
	invoice_series VARCHAR NULL DEFAULT 'INV':::STRING,
	customer_details JSONB NULL DEFAULT '{}':::JSONB,
	gstin VARCHAR NULL,
	line_items JSONB NULL DEFAULT '[]':::JSONB,
	swap_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	platform_fee DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	delivery_fee DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	insurance_fee DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	discount_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	taxable_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	cgst_rate DECIMAL(5,2) NULL DEFAULT 9.00:::DECIMAL,
	sgst_rate DECIMAL(5,2) NULL DEFAULT 9.00:::DECIMAL,
	igst_rate DECIMAL(5,2) NULL DEFAULT 18.00:::DECIMAL,
	cgst_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	sgst_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	igst_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	total_tax_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	subtotal DECIMAL(12,2) NOT NULL,
	total_amount DECIMAL(12,2) NOT NULL,
	status VARCHAR NULL DEFAULT 'draft':::STRING,
	payment_terms VARCHAR NULL DEFAULT 'Due on receipt':::STRING,
	payment_method VARCHAR NULL,
	is_export BOOL NULL DEFAULT false,
	is_inter_state BOOL NULL DEFAULT false,
	issued_at TIMESTAMP(6) NULL,
	due_date TIMESTAMP(6) NULL,
	paid_at TIMESTAMP(6) NULL,
	refunded_at TIMESTAMP(6) NULL,
	notes STRING NULL,
	terms_and_conditions STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT invoices_pkey PRIMARY KEY (id ASC),
	INDEX index_invoices_on_gstin (gstin ASC),
	UNIQUE INDEX index_invoices_on_invoice_number (invoice_number ASC),
	INDEX index_invoices_on_payment_intent_id (payment_intent_id ASC),
	INDEX index_invoices_on_status_and_issued_at (status ASC, issued_at ASC),
	INDEX index_invoices_on_swap_request_id (swap_request_id ASC),
	INDEX index_invoices_on_user_id_and_created_at (user_id ASC, created_at DESC)
) WITH (schema_locked = true);"
"CREATE TABLE public.listing_approval_settings (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	zone_id INT8 NOT NULL,
	manual_approval_required BOOL NULL,
	auto_approval_enabled BOOL NULL,
	max_items_per_user INT8 NULL,
	approval_criteria STRING NULL,
	status VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT listing_approval_settings_pkey PRIMARY KEY (id ASC),
	INDEX index_listing_approval_settings_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.listing_types (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	name VARCHAR NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT listing_types_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_listing_types_on_name (name ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.listing_validations (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	listing_id UUID NOT NULL,
	status VARCHAR NOT NULL DEFAULT 'pending':::STRING,
	decision VARCHAR NULL,
	confidence FLOAT8 NULL,
	provider VARCHAR NULL,
	item_results JSONB NOT NULL DEFAULT '[]':::JSONB,
	raw_response JSONB NOT NULL DEFAULT '{}':::JSONB,
	error_message STRING NULL,
	attempt_count INT8 NOT NULL DEFAULT 0:::INT8,
	validated_at TIMESTAMP NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	admin_override BOOL NULL DEFAULT false,
	admin_decision VARCHAR NULL,
	admin_reason STRING NULL,
	reviewed_by_id UUID NULL,
	CONSTRAINT listing_validations_pkey PRIMARY KEY (id ASC),
	INDEX index_listing_validations_on_listing_id_and_status (listing_id ASC, status ASC),
	INDEX index_listing_validations_on_listing_id (listing_id ASC),
	INDEX idx_lv_status_decision (status ASC, decision ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.merchant_pricing_policies (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	merchant_id VARCHAR NOT NULL,
	merchant_name VARCHAR NULL,
	city_code VARCHAR NULL,
	vehicle_type VARCHAR NULL,
	policy_type VARCHAR NOT NULL,
	value_paise INT8 NULL,
	value_pct FLOAT8 NULL,
	priority INT8 NULL DEFAULT 0:::INT8,
	active BOOL NULL DEFAULT true,
	effective_from DATE NULL,
	effective_until DATE NULL,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT merchant_pricing_policies_pkey PRIMARY KEY (id ASC),
	INDEX index_merchant_pricing_policies_on_city_code_and_vehicle_type (city_code ASC, vehicle_type ASC),
	INDEX index_merchant_pricing_policies_on_merchant_id_and_active (merchant_id ASC, active ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.notifications (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	title VARCHAR NOT NULL,
	body VARCHAR NULL,
	notification_type VARCHAR NOT NULL DEFAULT 'general':::STRING,
	data JSONB NULL DEFAULT '{}':::JSONB,
	read_at TIMESTAMP(6) NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT notifications_pkey PRIMARY KEY (id ASC),
	INDEX idx_notifications_user_type (user_id ASC, notification_type ASC),
	INDEX idx_notifications_user_read_created (user_id ASC, read_at ASC, created_at DESC)
) WITH (schema_locked = true);"
"CREATE TABLE public.otp_codes (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	phone VARCHAR NULL,
	otp_code VARCHAR NOT NULL,
	expires_at TIMESTAMP(6) NULL,
	verified BOOL NULL DEFAULT false,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	user_id INT8 NULL,
	email VARCHAR NULL,
	CONSTRAINT otp_codes_pkey PRIMARY KEY (id ASC),
	INDEX index_otp_codes_on_email (email ASC),
	INDEX index_otp_codes_on_phone (phone ASC),
	INDEX index_otp_codes_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.payment_methods (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	method_type VARCHAR NOT NULL,
	details JSONB NOT NULL DEFAULT '{}':::JSONB,
	billing_details JSONB NULL DEFAULT '{}':::JSONB,
	gateway_token VARCHAR NULL,
	gateway_customer_id VARCHAR NULL,
	gateway VARCHAR NULL DEFAULT 'razorpay':::STRING,
	fingerprint VARCHAR NULL,
	network VARCHAR NULL,
	issuer_country VARCHAR NULL DEFAULT 'IN':::STRING,
	card_type VARCHAR NULL,
	usage_count INT8 NULL DEFAULT 0:::INT8,
	last_used_at TIMESTAMP(6) NULL,
	is_default BOOL NULL DEFAULT false,
	is_verified BOOL NULL DEFAULT false,
	is_active BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT payment_methods_pkey PRIMARY KEY (id ASC),
	INDEX index_payment_methods_on_fingerprint (fingerprint ASC),
	UNIQUE INDEX index_payment_methods_on_gateway_token (gateway_token ASC),
	INDEX index_payment_methods_on_user_id_and_is_active (user_id ASC, is_active ASC),
	INDEX index_payment_methods_on_user_id_and_is_default (user_id ASC, is_default ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.payment_charges (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	intent_id UUID NOT NULL,
	payment_method_id UUID NULL,
	gateway_charge_id VARCHAR NOT NULL,
	gateway VARCHAR NULL DEFAULT 'razorpay':::STRING,
	amount DECIMAL(12,2) NOT NULL,
	gateway_fee DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	gateway_tax DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	refunded_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	status VARCHAR NOT NULL DEFAULT 'pending':::STRING,
	payment_method_type VARCHAR NULL,
	payment_method_details JSONB NULL DEFAULT '{}':::JSONB,
	failure_code VARCHAR NULL,
	failure_reason VARCHAR NULL,
	failure_message STRING NULL,
	settlement_id VARCHAR NULL,
	settled_at TIMESTAMP(6) NULL,
	bank_reference VARCHAR NULL,
	authorized_at TIMESTAMP(6) NULL,
	captured_at TIMESTAMP(6) NULL,
	dispute_id VARCHAR NULL,
	dispute_status VARCHAR NULL,
	dispute_opened_at TIMESTAMP(6) NULL,
	dispute_closed_at TIMESTAMP(6) NULL,
	gateway_response JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT payment_charges_pkey PRIMARY KEY (id ASC),
	INDEX index_payment_charges_on_dispute_id (dispute_id ASC),
	UNIQUE INDEX index_payment_charges_on_gateway_charge_id (gateway_charge_id ASC),
	INDEX index_payment_charges_on_intent_id (intent_id ASC),
	INDEX index_payment_charges_on_payment_method_id (payment_method_id ASC),
	INDEX index_payment_charges_on_settlement_id (settlement_id ASC),
	INDEX index_payment_charges_on_status_and_created_at (status ASC, created_at ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.payment_refunds (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	charge_id UUID NOT NULL,
	amount DECIMAL(12,2) NOT NULL,
	gateway_refund_fee DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	reason VARCHAR NULL,
	refund_type VARCHAR NULL DEFAULT 'full':::STRING,
	speed VARCHAR NULL DEFAULT 'normal':::STRING,
	status VARCHAR NOT NULL DEFAULT 'pending':::STRING,
	initiated_by_id INT8 NULL,
	initiated_by_role VARCHAR NULL,
	initiated_at TIMESTAMP(6) NULL,
	gateway VARCHAR NULL DEFAULT 'razorpay':::STRING,
	gateway_refund_id VARCHAR NULL,
	gateway_response JSONB NULL DEFAULT '{}':::JSONB,
	succeeded_at TIMESTAMP(6) NULL,
	failed_at TIMESTAMP(6) NULL,
	failure_reason STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT payment_refunds_pkey PRIMARY KEY (id ASC),
	INDEX index_payment_refunds_on_charge_id (charge_id ASC),
	UNIQUE INDEX index_payment_refunds_on_gateway_refund_id (gateway_refund_id ASC),
	INDEX index_payment_refunds_on_initiated_by_id (initiated_by_id ASC),
	INDEX index_payment_refunds_on_status_and_created_at (status ASC, created_at ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.payment_settlements (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	gateway_settlement_id VARCHAR NOT NULL,
	gateway VARCHAR NULL DEFAULT 'razorpay':::STRING,
	amount DECIMAL(12,2) NOT NULL,
	fee DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	tax DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	net_amount DECIMAL(12,2) NOT NULL,
	utr_number VARCHAR NULL,
	settled_at TIMESTAMP(6) NULL,
	status VARCHAR NULL DEFAULT 'pending':::STRING,
	charge_count INT8 NULL DEFAULT 0:::INT8,
	charge_ids JSONB NULL DEFAULT '[]':::JSONB,
	gateway_response JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT payment_settlements_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_payment_settlements_on_gateway_settlement_id (gateway_settlement_id ASC),
	INDEX index_payment_settlements_on_settled_at (settled_at ASC),
	INDEX index_payment_settlements_on_status_and_created_at (status ASC, created_at ASC),
	INDEX index_payment_settlements_on_utr_number (utr_number ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.payment_webhook_events (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	intent_id UUID NULL,
	event_type VARCHAR NOT NULL,
	payload JSONB NOT NULL,
	gateway_event_id VARCHAR NULL,
	gateway VARCHAR NULL DEFAULT 'razorpay':::STRING,
	signature VARCHAR NULL,
	ip_address VARCHAR NULL,
	signature_verified BOOL NULL DEFAULT false,
	processed BOOL NULL DEFAULT false,
	processed_at TIMESTAMP(6) NULL,
	processing_error STRING NULL,
	retry_count INT8 NULL DEFAULT 0:::INT8,
	next_retry_at TIMESTAMP(6) NULL,
	received_at TIMESTAMP(6) NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT payment_webhook_events_pkey PRIMARY KEY (id ASC),
	INDEX index_payment_webhook_events_on_event_type (event_type ASC),
	UNIQUE INDEX index_payment_webhook_events_on_gateway_event_id (gateway_event_id ASC),
	INDEX index_payment_webhook_events_on_intent_id (intent_id ASC),
	INDEX index_payment_webhook_events_on_processed_and_created_at (processed ASC, created_at ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.payout_accounts (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	account_type VARCHAR NOT NULL,
	details JSONB NOT NULL DEFAULT '{}':::JSONB,
	is_verified BOOL NULL DEFAULT false,
	verified_at TIMESTAMP(6) NULL,
	verification_method VARCHAR NULL,
	verification_details JSONB NULL DEFAULT '{}':::JSONB,
	is_default BOOL NULL DEFAULT false,
	is_active BOOL NULL DEFAULT true,
	gateway_beneficiary_id VARCHAR NULL,
	gateway VARCHAR NULL DEFAULT 'decentro':::STRING,
	payout_count INT8 NULL DEFAULT 0:::INT8,
	last_payout_at TIMESTAMP(6) NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT payout_accounts_pkey PRIMARY KEY (id ASC),
	INDEX index_payout_accounts_on_gateway_beneficiary_id (gateway_beneficiary_id ASC),
	INDEX index_payout_accounts_on_user_id_and_is_active (user_id ASC, is_active ASC),
	INDEX index_payout_accounts_on_user_id_and_is_default (user_id ASC, is_default ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.payouts (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	account_id UUID NOT NULL,
	wallet_id UUID NOT NULL,
	amount DECIMAL(12,2) NOT NULL,
	fee DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	tax DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	net_amount DECIMAL(12,2) NOT NULL,
	status VARCHAR NOT NULL DEFAULT 'pending':::STRING,
	gateway VARCHAR NULL DEFAULT 'decentro':::STRING,
	gateway_payout_id VARCHAR NULL,
	gateway_utr VARCHAR NULL,
	transfer_mode VARCHAR NULL,
	source_type VARCHAR NULL,
	source_id VARCHAR NULL,
	failure_code VARCHAR NULL,
	failure_message STRING NULL,
	gateway_response JSONB NULL DEFAULT '{}':::JSONB,
	initiated_at TIMESTAMP(6) NULL,
	processing_at TIMESTAMP(6) NULL,
	completed_at TIMESTAMP(6) NULL,
	failed_at TIMESTAMP(6) NULL,
	notes STRING NULL,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT payouts_pkey PRIMARY KEY (id ASC),
	INDEX index_payouts_on_account_id (account_id ASC),
	INDEX index_payouts_on_gateway_payout_id (gateway_payout_id ASC),
	INDEX index_payouts_on_source_type_and_source_id (source_type ASC, source_id ASC),
	INDEX index_payouts_on_status_and_initiated_at (status ASC, initiated_at DESC),
	INDEX index_payouts_on_user_id_and_status (user_id ASC, status ASC),
	INDEX index_payouts_on_wallet_id (wallet_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_delivery_configs (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	zone_id INT8 NOT NULL,
	delivery_partner_id INT8 NOT NULL,
	fee_table JSONB NULL,
	sla_hours INT8 NULL,
	self_pickup_enabled BOOL NULL,
	courier_delivery_enabled BOOL NULL,
	expedited_delivery_enabled BOOL NULL,
	max_delivery_time INT8 NULL,
	delivery_cost_multiplier FLOAT8 NULL,
	status VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT zone_delivery_configs_pkey PRIMARY KEY (id ASC),
	INDEX index_zone_delivery_configs_on_delivery_partner_id (delivery_partner_id ASC),
	INDEX index_zone_delivery_configs_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pickup_slots (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	zone_delivery_config_id INT8 NOT NULL,
	delivery_partner_id INT8 NOT NULL,
	pickup_day VARCHAR NULL,
	start_time TIME NULL,
	end_time TIME NULL,
	available BOOL NULL,
	max_capacity INT8 NULL,
	status VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pickup_slots_pkey PRIMARY KEY (id ASC),
	INDEX index_pickup_slots_on_delivery_partner_id (delivery_partner_id ASC),
	INDEX index_pickup_slots_on_zone_delivery_config_id (zone_delivery_config_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.platforms (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	platform_fee DECIMAL NULL,
	gst_rate DECIMAL NULL,
	escrow_enabled BOOL NULL,
	currency_code VARCHAR NULL,
	locale VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	platform_fee_percentage DECIMAL(5,2) NULL DEFAULT 3.00:::DECIMAL,
	min_platform_fee DECIMAL(10,2) NULL DEFAULT 10.00:::DECIMAL,
	payout_fee_imps DECIMAL(10,2) NULL DEFAULT 5.00:::DECIMAL,
	payout_fee_upi DECIMAL(10,2) NULL DEFAULT 0.00:::DECIMAL,
	payout_fee_neft DECIMAL(10,2) NULL DEFAULT 2.50:::DECIMAL,
	payout_fee_rtgs DECIMAL(10,2) NULL DEFAULT 20.00:::DECIMAL,
	default_payment_gateway VARCHAR NULL DEFAULT 'razorpay':::STRING,
	enabled_payment_gateways VARCHAR NULL DEFAULT 'razorpay':::STRING,
	payout_source VARCHAR NULL DEFAULT 'own_capital':::STRING,
	ai_auto_approve_threshold FLOAT8 NULL DEFAULT 0.85:::FLOAT8,
	ai_auto_reject_threshold FLOAT8 NULL DEFAULT 0.5:::FLOAT8,
	ai_validation_enabled BOOL NULL DEFAULT true,
	ai_weight FLOAT8 NULL DEFAULT 0.4:::FLOAT8,
	forensics_weight FLOAT8 NULL DEFAULT 0.2:::FLOAT8,
	trust_weight FLOAT8 NULL DEFAULT 0.15:::FLOAT8,
	quality_weight FLOAT8 NULL DEFAULT 0.15:::FLOAT8,
	duplicate_weight FLOAT8 NULL DEFAULT 0.1:::FLOAT8,
	payment_deadline_mutual_hours INT8 NOT NULL DEFAULT 12:::INT8,
	payment_deadline_monetary_hours INT8 NOT NULL DEFAULT 12:::INT8,
	payment_deadline_partial_paid_hours INT8 NOT NULL DEFAULT 24:::INT8,
	CONSTRAINT platforms_pkey PRIMARY KEY (id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.porter_benchmarks (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	city_code VARCHAR NOT NULL DEFAULT 'hyd':::STRING,
	route_key VARCHAR NOT NULL,
	pickup_address VARCHAR NOT NULL,
	drop_address VARCHAR NOT NULL,
	pickup_lat DECIMAL(10,6) NULL,
	pickup_lng DECIMAL(10,6) NULL,
	drop_lat DECIMAL(10,6) NULL,
	drop_lng DECIMAL(10,6) NULL,
	vehicle_type VARCHAR NOT NULL,
	time_band VARCHAR NOT NULL,
	porter_price_inr INT8 NULL,
	our_price_inr INT8 NULL,
	distance_m INT8 NULL,
	delta_pct FLOAT8 NULL,
	status VARCHAR NULL DEFAULT 'entered':::STRING,
	entered_by VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT porter_benchmarks_pkey PRIMARY KEY (id ASC),
	INDEX index_porter_benchmarks_on_city_code_and_time_band (city_code ASC, time_band ASC),
	UNIQUE INDEX idx_porter_bench_route_vt_tb (route_key ASC, vehicle_type ASC, time_band ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.porter_screenshots (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	city_code VARCHAR NULL DEFAULT 'hyd':::STRING,
	time_band VARCHAR NULL,
	notes VARCHAR NULL,
	uploaded_by VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT porter_screenshots_pkey PRIMARY KEY (id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.preferred_exchange_categories (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	listing_id UUID NOT NULL,
	category_id UUID NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT preferred_exchange_categories_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_preferred_exchange_on_listing_and_category (listing_id ASC, category_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.premium_feature_flags (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	name VARCHAR NOT NULL,
	description STRING NULL,
	enabled BOOL NULL DEFAULT false,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT premium_feature_flags_pkey PRIMARY KEY (id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_quotes (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	request_id VARCHAR NULL,
	city_code VARCHAR NOT NULL,
	vehicle_type VARCHAR NOT NULL,
	pickup_raw_lat DECIMAL(10,6) NULL,
	pickup_raw_lng DECIMAL(10,6) NULL,
	drop_raw_lat DECIMAL(10,6) NULL,
	drop_raw_lng DECIMAL(10,6) NULL,
	pickup_norm_lat DECIMAL(10,6) NULL,
	pickup_norm_lng DECIMAL(10,6) NULL,
	drop_norm_lat DECIMAL(10,6) NULL,
	drop_norm_lng DECIMAL(10,6) NULL,
	distance_m INT8 NULL,
	duration_s INT8 NULL,
	route_provider VARCHAR NULL,
	route_cache_key VARCHAR NULL,
	price_paise INT8 NOT NULL,
	price_confidence VARCHAR NULL DEFAULT 'estimated':::STRING,
	pricing_version VARCHAR NULL DEFAULT 'v1':::STRING,
	breakdown_json JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	valid_until TIMESTAMP(6) NULL,
	scheduled_for TIMESTAMP(6) NULL,
	is_scheduled BOOL NULL DEFAULT false,
	linked_quote_id UUID NULL,
	trip_leg VARCHAR NULL,
	weight_kg DECIMAL(8,2) NULL,
	vendor_predicted_paise INT8 NULL,
	vendor_code VARCHAR NULL,
	margin_paise INT8 NULL,
	margin_pct DECIMAL(6,2) NULL,
	vendor_confidence VARCHAR NULL DEFAULT 'none':::STRING,
	pickup_h3_r8 VARCHAR NULL,
	drop_h3_r8 VARCHAR NULL,
	pickup_h3_r7 VARCHAR NULL,
	drop_h3_r7 VARCHAR NULL,
	h3_surge_multiplier FLOAT8 NULL DEFAULT 1.0:::FLOAT8,
	route_segments_json JSONB NULL,
	weather_condition VARCHAR NULL,
	weather_multiplier FLOAT8 NULL DEFAULT 1.0:::FLOAT8,
	backhaul_multiplier FLOAT8 NULL DEFAULT 1.0:::FLOAT8,
	estimated_waiting_charge_paise INT8 NULL DEFAULT 0:::INT8,
	cancellation_risk_multiplier FLOAT8 NULL DEFAULT 1.0:::FLOAT8,
	CONSTRAINT pricing_quotes_pkey PRIMARY KEY (id ASC),
	INDEX idx_quotes_drop_h3 (city_code ASC, drop_h3_r8 ASC),
	INDEX idx_quotes_pickup_h3 (city_code ASC, pickup_h3_r8 ASC),
	INDEX index_pricing_quotes_on_city_code (city_code ASC),
	INDEX index_pricing_quotes_on_created_at (created_at ASC),
	INDEX index_pricing_quotes_on_linked_quote_id (linked_quote_id ASC),
	INDEX index_pricing_quotes_on_request_id (request_id ASC),
	INDEX index_pricing_quotes_on_valid_until (valid_until ASC),
	INDEX index_pricing_quotes_on_vehicle_type (vehicle_type ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_actuals (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	pricing_quote_id UUID NOT NULL,
	vendor VARCHAR NULL DEFAULT 'porter':::STRING,
	vendor_booking_ref VARCHAR NULL,
	actual_price_paise INT8 NOT NULL,
	notes STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	actual_vendor_code VARCHAR NULL,
	actual_breakdown_json JSONB NULL DEFAULT '{}':::JSONB,
	predicted_vendor_paise INT8 NULL,
	prediction_variance_paise INT8 NULL,
	prediction_variance_pct DECIMAL(6,2) NULL,
	CONSTRAINT pricing_actuals_pkey PRIMARY KEY (id ASC),
	INDEX index_pricing_actuals_on_pricing_quote_id (pricing_quote_id ASC),
	INDEX index_pricing_actuals_on_vendor (vendor ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_backtests (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	city_code VARCHAR NOT NULL,
	candidate_config_id UUID NULL,
	baseline_config_id UUID NULL,
	status VARCHAR NULL DEFAULT 'pending':::STRING,
	sample_size INT8 NULL,
	completed_replays INT8 NULL DEFAULT 0:::INT8,
	results JSONB NULL DEFAULT '{}':::JSONB,
	replay_details JSONB NULL DEFAULT '[]':::JSONB,
	triggered_by VARCHAR NULL,
	started_at TIMESTAMP(6) NULL,
	completed_at TIMESTAMP(6) NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_backtests_pkey PRIMARY KEY (id ASC),
	INDEX index_pricing_backtests_on_city_code_and_status (city_code ASC, status ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_change_logs (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	entity_type VARCHAR NOT NULL,
	entity_id UUID NOT NULL,
	action VARCHAR NOT NULL,
	actor VARCHAR NOT NULL,
	before_state JSONB NULL DEFAULT '{}':::JSONB,
	after_state JSONB NULL DEFAULT '{}':::JSONB,
	diff JSONB NULL DEFAULT '{}':::JSONB,
	city_code VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_change_logs_pkey PRIMARY KEY (id ASC),
	INDEX index_pricing_change_logs_on_city_code (city_code ASC),
	INDEX index_pricing_change_logs_on_entity_type_and_entity_id (entity_type ASC, entity_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_configs (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	city_code VARCHAR NOT NULL,
	vehicle_type VARCHAR NOT NULL,
	timezone VARCHAR NOT NULL DEFAULT 'Asia/Kolkata':::STRING,
	base_fare_paise INT8 NOT NULL,
	min_fare_paise INT8 NOT NULL,
	base_distance_m INT8 NOT NULL DEFAULT 0:::INT8,
	per_km_rate_paise INT8 NOT NULL,
	vehicle_multiplier DECIMAL(6,3) NULL DEFAULT 1.000:::DECIMAL,
	city_multiplier DECIMAL(6,3) NULL DEFAULT 1.000:::DECIMAL,
	surge_multiplier DECIMAL(6,3) NULL DEFAULT 1.000:::DECIMAL,
	variance_buffer_pct DECIMAL(6,3) NULL DEFAULT 0.000:::DECIMAL,
	variance_buffer_min_paise INT8 NULL DEFAULT 0:::INT8,
	variance_buffer_max_paise INT8 NULL DEFAULT 0:::INT8,
	high_value_threshold_paise INT8 NULL DEFAULT 0:::INT8,
	high_value_buffer_pct DECIMAL(6,3) NULL DEFAULT 0.000:::DECIMAL,
	high_value_buffer_min_paise INT8 NULL DEFAULT 0:::INT8,
	min_margin_pct DECIMAL(6,3) NULL DEFAULT 0.000:::DECIMAL,
	min_margin_flat_paise INT8 NULL DEFAULT 0:::INT8,
	active BOOL NULL DEFAULT true,
	version INT8 NULL DEFAULT 1:::INT8,
	effective_from TIMESTAMP(6) NULL,
	effective_until TIMESTAMP(6) NULL,
	created_by_id INT8 NULL,
	notes STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	vendor_vehicle_code VARCHAR NULL,
	weight_capacity_kg INT8 NULL,
	display_name VARCHAR NULL,
	description STRING NULL,
	quote_validity_minutes INT8 NULL DEFAULT 10:::INT8,
	scheduled_discount_pct DECIMAL(5,2) NULL DEFAULT 0.00:::DECIMAL,
	scheduled_threshold_hours INT8 NULL DEFAULT 2:::INT8,
	return_trip_discount_pct DECIMAL(5,2) NULL DEFAULT 10.00:::DECIMAL,
	weight_multiplier_tiers JSONB NULL DEFAULT '[{""max_kg"": 15, ""mult"": 1.0}, {""max_kg"": 50, ""mult"": 1.1}, {""max_kg"": 200, ""mult"": 1.2}, {""max_kg"": null, ""mult"": 1.4}]':::JSONB,
	per_min_rate_paise INT8 NULL DEFAULT 0:::INT8,
	free_pickup_radius_m INT8 NULL DEFAULT 0:::INT8,
	dead_km_per_km_rate_paise INT8 NULL DEFAULT 0:::INT8,
	dead_km_enabled BOOL NULL DEFAULT false,
	approval_status VARCHAR NULL DEFAULT 'approved':::STRING,
	submitted_by VARCHAR NULL,
	reviewed_by VARCHAR NULL,
	reviewed_at TIMESTAMP(6) NULL,
	rejection_reason VARCHAR NULL,
	change_summary STRING NULL,
	weather_multipliers JSONB NULL,
	max_backhaul_premium FLOAT8 NULL DEFAULT 0.2:::FLOAT8,
	waiting_per_min_rate_paise INT8 NULL DEFAULT 0:::INT8,
	free_waiting_minutes INT8 NULL DEFAULT 10:::INT8,
	CONSTRAINT pricing_configs_pkey PRIMARY KEY (id ASC),
	INDEX index_pricing_configs_on_approval_status (approval_status ASC),
	INDEX idx_pricing_configs_current (city_code ASC, vehicle_type ASC, active ASC, effective_from ASC),
	UNIQUE INDEX idx_on_city_code_vehicle_type_version_008f27eb85 (city_code ASC, vehicle_type ASC, version ASC),
	INDEX index_pricing_configs_on_vendor_code_and_city (vendor_vehicle_code ASC, city_code ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_distance_slabs (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	pricing_config_id UUID NOT NULL,
	min_distance_m INT8 NOT NULL DEFAULT 0:::INT8,
	max_distance_m INT8 NULL,
	per_km_rate_paise INT8 NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_distance_slabs_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX idx_slabs_config_min_distance (pricing_config_id ASC, min_distance_m ASC),
	INDEX index_pricing_distance_slabs_on_pricing_config_id (pricing_config_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_emergency_freezes (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	city_code VARCHAR NULL,
	reason VARCHAR NOT NULL,
	activated_by VARCHAR NOT NULL,
	deactivated_by VARCHAR NULL,
	activated_at TIMESTAMP(6) NOT NULL,
	deactivated_at TIMESTAMP(6) NULL,
	active BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_emergency_freezes_pkey PRIMARY KEY (id ASC),
	INDEX index_pricing_emergency_freezes_on_city_code_and_active (city_code ASC, active ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_model_configs (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	algorithm_name VARCHAR NOT NULL,
	model_version VARCHAR NOT NULL,
	mode VARCHAR NULL DEFAULT 'shadow':::STRING,
	canary_pct INT8 NULL DEFAULT 0:::INT8,
	city_code VARCHAR NULL,
	parameters JSONB NULL DEFAULT '{}':::JSONB,
	active BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_model_configs_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_pricing_model_configs_on_algorithm_name_and_city_code (algorithm_name ASC, city_code ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_model_scores (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	pricing_quote_id UUID NULL,
	model_version VARCHAR NOT NULL,
	city_code VARCHAR NOT NULL,
	vehicle_type VARCHAR NULL,
	deterministic_price_paise INT8 NULL,
	model_suggested_paise INT8 NULL,
	expected_acceptance_pct FLOAT8 NULL,
	expected_margin_pct FLOAT8 NULL,
	features JSONB NULL DEFAULT '{}':::JSONB,
	model_metadata JSONB NULL DEFAULT '{}':::JSONB,
	outcome VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_model_scores_pkey PRIMARY KEY (id ASC),
	INDEX index_pricing_model_scores_on_model_version_and_city_code (model_version ASC, city_code ASC),
	INDEX index_pricing_model_scores_on_pricing_quote_id (pricing_quote_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_outcomes (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	pricing_quote_id UUID NOT NULL,
	outcome VARCHAR NOT NULL,
	city_code VARCHAR NOT NULL,
	vehicle_type VARCHAR NULL,
	time_band VARCHAR NULL,
	pickup_zone_code VARCHAR NULL,
	drop_zone_code VARCHAR NULL,
	h3_index_r7 VARCHAR NULL,
	quoted_price_paise INT8 NULL,
	response_time_seconds INT8 NULL,
	rejection_reason VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_outcomes_pkey PRIMARY KEY (id ASC),
	INDEX index_pricing_outcomes_on_city_code_and_outcome (city_code ASC, outcome ASC),
	INDEX index_pricing_outcomes_on_h3_index_r7_and_time_band (h3_index_r7 ASC, time_band ASC),
	INDEX index_pricing_outcomes_on_pricing_quote_id (pricing_quote_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_quote_decisions (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	pricing_quote_id UUID NULL,
	pricing_config_id UUID NULL,
	request_id VARCHAR NULL,
	city_code VARCHAR NOT NULL,
	vehicle_type VARCHAR NOT NULL,
	quote_time TIMESTAMP(6) NULL,
	scheduled_for TIMESTAMP(6) NULL,
	decision_status VARCHAR NOT NULL DEFAULT 'quoted':::STRING,
	route_provider VARCHAR NULL,
	route_cache_key VARCHAR NULL,
	pricing_version VARCHAR NULL,
	pricing_source VARCHAR NULL,
	pricing_mode VARCHAR NULL,
	price_paise INT8 NULL,
	request_snapshot_json JSONB NOT NULL DEFAULT '{}':::JSONB,
	route_snapshot_json JSONB NOT NULL DEFAULT '{}':::JSONB,
	pricing_snapshot_json JSONB NOT NULL DEFAULT '{}':::JSONB,
	breakdown_json JSONB NOT NULL DEFAULT '{}':::JSONB,
	error_message STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	time_band VARCHAR NULL,
	pickup_zone_code VARCHAR NULL,
	drop_zone_code VARCHAR NULL,
	quoted_price_paise INT8 NULL,
	actual_price_paise INT8 NULL,
	variance_paise INT8 NULL,
	variance_pct FLOAT8 NULL,
	pricing_tier VARCHAR NULL,
	distance_km FLOAT8 NULL,
	config_version VARCHAR NULL,
	within_threshold BOOL NULL DEFAULT true,
	CONSTRAINT pricing_quote_decisions_pkey PRIMARY KEY (id ASC),
	INDEX idx_quote_decisions_city_vehicle_created (city_code ASC, vehicle_type ASC, created_at ASC),
	INDEX index_pricing_quote_decisions_on_decision_status (decision_status ASC),
	INDEX index_pricing_quote_decisions_on_pricing_config_id (pricing_config_id ASC),
	UNIQUE INDEX idx_quote_decisions_quote_unique (pricing_quote_id ASC),
	INDEX index_pricing_quote_decisions_on_pricing_quote_id (pricing_quote_id ASC),
	INDEX index_pricing_quote_decisions_on_pricing_version (pricing_version ASC),
	INDEX index_pricing_quote_decisions_on_request_id (request_id ASC),
	INDEX index_pricing_quote_decisions_on_within_threshold (within_threshold ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_quote_replays (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	pricing_quote_decision_id UUID NOT NULL,
	pricing_config_id UUID NULL,
	replayed_by_id INT8 NULL,
	mode VARCHAR NOT NULL DEFAULT 'current':::STRING,
	replay_status VARCHAR NOT NULL DEFAULT 'succeeded':::STRING,
	pricing_version VARCHAR NULL,
	price_paise INT8 NULL,
	breakdown_json JSONB NOT NULL DEFAULT '{}':::JSONB,
	comparison_json JSONB NOT NULL DEFAULT '{}':::JSONB,
	error_message STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_quote_replays_pkey PRIMARY KEY (id ASC),
	INDEX index_pricing_quote_replays_on_mode (mode ASC),
	INDEX index_pricing_quote_replays_on_pricing_config_id (pricing_config_id ASC),
	INDEX idx_quote_replays_decision_created (pricing_quote_decision_id ASC, created_at ASC),
	INDEX index_pricing_quote_replays_on_pricing_quote_decision_id (pricing_quote_decision_id ASC),
	INDEX index_pricing_quote_replays_on_replay_status (replay_status ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_rollout_flags (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	flag_name VARCHAR NOT NULL,
	city_code VARCHAR NULL,
	enabled BOOL NULL DEFAULT false,
	rollout_pct INT8 NULL DEFAULT 0:::INT8,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_rollout_flags_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_pricing_rollout_flags_on_flag_name_and_city_code (flag_name ASC, city_code ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_surge_rules (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	pricing_config_id UUID NOT NULL,
	rule_type VARCHAR NOT NULL,
	condition_json JSONB NOT NULL DEFAULT '{}':::JSONB,
	multiplier DECIMAL(6,3) NOT NULL,
	priority INT8 NULL DEFAULT 100:::INT8,
	active BOOL NULL DEFAULT true,
	created_by_id INT8 NULL,
	notes STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT pricing_surge_rules_pkey PRIMARY KEY (id ASC),
	INDEX idx_pricing_surge_rules_active (pricing_config_id ASC, active ASC, priority ASC),
	INDEX index_pricing_surge_rules_on_rule_type (rule_type ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.pricing_zone_multipliers (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	zone_code VARCHAR NOT NULL,
	zone_name VARCHAR NULL,
	city_code VARCHAR NULL DEFAULT 'hyd':::STRING,
	lat_min DECIMAL(10,6) NULL,
	lat_max DECIMAL(10,6) NULL,
	lng_min DECIMAL(10,6) NULL,
	lng_max DECIMAL(10,6) NULL,
	multiplier DECIMAL(4,2) NULL DEFAULT 1.00:::DECIMAL,
	active BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	small_vehicle_mult DECIMAL(4,2) NULL DEFAULT 1.00:::DECIMAL,
	mid_truck_mult DECIMAL(4,2) NULL DEFAULT 1.00:::DECIMAL,
	heavy_truck_mult DECIMAL(4,2) NULL DEFAULT 1.00:::DECIMAL,
	zone_type VARCHAR NULL,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	CONSTRAINT pricing_zone_multipliers_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX index_pricing_zone_multipliers_on_city_code_and_zone_code (city_code ASC, zone_code ASC),
	INDEX idx_zone_coords (lat_min ASC, lat_max ASC, lng_min ASC, lng_max ASC),
	INDEX index_pricing_zone_multipliers_on_zone_type (zone_type ASC)
) WITH (schema_locked = true);
COMMENT ON COLUMN public.pricing_zone_multipliers.small_vehicle_mult IS 'Multiplier for 2W/Scooter/Mini3W';
COMMENT ON COLUMN public.pricing_zone_multipliers.mid_truck_mult IS 'Multiplier for 3W/TataAce/Pickup8ft';
COMMENT ON COLUMN public.pricing_zone_multipliers.heavy_truck_mult IS 'Multiplier for Eeco/Tata407/Canter';
COMMENT ON COLUMN public.pricing_zone_multipliers.zone_type IS 'Business zone classification';
COMMENT ON COLUMN public.pricing_zone_multipliers.metadata IS 'Extensible metadata for zone-specific features';"
"CREATE TABLE public.profile_settings (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	preferences JSONB NULL DEFAULT '{}':::JSONB,
	app_language VARCHAR NULL,
	dark_mode_enabled BOOL NULL DEFAULT false,
	notification_enabled BOOL NULL DEFAULT true,
	locale VARCHAR NULL DEFAULT 'en':::STRING,
	theme_preference VARCHAR NULL DEFAULT 'light':::STRING,
	user_status VARCHAR NULL DEFAULT 'active':::STRING,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT profile_settings_pkey PRIMARY KEY (id ASC),
	INDEX index_profile_settings_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.prohibited_keywords (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	keyword VARCHAR NULL,
	category VARCHAR NULL,
	status VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT prohibited_keywords_pkey PRIMARY KEY (id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.referral_rewards (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	user_id INT8 NOT NULL,
	referred_user_id INT8 NOT NULL,
	coins_earned INT8 NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT referral_rewards_pkey PRIMARY KEY (id ASC),
	INDEX index_referral_rewards_on_referred_user_id (referred_user_id ASC),
	UNIQUE INDEX index_referral_rewards_on_user_id_and_referred_user_id (user_id ASC, referred_user_id ASC),
	INDEX index_referral_rewards_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.referral_rules (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	zone_id INT8 NOT NULL,
	referral_code_reward INT8 NULL,
	referee_reward INT8 NULL,
	referral_limit INT8 NULL,
	status VARCHAR NULL DEFAULT 'active':::STRING,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT referral_rules_pkey PRIMARY KEY (id ASC),
	INDEX index_referral_rules_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.reviews (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	reviewer_id INT8 NOT NULL,
	reviewee_id INT8 NOT NULL,
	swap_request_id VARCHAR NULL,
	rating INT8 NOT NULL,
	comment STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT reviews_pkey PRIMARY KEY (id ASC),
	INDEX idx_reviews_reviewee_created (reviewee_id ASC, created_at DESC),
	UNIQUE INDEX idx_reviews_reviewer_swap_unique (reviewer_id ASC, swap_request_id ASC),
	INDEX idx_reviews_reviewer (reviewer_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.support_tickets (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	category VARCHAR NOT NULL,
	description STRING NOT NULL,
	photo_urls JSONB NULL DEFAULT '[]':::JSONB,
	status VARCHAR NOT NULL DEFAULT 'open':::STRING,
	priority VARCHAR NULL DEFAULT 'medium':::STRING,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT support_tickets_pkey PRIMARY KEY (id ASC),
	INDEX index_support_tickets_on_status (status ASC),
	INDEX index_support_tickets_on_user_id_and_status (user_id ASC, status ASC),
	INDEX index_support_tickets_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.swap_counters (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	swap_request_id UUID NOT NULL,
	version INT8 NOT NULL,
	author_role VARCHAR NOT NULL,
	counter_type VARCHAR NOT NULL,
	diff_hint VARCHAR NULL,
	requester_item_ids JSONB NOT NULL DEFAULT '[]':::JSONB,
	owner_item_ids JSONB NOT NULL DEFAULT '[]':::JSONB,
	amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	coins DECIMAL(12,4) NULL DEFAULT 0.0000:::DECIMAL,
	message VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	created_by_id INT8 NOT NULL,
	CONSTRAINT swap_counters_pkey PRIMARY KEY (id ASC),
	INDEX index_swap_counters_on_created_by_id (created_by_id ASC),
	INVERTED INDEX idx_swap_counters_owner_item_ids (owner_item_ids),
	INVERTED INDEX idx_swap_counters_requester_item_ids (requester_item_ids),
	INDEX index_swap_counters_on_swap_request_id_and_created_at (swap_request_id ASC, created_at ASC),
	UNIQUE INDEX index_swap_counters_on_swap_request_id_and_version (swap_request_id ASC, version ASC),
	CONSTRAINT chk_owner_items_size CHECK ((jsonb_typeof(owner_item_ids) = 'array':::STRING) AND (jsonb_array_length(owner_item_ids) <= 10:::INT8)),
	CONSTRAINT chk_requester_items_size CHECK ((jsonb_typeof(requester_item_ids) = 'array':::STRING) AND (jsonb_array_length(requester_item_ids) <= 10:::INT8))
) WITH (schema_locked = true);"
"CREATE TABLE public.swap_disputes (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	swap_request_id UUID NOT NULL,
	raised_by_id INT8 NOT NULL,
	raised_by_role VARCHAR NOT NULL,
	issue_type VARCHAR NOT NULL,
	status VARCHAR NOT NULL DEFAULT 'open':::STRING,
	description STRING NOT NULL,
	photo_urls JSONB NULL DEFAULT '[]':::JSONB,
	resolution VARCHAR NULL,
	admin_notes STRING NULL,
	resolved_by_id INT8 NULL,
	assigned_to_id INT8 NULL,
	opened_at TIMESTAMP(6) NULL,
	resolved_at TIMESTAMP(6) NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT swap_disputes_pkey PRIMARY KEY (id ASC),
	INDEX index_swap_disputes_on_raised_by_id (raised_by_id ASC),
	INDEX index_swap_disputes_on_status_and_created_at (status ASC, created_at ASC),
	INDEX index_swap_disputes_on_status (status ASC),
	INDEX index_swap_disputes_on_swap_request_id (swap_request_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.swap_requests (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	requester_listing_id UUID NULL,
	swap_type VARCHAR NOT NULL,
	status VARCHAR NOT NULL DEFAULT 'pending':::STRING,
	currency_code VARCHAR NOT NULL DEFAULT 'INR':::STRING,
	note VARCHAR NULL,
	initial_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	initial_coins DECIMAL(12,4) NULL DEFAULT 0.0000:::DECIMAL,
	current_offer_version INT8 NOT NULL DEFAULT 1:::INT8,
	current_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	current_coins DECIMAL(12,4) NULL DEFAULT 0.0000:::DECIMAL,
	accepted_version INT8 NULL,
	accepted_amount DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	accepted_coins DECIMAL(12,4) NULL DEFAULT 0.0000:::DECIMAL,
	accepted_items JSONB NOT NULL DEFAULT '{}':::JSONB,
	last_action_by VARCHAR NULL,
	last_action_at TIMESTAMP NULL,
	accepted_at TIMESTAMP NULL,
	rejected_at TIMESTAMP NULL,
	cancelled_at TIMESTAMP NULL,
	state_reason VARCHAR NULL,
	owner_listing_snapshot JSONB NOT NULL DEFAULT '{}':::JSONB,
	requester_listing_snapshot JSONB NOT NULL DEFAULT '{}':::JSONB,
	negotiation_cap INT8 NOT NULL DEFAULT 25:::INT8,
	unread_for_owner BOOL NOT NULL DEFAULT false,
	unread_for_requester BOOL NOT NULL DEFAULT false,
	chat_thread_id UUID NULL,
	lock_version INT8 NOT NULL DEFAULT 0:::INT8,
	expires_at TIMESTAMP NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	owner_listing_id UUID NOT NULL,
	initial_items JSONB NOT NULL DEFAULT '{}':::JSONB,
	current_items JSONB NOT NULL DEFAULT '{}':::JSONB,
	metadata JSONB NOT NULL DEFAULT '{}':::JSONB,
	accepted_by_id UUID NULL,
	accepted_by_role VARCHAR NULL,
	counters_count INT8 NOT NULL DEFAULT 0:::INT8,
	owner_id INT8 NOT NULL,
	requester_id INT8 NOT NULL,
	owner_receipt_confirmed BOOL NULL DEFAULT false,
	requester_receipt_confirmed BOOL NULL DEFAULT false,
	owner_receipt_confirmed_at TIMESTAMP(6) NULL,
	requester_receipt_confirmed_at TIMESTAMP(6) NULL,
	delivered_at TIMESTAMP(6) NULL,
	has_dispute BOOL NULL DEFAULT false,
	CONSTRAINT swap_requests_pkey PRIMARY KEY (id ASC),
	INVERTED INDEX idx_swap_requests_accepted_items (accepted_items),
	INVERTED INDEX idx_swap_requests_current_items_inverted (current_items),
	INVERTED INDEX idx_swap_requests_initial_items_inverted (initial_items),
	INDEX index_swap_requests_on_owner_id_and_status_and_created_at (owner_id ASC, status ASC, created_at DESC),
	INDEX idx_owner_status_updated (owner_id ASC, status ASC, updated_at DESC, currency_code ASC, current_amount ASC, current_coins ASC, counters_count ASC, owner_listing_id ASC, requester_listing_id ASC, swap_type ASC),
	UNIQUE INDEX ux_open_pair_once (owner_listing_id ASC, requester_listing_id ASC) WHERE status IN ('pending':::STRING, 'accepted':::STRING),
	INDEX index_swap_requests_on_owner_listing_id (owner_listing_id ASC),
	UNIQUE INDEX ux_one_accepted_per_owner_listing (owner_listing_id ASC) WHERE status = 'accepted':::STRING,
	INDEX index_swap_requests_on_requester_id_and_status_and_created_at (requester_id ASC, status ASC, created_at DESC),
	INDEX idx_requester_status_updated (requester_id ASC, status ASC, updated_at DESC, currency_code ASC, current_amount ASC, current_coins ASC, counters_count ASC, owner_listing_id ASC, requester_listing_id ASC, swap_type ASC),
	INDEX index_swap_requests_on_status_and_last_action_at (status ASC, last_action_at DESC),
	CONSTRAINT chk_amount_nonneg CHECK (((initial_amount >= 0:::DECIMAL) AND (current_amount >= 0:::DECIMAL)) AND (accepted_amount >= 0:::DECIMAL)),
	CONSTRAINT chk_coins_nonneg CHECK (((initial_coins >= 0:::DECIMAL) AND (current_coins >= 0:::DECIMAL)) AND (accepted_coins >= 0:::DECIMAL))
) WITH (schema_locked = true);"
"CREATE TABLE public.swap_timeline_events (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	swap_request_id UUID NOT NULL,
	event_type VARCHAR NOT NULL,
	channel VARCHAR NOT NULL DEFAULT 'system':::STRING,
	actor_id UUID NULL,
	version INT8 NULL,
	metadata JSONB NOT NULL DEFAULT '{}':::JSONB,
	read_by_owner BOOL NOT NULL DEFAULT false,
	read_by_requester BOOL NOT NULL DEFAULT false,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT swap_timeline_events_pkey PRIMARY KEY (id ASC),
	INDEX index_swap_timeline_events_on_swap_request_id_and_created_at (swap_request_id ASC, created_at ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.ticket_replies (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	support_ticket_id UUID NOT NULL,
	user_id INT8 NULL,
	admin_name VARCHAR NULL,
	message STRING NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT ticket_replies_pkey PRIMARY KEY (id ASC),
	INDEX index_ticket_replies_on_support_ticket_id (support_ticket_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.user_devices (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	user_id INT8 NOT NULL,
	device_type VARCHAR NULL,
	device_token VARCHAR NULL,
	os_type VARCHAR NULL,
	os_version VARCHAR NULL,
	app_version VARCHAR NULL,
	last_active_at TIMESTAMP(6) NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT user_devices_pkey PRIMARY KEY (id ASC),
	INDEX index_user_devices_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.user_login_logs (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	ip_address VARCHAR NULL,
	device_type VARCHAR NULL,
	browser_info VARCHAR NULL,
	login_at TIMESTAMP(6) NULL,
	status VARCHAR NULL DEFAULT 'failed':::STRING,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT user_login_logs_pkey PRIMARY KEY (id ASC),
	INDEX index_user_login_logs_on_user_id (user_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.vendor_rate_cards (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	vendor_code VARCHAR NOT NULL,
	city_code VARCHAR NOT NULL,
	vehicle_type VARCHAR NOT NULL,
	time_band VARCHAR NULL,
	base_fare_paise INT8 NOT NULL,
	per_km_rate_paise INT8 NOT NULL,
	per_min_rate_paise INT8 NULL DEFAULT 0:::INT8,
	dead_km_rate_paise INT8 NULL DEFAULT 0:::INT8,
	free_km_m INT8 NULL DEFAULT 1000:::INT8,
	surge_cap_multiplier DECIMAL(4,2) NULL DEFAULT 2.00:::DECIMAL,
	min_fare_paise INT8 NOT NULL,
	effective_from TIMESTAMP(6) NOT NULL,
	effective_until TIMESTAMP(6) NULL,
	active BOOL NULL DEFAULT true,
	version INT8 NULL DEFAULT 1:::INT8,
	notes STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT vendor_rate_cards_pkey PRIMARY KEY (id ASC),
	INDEX idx_vendor_rate_cards_lookup (vendor_code ASC, city_code ASC, active ASC),
	UNIQUE INDEX idx_vendor_rate_cards_unique (vendor_code ASC, city_code ASC, vehicle_type ASC, time_band ASC, version ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.wallet_transactions (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	wallet_id UUID NOT NULL,
	amount DECIMAL(12,2) NOT NULL,
	transaction_type VARCHAR NOT NULL,
	reference_type VARCHAR NULL,
	reference_id VARCHAR NULL,
	status VARCHAR NOT NULL DEFAULT 'pending':::STRING,
	description STRING NULL,
	metadata JSONB NULL DEFAULT '{}':::JSONB,
	balance_before DECIMAL(12,2) NULL,
	balance_after DECIMAL(12,2) NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id ASC),
	INDEX index_wallet_transactions_on_reference_type_and_reference_id (reference_type ASC, reference_id ASC),
	INDEX index_wallet_transactions_on_status_and_created_at (status ASC, created_at ASC),
	INDEX index_wallet_transactions_on_transaction_type_and_status (transaction_type ASC, status ASC),
	INDEX index_wallet_transactions_on_wallet_id_and_created_at (wallet_id ASC, created_at DESC)
) WITH (schema_locked = true);"
"CREATE TABLE public.wallet_ledger_entries (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	wallet_id UUID NOT NULL,
	wallet_transaction_id UUID NOT NULL,
	debit DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	credit DECIMAL(12,2) NULL DEFAULT 0.00:::DECIMAL,
	balance_after DECIMAL(12,2) NOT NULL,
	description STRING NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT wallet_ledger_entries_pkey PRIMARY KEY (id ASC),
	INDEX index_wallet_ledger_entries_on_wallet_id_and_created_at (wallet_id ASC, created_at DESC),
	INDEX index_wallet_ledger_entries_on_wallet_transaction_id (wallet_transaction_id ASC),
	CONSTRAINT ledger_amounts_non_negative CHECK ((debit >= 0:::DECIMAL) AND (credit >= 0:::DECIMAL)),
	CONSTRAINT ledger_debit_or_credit_only CHECK (NOT ((debit > 0:::DECIMAL) AND (credit > 0:::DECIMAL)))
) WITH (schema_locked = true);"
"CREATE TABLE public.wishlists (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	user_id INT8 NOT NULL,
	listing_id UUID NOT NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT wishlists_pkey PRIMARY KEY (id ASC),
	INDEX idx_wishlists_listing (listing_id ASC),
	INDEX idx_wishlists_user_created (user_id ASC, created_at DESC),
	UNIQUE INDEX idx_wishlists_user_listing_unique (user_id ASC, listing_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_announcements (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	announcement_type VARCHAR NULL,
	status VARCHAR NULL DEFAULT 'active':::STRING,
	valid_from TIMESTAMP(6) NULL,
	valid_until TIMESTAMP(6) NULL,
	message STRING NULL,
	user_targeting JSONB NULL DEFAULT '{}':::JSONB,
	zone_ids UUID[] NULL DEFAULT ARRAY[]:::UUID[],
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT zone_announcements_pkey PRIMARY KEY (id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_listing_rules (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	zone_id INT8 NOT NULL,
	max_items_per_user INT8 NULL,
	swap_enabled BOOL NULL,
	monetary_swap_enabled BOOL NULL,
	premium_listing_enabled BOOL NULL,
	approval_required BOOL NULL,
	status VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT zone_listing_rules_pkey PRIMARY KEY (id ASC),
	INDEX index_zone_listing_rules_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_category_restrictions (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	zone_listing_rule_id INT8 NOT NULL,
	category VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT zone_category_restrictions_pkey PRIMARY KEY (id ASC),
	INDEX index_zone_category_restrictions_on_zone_listing_rule_id (zone_listing_rule_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_distance_slabs (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	city_code VARCHAR NOT NULL,
	zone_id INT8 NOT NULL,
	vehicle_type VARCHAR NOT NULL,
	min_distance_m INT8 NOT NULL DEFAULT 0:::INT8,
	max_distance_m INT8 NULL,
	per_km_rate_paise INT8 NOT NULL,
	flat_fare_paise INT8 NULL,
	priority INT8 NULL DEFAULT 10:::INT8,
	active BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT zone_distance_slabs_pkey PRIMARY KEY (id ASC),
	INDEX index_zone_distance_slabs_on_city_code_and_active (city_code ASC, active ASC),
	UNIQUE INDEX idx_zone_slabs_unique (city_code ASC, zone_id ASC, vehicle_type ASC, min_distance_m ASC),
	INDEX idx_on_zone_id_vehicle_type_active_a11cdf01f8 (zone_id ASC, vehicle_type ASC, active ASC),
	INDEX index_zone_distance_slabs_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_h3_mappings (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	h3_index_r7 VARCHAR NOT NULL,
	h3_index_r9 VARCHAR NULL,
	zone_id INT8 NOT NULL,
	city_code VARCHAR NOT NULL,
	is_boundary BOOL NULL DEFAULT false,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	serviceable BOOL NULL DEFAULT true,
	h3_index_r8 VARCHAR NULL,
	CONSTRAINT zone_h3_mappings_pkey PRIMARY KEY (id ASC),
	INDEX idx_zone_h3_mappings_r8_city (city_code ASC, h3_index_r8 ASC),
	INDEX idx_zone_h3_mappings_r7_city (h3_index_r7 ASC, city_code ASC),
	UNIQUE INDEX idx_zone_h3_mappings_r7_zone (h3_index_r7 ASC, zone_id ASC),
	INDEX idx_zone_h3_mappings_r9_city (h3_index_r9 ASC, city_code ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_pair_vehicle_pricings (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	city_code VARCHAR NOT NULL,
	from_zone_id INT8 NOT NULL,
	to_zone_id INT8 NOT NULL,
	vehicle_type VARCHAR NOT NULL,
	base_fare_paise INT8 NULL,
	min_fare_paise INT8 NULL,
	per_km_rate_paise INT8 NULL,
	corridor_type VARCHAR NULL,
	directional BOOL NULL DEFAULT true,
	active BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	time_band VARCHAR NULL,
	per_min_rate_paise INT8 NULL DEFAULT 0:::INT8,
	auto_generated BOOL NULL DEFAULT false,
	CONSTRAINT zone_pair_vehicle_pricings_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX idx_zpvp_routing_with_time_band (city_code ASC, from_zone_id ASC, to_zone_id ASC, vehicle_type ASC, time_band ASC),
	INDEX index_zone_pair_vehicle_pricings_on_from_zone_id (from_zone_id ASC),
	INDEX index_zone_pair_vehicle_pricings_on_to_zone_id (to_zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_policies (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	zone_id INT8 NOT NULL,
	feature VARCHAR NULL,
	enabled BOOL NULL,
	start_date TIMESTAMP(6) NULL,
	end_date TIMESTAMP(6) NULL,
	updated_by UUID NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT zone_policies_pkey PRIMARY KEY (id ASC),
	INDEX index_zone_policies_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_vehicle_pricings (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	zone_id INT8 NOT NULL,
	city_code VARCHAR NOT NULL,
	vehicle_type VARCHAR NOT NULL,
	base_fare_paise INT8 NOT NULL,
	min_fare_paise INT8 NOT NULL,
	base_distance_m INT8 NOT NULL,
	per_km_rate_paise INT8 NOT NULL,
	active BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	per_min_rate_paise INT8 NULL DEFAULT 0:::INT8,
	CONSTRAINT zone_vehicle_pricings_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX idx_zvp_lookup (city_code ASC, zone_id ASC, vehicle_type ASC),
	INDEX index_zone_vehicle_pricings_on_zone_id (zone_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.zone_vehicle_time_pricings (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	zone_vehicle_pricing_id UUID NOT NULL,
	time_band VARCHAR NOT NULL,
	base_fare_paise INT8 NOT NULL,
	min_fare_paise INT8 NOT NULL,
	per_km_rate_paise INT8 NOT NULL,
	active BOOL NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	per_min_rate_paise INT8 NULL DEFAULT 0:::INT8,
	CONSTRAINT zone_vehicle_time_pricings_pkey PRIMARY KEY (id ASC),
	UNIQUE INDEX idx_zvtp_pricing_time (zone_vehicle_pricing_id ASC, time_band ASC),
	INDEX index_zone_vehicle_time_pricings_on_zone_vehicle_pricing_id (zone_vehicle_pricing_id ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.schema_migrations (
	version VARCHAR NOT NULL,
	CONSTRAINT schema_migrations_pkey PRIMARY KEY (version ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.ar_internal_metadata (
	key VARCHAR NOT NULL,
	value VARCHAR NULL,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.inter_zone_configs (
	id INT8 NOT NULL DEFAULT unique_rowid(),
	city_code VARCHAR NOT NULL,
	origin_weight FLOAT8 NOT NULL DEFAULT 0.6:::FLOAT8,
	destination_weight FLOAT8 NOT NULL DEFAULT 0.4:::FLOAT8,
	type_adjustments JSONB NULL DEFAULT '{}':::JSONB,
	active BOOL NOT NULL DEFAULT true,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT inter_zone_configs_pkey PRIMARY KEY (id ASC),
	INDEX index_inter_zone_configs_on_city_code_and_active (city_code ASC, active ASC)
) WITH (schema_locked = true);"
"CREATE TABLE public.backhaul_probabilities (
	id UUID NOT NULL DEFAULT gen_random_uuid(),
	zone_id INT8 NOT NULL,
	time_band VARCHAR NOT NULL,
	return_probability FLOAT8 NOT NULL DEFAULT 0.5:::FLOAT8,
	avg_return_distance_m INT8 NULL DEFAULT 0:::INT8,
	sample_size INT8 NULL DEFAULT 0:::INT8,
	created_at TIMESTAMP(6) NOT NULL,
	updated_at TIMESTAMP(6) NOT NULL,
	CONSTRAINT backhaul_probabilities_pkey PRIMARY KEY (id ASC),
	INDEX index_backhaul_probabilities_on_zone_id (zone_id ASC),
	UNIQUE INDEX index_backhaul_probabilities_on_zone_id_and_time_band (zone_id ASC, time_band ASC)
) WITH (schema_locked = true);"
ALTER TABLE public.active_storage_attachments ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);
ALTER TABLE public.active_storage_variant_records ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);
ALTER TABLE public.users ADD CONSTRAINT fk_rails_9e4eab2a89 FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.locations ADD CONSTRAINT fk_rails_5e107925c6 FOREIGN KEY (user_id) REFERENCES public.users(id) NOT VALID;
ALTER TABLE public.address_contacts ADD CONSTRAINT fk_rails_fa3ecc9e02 FOREIGN KEY (location_id) REFERENCES public.locations(id);
ALTER TABLE public.admin_coin_overrides ADD CONSTRAINT fk_rails_df670a418e FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.admins ADD CONSTRAINT fk_rails_ce57ed3a3a FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.blocked_users ADD CONSTRAINT fk_rails_b231984b0e FOREIGN KEY (blocked_id) REFERENCES public.users(id);
ALTER TABLE public.blocked_users ADD CONSTRAINT fk_rails_9840362eae FOREIGN KEY (blocker_id) REFERENCES public.users(id);
ALTER TABLE public.coin_earning_rules ADD CONSTRAINT fk_rails_4066822627 FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.coin_expiry_settings ADD CONSTRAINT fk_rails_968038886c FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.delivery_addresses ADD CONSTRAINT fk_rails_42675d2d6f FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.delivery_orders ADD CONSTRAINT fk_rails_c5cc25ad28 FOREIGN KEY (drop_address_id) REFERENCES public.delivery_addresses(id) ON DELETE RESTRICT;
ALTER TABLE public.delivery_orders ADD CONSTRAINT fk_rails_2441587460 FOREIGN KEY (pickup_address_id) REFERENCES public.delivery_addresses(id) ON DELETE RESTRICT;
ALTER TABLE public.delivery_orders ADD CONSTRAINT fk_rails_d15df9538e FOREIGN KEY (delivery_partner_id) REFERENCES public.delivery_partners(id);
ALTER TABLE public.delivery_orders ADD CONSTRAINT fk_rails_7cc08184e8 FOREIGN KEY (receiver_id) REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.delivery_orders ADD CONSTRAINT fk_rails_b85c0e9e07 FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.delivery_partner_callbacks ADD CONSTRAINT fk_rails_a7b92220bb FOREIGN KEY (delivery_order_id) REFERENCES public.delivery_orders(id) ON DELETE CASCADE;
ALTER TABLE public.wallets ADD CONSTRAINT fk_rails_732f6628c4 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.escrow_holds ADD CONSTRAINT fk_rails_a4b41346fb FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.escrow_holds ADD CONSTRAINT fk_rails_f1d6cb7678 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE RESTRICT;
ALTER TABLE public.zone_locations ADD CONSTRAINT fk_rails_f2b81dc62b FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.listings ADD CONSTRAINT fk_rails_baa008bfd2 FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.listings ADD CONSTRAINT fk_rails_2cf8d82d26 FOREIGN KEY (zone_location_id) REFERENCES public.zone_locations(id);
ALTER TABLE public.listing_items ADD CONSTRAINT fk_rails_57b51b4d5c FOREIGN KEY (category_id) REFERENCES public.categories(id);
ALTER TABLE public.listing_items ADD CONSTRAINT fk_rails_6adb1514a4 FOREIGN KEY (listing_id) REFERENCES public.listings(id) ON DELETE CASCADE;
ALTER TABLE public.image_hashes ADD CONSTRAINT fk_rails_892c32a0c3 FOREIGN KEY (listing_item_id) REFERENCES public.listing_items(id) ON DELETE CASCADE;
ALTER TABLE public.image_hashes ADD CONSTRAINT fk_rails_1d92d16d9f FOREIGN KEY (listing_id) REFERENCES public.listings(id) ON DELETE CASCADE;
ALTER TABLE public.payment_intents ADD CONSTRAINT fk_rails_a3612857f8 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.invoices ADD CONSTRAINT fk_rails_858019996b FOREIGN KEY (payment_intent_id) REFERENCES public.payment_intents(id) ON DELETE SET NULL;
ALTER TABLE public.invoices ADD CONSTRAINT fk_rails_3d1522a0d8 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.listing_approval_settings ADD CONSTRAINT fk_rails_8ee432c166 FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.listing_validations ADD CONSTRAINT fk_rails_227ea3dca3 FOREIGN KEY (listing_id) REFERENCES public.listings(id) ON DELETE CASCADE;
ALTER TABLE public.notifications ADD CONSTRAINT fk_rails_b080fb4855 FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.otp_codes ADD CONSTRAINT fk_rails_43b86b8e4d FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.payment_methods ADD CONSTRAINT fk_rails_e13d4c515f FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.payment_charges ADD CONSTRAINT fk_rails_78de95edb6 FOREIGN KEY (intent_id) REFERENCES public.payment_intents(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_charges ADD CONSTRAINT fk_rails_a268f93f13 FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(id) ON DELETE SET NULL;
ALTER TABLE public.payment_refunds ADD CONSTRAINT fk_rails_91bbf5edd7 FOREIGN KEY (charge_id) REFERENCES public.payment_charges(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_refunds ADD CONSTRAINT fk_rails_9145e83a67 FOREIGN KEY (initiated_by_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.payment_webhook_events ADD CONSTRAINT fk_rails_c367713988 FOREIGN KEY (intent_id) REFERENCES public.payment_intents(id) ON DELETE SET NULL;
ALTER TABLE public.payout_accounts ADD CONSTRAINT fk_rails_eb67bdc716 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
ALTER TABLE public.payouts ADD CONSTRAINT fk_rails_2d0f5075a1 FOREIGN KEY (account_id) REFERENCES public.payout_accounts(id) ON DELETE RESTRICT;
ALTER TABLE public.payouts ADD CONSTRAINT fk_rails_f3cf384b33 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.payouts ADD CONSTRAINT fk_rails_b618081134 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE RESTRICT;
ALTER TABLE public.zone_delivery_configs ADD CONSTRAINT fk_rails_f8f61e0559 FOREIGN KEY (delivery_partner_id) REFERENCES public.delivery_partners(id);
ALTER TABLE public.zone_delivery_configs ADD CONSTRAINT fk_rails_a3ee0913ea FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.pickup_slots ADD CONSTRAINT fk_rails_337306b6c3 FOREIGN KEY (delivery_partner_id) REFERENCES public.delivery_partners(id);
ALTER TABLE public.pickup_slots ADD CONSTRAINT fk_rails_b279cdc95e FOREIGN KEY (zone_delivery_config_id) REFERENCES public.zone_delivery_configs(id);
ALTER TABLE public.preferred_exchange_categories ADD CONSTRAINT fk_rails_fe88b3740c FOREIGN KEY (category_id) REFERENCES public.categories(id);
ALTER TABLE public.preferred_exchange_categories ADD CONSTRAINT fk_rails_2a716f8dd0 FOREIGN KEY (listing_id) REFERENCES public.listings(id) ON DELETE CASCADE;
ALTER TABLE public.pricing_actuals ADD CONSTRAINT fk_rails_6cc4c99dfa FOREIGN KEY (pricing_quote_id) REFERENCES public.pricing_quotes(id);
ALTER TABLE public.pricing_distance_slabs ADD CONSTRAINT fk_rails_53e4771ca5 FOREIGN KEY (pricing_config_id) REFERENCES public.pricing_configs(id);
ALTER TABLE public.pricing_quote_decisions ADD CONSTRAINT fk_rails_7b4a227f19 FOREIGN KEY (pricing_config_id) REFERENCES public.pricing_configs(id);
ALTER TABLE public.pricing_quote_decisions ADD CONSTRAINT fk_rails_586e08f8d3 FOREIGN KEY (pricing_quote_id) REFERENCES public.pricing_quotes(id);
ALTER TABLE public.pricing_quote_replays ADD CONSTRAINT fk_rails_42c5e1e93a FOREIGN KEY (pricing_config_id) REFERENCES public.pricing_configs(id);
ALTER TABLE public.pricing_quote_replays ADD CONSTRAINT fk_rails_bf2c4ef7f5 FOREIGN KEY (pricing_quote_decision_id) REFERENCES public.pricing_quote_decisions(id);
ALTER TABLE public.pricing_quote_replays ADD CONSTRAINT fk_rails_cd20d597a7 FOREIGN KEY (replayed_by_id) REFERENCES public.users(id);
ALTER TABLE public.pricing_surge_rules ADD CONSTRAINT fk_rails_f3ea02dbb6 FOREIGN KEY (pricing_config_id) REFERENCES public.pricing_configs(id);
ALTER TABLE public.profile_settings ADD CONSTRAINT fk_rails_633b047444 FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.referral_rewards ADD CONSTRAINT fk_rails_81acacb007 FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.referral_rewards ADD CONSTRAINT fk_rails_49a1029bd8 FOREIGN KEY (referred_user_id) REFERENCES public.users(id);
ALTER TABLE public.referral_rules ADD CONSTRAINT fk_rails_a1057699ad FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.user_devices ADD CONSTRAINT fk_rails_e700a96826 FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.user_login_logs ADD CONSTRAINT fk_rails_6146581a82 FOREIGN KEY (user_id) REFERENCES public.users(id);
ALTER TABLE public.wallet_transactions ADD CONSTRAINT fk_rails_d07bc24ce3 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE RESTRICT;
ALTER TABLE public.wallet_ledger_entries ADD CONSTRAINT fk_rails_102f5c88f2 FOREIGN KEY (wallet_transaction_id) REFERENCES public.wallet_transactions(id) ON DELETE RESTRICT;
ALTER TABLE public.wallet_ledger_entries ADD CONSTRAINT fk_rails_9825699323 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE RESTRICT;
ALTER TABLE public.zone_listing_rules ADD CONSTRAINT fk_rails_646e0dade3 FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.zone_category_restrictions ADD CONSTRAINT fk_rails_60bd33c398 FOREIGN KEY (zone_listing_rule_id) REFERENCES public.zone_listing_rules(id);
ALTER TABLE public.zone_distance_slabs ADD CONSTRAINT fk_rails_83918bfa5b FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.zone_h3_mappings ADD CONSTRAINT fk_rails_d5133dff51 FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.zone_pair_vehicle_pricings ADD CONSTRAINT fk_rails_1c66894da4 FOREIGN KEY (from_zone_id) REFERENCES public.zones(id);
ALTER TABLE public.zone_pair_vehicle_pricings ADD CONSTRAINT fk_rails_9eaecc9ba0 FOREIGN KEY (to_zone_id) REFERENCES public.zones(id);
ALTER TABLE public.zone_policies ADD CONSTRAINT fk_rails_787f489652 FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.zone_vehicle_pricings ADD CONSTRAINT fk_rails_fe8b307e39 FOREIGN KEY (zone_id) REFERENCES public.zones(id);
ALTER TABLE public.zone_vehicle_time_pricings ADD CONSTRAINT fk_rails_8ee30a673e FOREIGN KEY (zone_vehicle_pricing_id) REFERENCES public.zone_vehicle_pricings(id);
ALTER TABLE public.backhaul_probabilities ADD CONSTRAINT fk_rails_e0f6102350 FOREIGN KEY (zone_id) REFERENCES public.zones(id);
-- Validate foreign key constraints. These can fail if there was unvalidated data during the SHOW CREATE ALL TABLES
ALTER TABLE public.active_storage_attachments VALIDATE CONSTRAINT fk_rails_c3b3935057;
ALTER TABLE public.active_storage_variant_records VALIDATE CONSTRAINT fk_rails_993965df05;
ALTER TABLE public.users VALIDATE CONSTRAINT fk_rails_9e4eab2a89;
ALTER TABLE public.locations VALIDATE CONSTRAINT fk_rails_5e107925c6;
ALTER TABLE public.address_contacts VALIDATE CONSTRAINT fk_rails_fa3ecc9e02;
ALTER TABLE public.admin_coin_overrides VALIDATE CONSTRAINT fk_rails_df670a418e;
ALTER TABLE public.admins VALIDATE CONSTRAINT fk_rails_ce57ed3a3a;
ALTER TABLE public.blocked_users VALIDATE CONSTRAINT fk_rails_b231984b0e;
ALTER TABLE public.blocked_users VALIDATE CONSTRAINT fk_rails_9840362eae;
ALTER TABLE public.coin_earning_rules VALIDATE CONSTRAINT fk_rails_4066822627;
ALTER TABLE public.coin_expiry_settings VALIDATE CONSTRAINT fk_rails_968038886c;
ALTER TABLE public.delivery_addresses VALIDATE CONSTRAINT fk_rails_42675d2d6f;
ALTER TABLE public.delivery_orders VALIDATE CONSTRAINT fk_rails_c5cc25ad28;
ALTER TABLE public.delivery_orders VALIDATE CONSTRAINT fk_rails_2441587460;
ALTER TABLE public.delivery_orders VALIDATE CONSTRAINT fk_rails_d15df9538e;
ALTER TABLE public.delivery_orders VALIDATE CONSTRAINT fk_rails_7cc08184e8;
ALTER TABLE public.delivery_orders VALIDATE CONSTRAINT fk_rails_b85c0e9e07;
ALTER TABLE public.delivery_partner_callbacks VALIDATE CONSTRAINT fk_rails_a7b92220bb;
ALTER TABLE public.wallets VALIDATE CONSTRAINT fk_rails_732f6628c4;
ALTER TABLE public.escrow_holds VALIDATE CONSTRAINT fk_rails_a4b41346fb;
ALTER TABLE public.escrow_holds VALIDATE CONSTRAINT fk_rails_f1d6cb7678;
ALTER TABLE public.zone_locations VALIDATE CONSTRAINT fk_rails_f2b81dc62b;
ALTER TABLE public.listings VALIDATE CONSTRAINT fk_rails_baa008bfd2;
ALTER TABLE public.listings VALIDATE CONSTRAINT fk_rails_2cf8d82d26;
ALTER TABLE public.listing_items VALIDATE CONSTRAINT fk_rails_57b51b4d5c;
ALTER TABLE public.listing_items VALIDATE CONSTRAINT fk_rails_6adb1514a4;
ALTER TABLE public.image_hashes VALIDATE CONSTRAINT fk_rails_892c32a0c3;
ALTER TABLE public.image_hashes VALIDATE CONSTRAINT fk_rails_1d92d16d9f;
ALTER TABLE public.payment_intents VALIDATE CONSTRAINT fk_rails_a3612857f8;
ALTER TABLE public.invoices VALIDATE CONSTRAINT fk_rails_858019996b;
ALTER TABLE public.invoices VALIDATE CONSTRAINT fk_rails_3d1522a0d8;
ALTER TABLE public.listing_approval_settings VALIDATE CONSTRAINT fk_rails_8ee432c166;
ALTER TABLE public.listing_validations VALIDATE CONSTRAINT fk_rails_227ea3dca3;
ALTER TABLE public.notifications VALIDATE CONSTRAINT fk_rails_b080fb4855;
ALTER TABLE public.otp_codes VALIDATE CONSTRAINT fk_rails_43b86b8e4d;
ALTER TABLE public.payment_methods VALIDATE CONSTRAINT fk_rails_e13d4c515f;
ALTER TABLE public.payment_charges VALIDATE CONSTRAINT fk_rails_78de95edb6;
ALTER TABLE public.payment_charges VALIDATE CONSTRAINT fk_rails_a268f93f13;
ALTER TABLE public.payment_refunds VALIDATE CONSTRAINT fk_rails_91bbf5edd7;
ALTER TABLE public.payment_refunds VALIDATE CONSTRAINT fk_rails_9145e83a67;
ALTER TABLE public.payment_webhook_events VALIDATE CONSTRAINT fk_rails_c367713988;
ALTER TABLE public.payout_accounts VALIDATE CONSTRAINT fk_rails_eb67bdc716;
ALTER TABLE public.payouts VALIDATE CONSTRAINT fk_rails_2d0f5075a1;
ALTER TABLE public.payouts VALIDATE CONSTRAINT fk_rails_f3cf384b33;
ALTER TABLE public.payouts VALIDATE CONSTRAINT fk_rails_b618081134;
ALTER TABLE public.zone_delivery_configs VALIDATE CONSTRAINT fk_rails_f8f61e0559;
ALTER TABLE public.zone_delivery_configs VALIDATE CONSTRAINT fk_rails_a3ee0913ea;
ALTER TABLE public.pickup_slots VALIDATE CONSTRAINT fk_rails_337306b6c3;
ALTER TABLE public.pickup_slots VALIDATE CONSTRAINT fk_rails_b279cdc95e;
ALTER TABLE public.preferred_exchange_categories VALIDATE CONSTRAINT fk_rails_fe88b3740c;
ALTER TABLE public.preferred_exchange_categories VALIDATE CONSTRAINT fk_rails_2a716f8dd0;
ALTER TABLE public.pricing_actuals VALIDATE CONSTRAINT fk_rails_6cc4c99dfa;
ALTER TABLE public.pricing_distance_slabs VALIDATE CONSTRAINT fk_rails_53e4771ca5;
ALTER TABLE public.pricing_quote_decisions VALIDATE CONSTRAINT fk_rails_7b4a227f19;
ALTER TABLE public.pricing_quote_decisions VALIDATE CONSTRAINT fk_rails_586e08f8d3;
ALTER TABLE public.pricing_quote_replays VALIDATE CONSTRAINT fk_rails_42c5e1e93a;
ALTER TABLE public.pricing_quote_replays VALIDATE CONSTRAINT fk_rails_bf2c4ef7f5;
ALTER TABLE public.pricing_quote_replays VALIDATE CONSTRAINT fk_rails_cd20d597a7;
ALTER TABLE public.pricing_surge_rules VALIDATE CONSTRAINT fk_rails_f3ea02dbb6;
ALTER TABLE public.profile_settings VALIDATE CONSTRAINT fk_rails_633b047444;
ALTER TABLE public.referral_rewards VALIDATE CONSTRAINT fk_rails_81acacb007;
ALTER TABLE public.referral_rewards VALIDATE CONSTRAINT fk_rails_49a1029bd8;
ALTER TABLE public.referral_rules VALIDATE CONSTRAINT fk_rails_a1057699ad;
ALTER TABLE public.user_devices VALIDATE CONSTRAINT fk_rails_e700a96826;
ALTER TABLE public.user_login_logs VALIDATE CONSTRAINT fk_rails_6146581a82;
ALTER TABLE public.wallet_transactions VALIDATE CONSTRAINT fk_rails_d07bc24ce3;
ALTER TABLE public.wallet_ledger_entries VALIDATE CONSTRAINT fk_rails_102f5c88f2;
ALTER TABLE public.wallet_ledger_entries VALIDATE CONSTRAINT fk_rails_9825699323;
ALTER TABLE public.zone_listing_rules VALIDATE CONSTRAINT fk_rails_646e0dade3;
ALTER TABLE public.zone_category_restrictions VALIDATE CONSTRAINT fk_rails_60bd33c398;
ALTER TABLE public.zone_distance_slabs VALIDATE CONSTRAINT fk_rails_83918bfa5b;
ALTER TABLE public.zone_h3_mappings VALIDATE CONSTRAINT fk_rails_d5133dff51;
ALTER TABLE public.zone_pair_vehicle_pricings VALIDATE CONSTRAINT fk_rails_1c66894da4;
ALTER TABLE public.zone_pair_vehicle_pricings VALIDATE CONSTRAINT fk_rails_9eaecc9ba0;
ALTER TABLE public.zone_policies VALIDATE CONSTRAINT fk_rails_787f489652;
ALTER TABLE public.zone_vehicle_pricings VALIDATE CONSTRAINT fk_rails_fe8b307e39;
ALTER TABLE public.zone_vehicle_time_pricings VALIDATE CONSTRAINT fk_rails_8ee30a673e;
ALTER TABLE public.backhaul_probabilities VALIDATE CONSTRAINT fk_rails_e0f6102350;
