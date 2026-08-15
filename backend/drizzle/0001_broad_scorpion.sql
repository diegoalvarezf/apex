CREATE TABLE "pro_codes" (
	"code" text PRIMARY KEY NOT NULL,
	"issued_to" text,
	"redeemed_by_device_id" text,
	"redeemed_at" timestamp with time zone,
	"expires_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "devices" ADD COLUMN "pro_until" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "devices" ADD COLUMN "registration_ip_hash" text;--> statement-breakpoint
CREATE INDEX "devices_reg_ip_idx" ON "devices" USING btree ("registration_ip_hash","created_at");