CREATE TABLE "ai_calls" (
	"id" text PRIMARY KEY NOT NULL,
	"device_id" text NOT NULL,
	"kind" text NOT NULL,
	"model" text NOT NULL,
	"input_tokens" integer DEFAULT 0 NOT NULL,
	"output_tokens" integer DEFAULT 0 NOT NULL,
	"cost_micros" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "devices" (
	"id" text PRIMARY KEY NOT NULL,
	"token_hash" text NOT NULL,
	"platform" text DEFAULT 'ios' NOT NULL,
	"is_pro" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "usage_daily" (
	"device_id" text NOT NULL,
	"day" text NOT NULL,
	"kind" text NOT NULL,
	"count" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "usage_daily_device_id_day_kind_pk" PRIMARY KEY("device_id","day","kind")
);
--> statement-breakpoint
CREATE TABLE "usage_monthly" (
	"device_id" text NOT NULL,
	"month" text NOT NULL,
	"kind" text NOT NULL,
	"count" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "usage_monthly_device_id_month_kind_pk" PRIMARY KEY("device_id","month","kind")
);
--> statement-breakpoint
CREATE INDEX "ai_calls_device_idx" ON "ai_calls" USING btree ("device_id");--> statement-breakpoint
CREATE INDEX "ai_calls_created_idx" ON "ai_calls" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "devices_token_hash_idx" ON "devices" USING btree ("token_hash");