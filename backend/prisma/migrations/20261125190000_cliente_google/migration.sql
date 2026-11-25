-- "Continuar con Google" para la cuenta de cliente
ALTER TABLE "public"."Customer" ADD COLUMN     "googleId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Customer_googleId_key" ON "public"."Customer"("googleId");
