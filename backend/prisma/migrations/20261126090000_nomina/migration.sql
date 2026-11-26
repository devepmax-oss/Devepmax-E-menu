-- Reglas de horas extra
ALTER TABLE "public"."RestaurantSettings" ADD COLUMN     "doubleTimeDailyHours" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "doubleTimeMultiplier" DECIMAL(4,2) NOT NULL DEFAULT 2,
ADD COLUMN     "overtimeDailyHours" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "overtimeMultiplier" DECIMAL(4,2) NOT NULL DEFAULT 1.5,
ADD COLUMN     "overtimeWeeklyHours" INTEGER NOT NULL DEFAULT 40;

-- CreateTable
CREATE TABLE "public"."PayRate" (
    "id" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "hourlyRate" DECIMAL(10,2) NOT NULL,
    "effectiveFrom" DATE NOT NULL,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PayRate_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PayRate_employeeId_effectiveFrom_key" ON "public"."PayRate"("employeeId", "effectiveFrom");

-- AddForeignKey
ALTER TABLE "public"."PayRate" ADD CONSTRAINT "PayRate_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "public"."Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- El permiso nuevo "payroll.manage" para los roles Admin y Gerente
UPDATE "public"."Role" SET "permissions" = array_append("permissions", 'payroll.manage')
WHERE "name" IN ('Admin', 'Gerente') AND NOT ('payroll.manage' = ANY("permissions"));
