-- -------------------------------------------------------------
-- Database: tachyon
-- Generation Time: 
-- -------------------------------------------------------------
CREATE TABLE "users" (
  "id" bigserial PRIMARY KEY,
  "username" varchar(20) UNIQUE NOT NULL,
  "first_name" varchar NOT NULL,
  "last_name" varchar NOT NULL,
  "email" varchar(25) UNIQUE NOT NULL,
  "password" varchar,
  "verified" boolean DEFAULT false,
  "created_at" timestamp
);

CREATE TABLE "user_settings" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "push_enabled" boolean,
  "quiet_hours" jsonb
);

CREATE TABLE "profiles" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "display_name" varchar UNIQUE NOT NULL,
  "avatar" text,
  "phone" text,
  "marketing_opt_in" boolean,
  "created_at" timestamp
);

CREATE TABLE "metrics" (
  "id" bigserial PRIMARY KEY,
  "profile_id" bigserial NOT NULL,
  "bot_count" integer,
  "win_loss_ratio" float
);

CREATE TABLE "wallets" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "currency" text,
  "buying_power" float,
  "updated_at" timestamp,
  "created_at" timestamp
);

CREATE TABLE "banking_connections" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "plaid_item_id" varchar NOT NULL,
  "plaid_access_token" varchar NOT NULL,
  "status" "enum(ACTIVE,INACTIVE)"
);

CREATE TABLE "bank_accounts" (
  "id" bigserial PRIMARY KEY,
  "banking_connection_id" bigserial NOT NULL,
  "plaid_account_id" varchar NOT NULL,
  "stripe_bank_account_token" varchar,
  "account_name" varchar,
  "type" "enum(CHECKING,SAVINGS)",
  "mask" varchar,
  "last_verified" timestamp
);

CREATE TABLE "transfers" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "wallet_id" bigserial NOT NULL,
  "direction" "enum(DEPOSIT,WITHDRAW)",
  "amount" numeric(18,2),
  "currency" text,
  "provider_ref" text,
  "status" "enum(INITIATED,PENDING,COMPLETED,FAILED,CANCELLED)",
  "failure_reason" text,
  "updated_at" timestamp,
  "created_at" timestamp
);

CREATE TABLE "ledger_accounts" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "name" text,
  "type" "enum(ASSET,LIABILITY,REVENUE,EXPENSE,FEE)"
);

CREATE TABLE "ledger_entries" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "reference_type" text,
  "reference_id" uuid,
  "memo" text,
  "created_at" timestamp
);

CREATE TABLE "ledger_lines" (
  "id" bigserial PRIMARY KEY,
  "ledger_entry_id" bigserial NOT NULL,
  "ledger_account_id" bigserial NOT NULL,
  "debit" numeric(18,2) DEFAULT 0,
  "credit" numeric(18,2) DEFAULT 0,
  "currency" text
);

CREATE TABLE "broker_connections" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "provider_name" "enum(ALPACA,TRADIER,IBKR,WEBULL)",
  "status" "enum(ACTIVE,REVOKED,ERROR)",
  "provider_account_id" text,
  "access_token" text,
  "refresh_token" text,
  "scopes" jsonb,
  "created_at" timestamp,
  "updated_at" timestamp
);

CREATE TABLE "broker_accounts" (
  "id" bigserial PRIMARY KEY,
  "broker_connection_id" bigserial NOT NULL,
  "account_type" text,
  "base_currency" text,
  "raw_payload" jsonb,
  "created_at" timestamp
);

CREATE TABLE "broker_events" (
  "id" bigserial PRIMARY KEY,
  "provider" bigserial NOT NULL,
  "provider_ref" text,
  "event_type" text,
  "payload" jsonb,
  "received_at" timestamp,
  "processed_at" timestamp
);

CREATE TABLE "bot_avatars" (
  "id" bigserial PRIMARY KEY,
  "img" varchar
);

CREATE TABLE "bots" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "avatar_id" bigserial NOT NULL,
  "name" text,
  "status" "enum(DRAFT,ACTIVE,PAUSED,ARCHIVED)",
  "allocation_pct" numeric(5,4),
  "created_at" timestamp,
  "updated_at" timestamp
);

CREATE TABLE "bot_settings" (
  "id" bigserial PRIMARY KEY,
  "bot_id" bigserial NOT NULL,
  "version" int,
  "risk_attitude" "enum(CAUTIOUS,BALANCED,AGGRESSIVE)",
  "trade_tempo" "enum(OPPORTUNISTIC,ACTIVE,RELENTLESS)",
  "combat_patience" "enum(IMPULSIVE,CALCULATED,PATIENT,STRATEGIC)",
  "daily_max_loss" numeric(18,2),
  "daily_max_gain" numeric(18,2),
  "asset_types" jsonb,
  "sectors" jsonb,
  "entry_syle" enum(),
  "exit_personality" enum(),
  "armor" enum(),
  "effective_from" timestamp,
  "created_at" timestamp
);

CREATE TABLE "bot_runtime_date" (
  "id" bigserial PRIMARY KEY,
  "bot_id" bigserial NOT NULL,
  "trading_day" date,
  "pnl_realized" numeric(18,2),
  "pnl_unrealized" numeric(18,2),
  "proposals_generated" int,
  "approvals_count" int,
  "stands_down" bool,
  "standdown_reason" text,
  "updated_at" timestamp
);

