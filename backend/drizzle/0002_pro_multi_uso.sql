CREATE TABLE "pro_redemptions" (
	"code" text NOT NULL,
	"device_id" text NOT NULL,
	"redeemed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "pro_redemptions_code_device_id_pk" PRIMARY KEY("code","device_id")
);
--> statement-breakpoint
ALTER TABLE "pro_codes" ADD COLUMN "max_redemptions" integer;