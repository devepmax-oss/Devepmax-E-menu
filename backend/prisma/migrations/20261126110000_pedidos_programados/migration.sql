-- Pedidos programados: la orden espera y pasa a cocina sola a su hora
ALTER TYPE "public"."OrderStatus" ADD VALUE 'SCHEDULED' BEFORE 'PENDING_PAYMENT';

ALTER TABLE "public"."Order" ADD COLUMN     "releaseAt" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "Order_status_releaseAt_idx" ON "public"."Order"("status", "releaseAt");

-- Ajuste para activarlos o no
ALTER TABLE "public"."RestaurantSettings" ADD COLUMN     "scheduledOrdersEnabled" BOOLEAN NOT NULL DEFAULT true;
