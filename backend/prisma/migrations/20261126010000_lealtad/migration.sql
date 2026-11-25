-- Lealtad: puntos por dólar, premio en cupón y regalo de cumpleaños

-- CreateEnum
CREATE TYPE "public"."LoyaltyTxType" AS ENUM ('EARN', 'REWARD', 'ADJUST');

-- AlterTable
ALTER TABLE "public"."Customer" ADD COLUMN     "birthDay" INTEGER,
ADD COLUMN     "birthMonth" INTEGER,
ADD COLUMN     "birthdayRewardYear" INTEGER,
ADD COLUMN     "points" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "public"."RestaurantSettings" ADD COLUMN     "birthdayRewardAmount" DECIMAL(10,2) NOT NULL DEFAULT 10,
ADD COLUMN     "birthdayRewardEnabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "loyaltyEnabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "loyaltyPointsPerDollar" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN     "loyaltyRewardAmount" DECIMAL(10,2) NOT NULL DEFAULT 5,
ADD COLUMN     "loyaltyRewardDays" INTEGER NOT NULL DEFAULT 60,
ADD COLUMN     "loyaltyRewardPoints" INTEGER NOT NULL DEFAULT 100;

-- CreateTable
CREATE TABLE "public"."LoyaltyTransaction" (
    "id" TEXT NOT NULL,
    "customerId" TEXT NOT NULL,
    "type" "public"."LoyaltyTxType" NOT NULL,
    "points" INTEGER NOT NULL,
    "billId" TEXT,
    "couponId" TEXT,
    "reason" TEXT,
    "employeeId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LoyaltyTransaction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "LoyaltyTransaction_customerId_createdAt_idx" ON "public"."LoyaltyTransaction"("customerId", "createdAt");

-- CreateIndex
CREATE INDEX "LoyaltyTransaction_billId_idx" ON "public"."LoyaltyTransaction"("billId");

-- AddForeignKey
ALTER TABLE "public"."LoyaltyTransaction" ADD CONSTRAINT "LoyaltyTransaction_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "public"."Customer"("id") ON DELETE CASCADE ON UPDATE CASCADE;
