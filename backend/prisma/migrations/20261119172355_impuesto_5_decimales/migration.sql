-- AlterTable
ALTER TABLE "public"."OrderItem" ALTER COLUMN "taxRate" SET DATA TYPE DECIMAL(7,5);

-- AlterTable
ALTER TABLE "public"."TaxRate" ALTER COLUMN "rate" SET DATA TYPE DECIMAL(7,5);
