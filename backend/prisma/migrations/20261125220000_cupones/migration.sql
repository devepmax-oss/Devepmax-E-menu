-- Cupones: descuento por % o $ o envío gratis, con límites, fechas y cupones personales

-- CreateEnum
CREATE TYPE "public"."CouponType" AS ENUM ('PERCENT', 'AMOUNT', 'FREE_DELIVERY');

-- AlterTable
ALTER TABLE "public"."Coupon" ALTER COLUMN "promotionId" DROP NOT NULL,
ADD COLUMN     "appliesInStore" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "appliesOnline" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "customerId" TEXT,
ADD COLUMN     "firstOrderOnly" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "maxDiscount" DECIMAL(10,2),
ADD COLUMN     "name" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "type" "public"."CouponType" NOT NULL DEFAULT 'PERCENT',
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "value" DECIMAL(10,2);

-- AlterTable
ALTER TABLE "public"."CouponRedemption" ADD COLUMN     "amount" DECIMAL(10,2) NOT NULL DEFAULT 0,
ADD COLUMN     "billId" TEXT,
ADD COLUMN     "customerPhone" TEXT;

-- CreateIndex
CREATE INDEX "CouponRedemption_couponId_idx" ON "public"."CouponRedemption"("couponId");

-- CreateIndex
CREATE INDEX "CouponRedemption_customerId_idx" ON "public"."CouponRedemption"("customerId");

-- AddForeignKey
ALTER TABLE "public"."Coupon" ADD CONSTRAINT "Coupon_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "public"."Customer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."CouponRedemption" ADD CONSTRAINT "CouponRedemption_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "public"."Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
