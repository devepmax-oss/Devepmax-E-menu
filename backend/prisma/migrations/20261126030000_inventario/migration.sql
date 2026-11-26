-- Inventario: ingredientes, recetas, proveedores, entradas, conteos, mermas y ventas

-- CreateEnum
CREATE TYPE "public"."StockMoveType" AS ENUM ('SALE', 'RECEIPT', 'COUNT', 'WASTE', 'ADJUST');

-- AlterTable
ALTER TABLE "public"."Product" ADD COLUMN     "soldOutByStock" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "public"."RestaurantSettings" ADD COLUMN     "inventoryAutoSoldOut" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "inventoryEnabled" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "public"."Supplier" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "contactName" TEXT,
    "phone" TEXT,
    "email" TEXT,
    "notes" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Supplier_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."InventoryItem" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "unit" TEXT NOT NULL DEFAULT 'unit',
    "onHand" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "minLevel" DECIMAL(12,3),
    "costPerUnit" DECIMAL(12,4) NOT NULL DEFAULT 0,
    "supplierId" TEXT,
    "sku" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."RecipeLine" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "quantity" DECIMAL(12,3) NOT NULL,

    CONSTRAINT "RecipeLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."StockMovement" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "type" "public"."StockMoveType" NOT NULL,
    "quantity" DECIMAL(12,3) NOT NULL,
    "unitCost" DECIMAL(12,4),
    "orderItemId" TEXT,
    "receiptId" TEXT,
    "reason" TEXT,
    "employeeId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StockMovement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."StockReceipt" (
    "id" TEXT NOT NULL,
    "supplierId" TEXT,
    "reference" TEXT,
    "notes" TEXT,
    "total" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "employeeId" TEXT,
    "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StockReceipt_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "InventoryItem_isActive_idx" ON "public"."InventoryItem"("isActive");

-- CreateIndex
CREATE INDEX "RecipeLine_itemId_idx" ON "public"."RecipeLine"("itemId");

-- CreateIndex
CREATE UNIQUE INDEX "RecipeLine_productId_itemId_key" ON "public"."RecipeLine"("productId", "itemId");

-- CreateIndex
CREATE INDEX "StockMovement_itemId_createdAt_idx" ON "public"."StockMovement"("itemId", "createdAt");

-- CreateIndex
CREATE INDEX "StockMovement_orderItemId_idx" ON "public"."StockMovement"("orderItemId");

-- CreateIndex
CREATE INDEX "StockMovement_type_createdAt_idx" ON "public"."StockMovement"("type", "createdAt");

-- CreateIndex
CREATE INDEX "StockReceipt_receivedAt_idx" ON "public"."StockReceipt"("receivedAt");

-- AddForeignKey
ALTER TABLE "public"."InventoryItem" ADD CONSTRAINT "InventoryItem_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "public"."Supplier"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."RecipeLine" ADD CONSTRAINT "RecipeLine_productId_fkey" FOREIGN KEY ("productId") REFERENCES "public"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."RecipeLine" ADD CONSTRAINT "RecipeLine_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "public"."InventoryItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."StockMovement" ADD CONSTRAINT "StockMovement_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "public"."InventoryItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."StockMovement" ADD CONSTRAINT "StockMovement_receiptId_fkey" FOREIGN KEY ("receiptId") REFERENCES "public"."StockReceipt"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."StockReceipt" ADD CONSTRAINT "StockReceipt_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "public"."Supplier"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- El permiso nuevo "inventory.manage" para los roles Admin y Gerente
UPDATE "public"."Role" SET "permissions" = array_append("permissions", 'inventory.manage')
WHERE "name" IN ('Admin', 'Gerente') AND NOT ('inventory.manage' = ANY("permissions"));