CREATE TABLE "trade_proposals" (
  "id" bigserial PRIMARY KEY,
  "bot_id" bigserial NOT NULL,
  "user_id" bigserial NOT NULL,
  "symbol" text,
  "side" "enum(BUY,SELL)",
  "qty" numeric(18,6),
  "entry_type" "enum(MARKET,LIMIT)",
  "limit_price" numeric(18,6),
  "stop_price" numeric(18,6),
  "target_price" numeric(18,6),
  "min_hold_until" timestamp,
  "confidence" numeric(5,4),
  "rationale_structured" jsonb,
  "rationale_text" text,
  "status" "enum(PENDING,APPROVED,SKIPPED,EXPIRED,CANCELLED)",
  "expires_at" timestamp,
  "created_at" timestamp
);

CREATE TABLE "proposal_actions" (
  "id" bigserial PRIMARY KEY,
  "proposal_id" bigserial NOT NULL,
  "user_id" bigserial NOT NULL,
  "action" "enum(APPROVE,SKIP)",
  "created_at" timestamp
);

CREATE TABLE "orders" (
  "id" bigserial PRIMARY KEY,
  "proposal_id" bigserial NOT NULL,
  "user_id" bigserial NOT NULL,
  "bot_id" bigserial NOT NULL,
  "provider" enum(...),
  "provider_order_id" text,
  "status" "enum(CREATED,SUBMITTED,FILLED,PARTIALLY_FILLED,CANCELLED,REJECTED)",
  "raw_payload" jsonb,
  "submitted_at" timestamp,
  "filled_at" timestamp
);

CREATE TABLE "fills" (
  "id" bigserial PRIMARY KEY,
  "order_id" bigserial NOT NULL,
  "provider_fill_id" text,
  "qty" numeric(18,6),
  "price" numeric(18,6),
  "fee" numeric(18,6),
  "filled_at" timestamp,
  "raw_payload" jsonb
);

CREATE TABLE "positions" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "bot_id" bigserial NOT NULL,
  "symbol" text,
  "qty" numeric(18,6),
  "opened_at" timestamp,
  "closed_at" timestamp,
  "min_hold_until" timestamp,
  "status" "enum(OPEN,CLOSED)"
);

CREATE TABLE "position_events" (
  "id" bigserial PRIMARY KEY,
  "position_id" bigserial NOT NULL,
  "type" "enum(OPENED,UPDATED,STOP_TRIGGERED,CLOSED)",
  "payload" jsonb,
  "created_at" timestamp
);

CREATE TABLE "audit_events" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigserial NOT NULL,
  "bot_id" bigserial NOT NULL,
  "event_type" text,
  "payload" jsonb,
  "created_at" timestamp
);

CREATE INDEX ON "users" ("username");

CREATE INDEX ON "users" ("email");

CREATE INDEX ON "profiles" ("user_id");

CREATE INDEX ON "profiles" ("display_name");

ALTER TABLE "user_settings" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "profiles" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "metrics" ADD FOREIGN KEY ("profile_id") REFERENCES "profiles" ("id");

ALTER TABLE "wallets" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "banking_connections" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "bank_accounts" ADD FOREIGN KEY ("banking_connection_id") REFERENCES "banking_connections" ("id");

ALTER TABLE "transfers" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "transfers" ADD FOREIGN KEY ("wallet_id") REFERENCES "wallets" ("id");

ALTER TABLE "ledger_accounts" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "ledger_entries" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "ledger_lines" ADD FOREIGN KEY ("ledger_entry_id") REFERENCES "ledger_entries" ("id");

ALTER TABLE "ledger_lines" ADD FOREIGN KEY ("ledger_account_id") REFERENCES "ledger_accounts" ("id");

ALTER TABLE "broker_connections" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "broker_accounts" ADD FOREIGN KEY ("broker_connection_id") REFERENCES "broker_connections" ("id");

ALTER TABLE "broker_events" ADD FOREIGN KEY ("provider") REFERENCES "broker_connections" ("id");

ALTER TABLE "bots" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "bots" ADD FOREIGN KEY ("avatar_id") REFERENCES "bot_avatars" ("id");

ALTER TABLE "bot_settings" ADD FOREIGN KEY ("bot_id") REFERENCES "bots" ("id");

ALTER TABLE "bot_runtime_date" ADD FOREIGN KEY ("bot_id") REFERENCES "bots" ("id");

ALTER TABLE "trade_proposals" ADD FOREIGN KEY ("bot_id") REFERENCES "bots" ("id");

ALTER TABLE "trade_proposals" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "proposal_actions" ADD FOREIGN KEY ("proposal_id") REFERENCES "trade_proposals" ("id");

ALTER TABLE "proposal_actions" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "orders" ADD FOREIGN KEY ("proposal_id") REFERENCES "trade_proposals" ("id");

ALTER TABLE "orders" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "orders" ADD FOREIGN KEY ("bot_id") REFERENCES "bots" ("id");

ALTER TABLE "fills" ADD FOREIGN KEY ("order_id") REFERENCES "orders" ("id");

ALTER TABLE "positions" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "positions" ADD FOREIGN KEY ("bot_id") REFERENCES "bots" ("id");

ALTER TABLE "position_events" ADD FOREIGN KEY ("position_id") REFERENCES "positions" ("id");

ALTER TABLE "audit_events" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "audit_events" ADD FOREIGN KEY ("bot_id") REFERENCES "bots" ("id");

ALTER TABLE "bot_settings" ADD FOREIGN KEY ("version") REFERENCES "bot_settings" ("id");

ALTER TABLE "metrics" ADD FOREIGN KEY ("profile_id") REFERENCES "metrics" ("id");
