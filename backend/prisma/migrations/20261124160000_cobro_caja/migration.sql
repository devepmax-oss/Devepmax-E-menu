-- Cobro en caja: idempotencia y referencia del cobro
ALTER TABLE "public"."Payment" ADD COLUMN     "clientRequestId" TEXT,
ADD COLUMN     "reference" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Payment_clientRequestId_key" ON "public"."Payment"("clientRequestId");
