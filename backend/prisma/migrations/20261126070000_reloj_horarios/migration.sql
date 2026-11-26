-- Tablet de reloj checador
ALTER TYPE "public"."DeviceType" ADD VALUE 'CLOCK';

-- CreateEnum
CREATE TYPE "public"."TimeEntrySource" AS ENUM ('CLOCK', 'MANUAL');

-- Ajustes del reloj
ALTER TABLE "public"."RestaurantSettings" ADD COLUMN     "clockGraceMinutes" INTEGER NOT NULL DEFAULT 5,
ADD COLUMN     "paidBreakMinutes" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "public"."TimeEntry" (
    "id" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "clockIn" TIMESTAMP(3) NOT NULL,
    "clockOut" TIMESTAMP(3),
    "source" "public"."TimeEntrySource" NOT NULL DEFAULT 'CLOCK',
    "deviceId" TEXT,
    "note" TEXT,
    "editedAt" TIMESTAMP(3),
    "editedById" TEXT,
    "editReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TimeEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."TimeBreak" (
    "id" TEXT NOT NULL,
    "entryId" TEXT NOT NULL,
    "start" TIMESTAMP(3) NOT NULL,
    "end" TIMESTAMP(3),

    CONSTRAINT "TimeBreak_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Shift" (
    "id" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "start" TIMESTAMP(3) NOT NULL,
    "end" TIMESTAMP(3) NOT NULL,
    "position" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Shift_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "TimeEntry_employeeId_clockIn_idx" ON "public"."TimeEntry"("employeeId", "clockIn");

-- CreateIndex
CREATE INDEX "TimeEntry_clockIn_idx" ON "public"."TimeEntry"("clockIn");

-- CreateIndex
CREATE INDEX "TimeEntry_clockOut_idx" ON "public"."TimeEntry"("clockOut");

-- CreateIndex
CREATE INDEX "TimeBreak_entryId_idx" ON "public"."TimeBreak"("entryId");

-- CreateIndex
CREATE INDEX "Shift_start_idx" ON "public"."Shift"("start");

-- CreateIndex
CREATE INDEX "Shift_employeeId_start_idx" ON "public"."Shift"("employeeId", "start");

-- AddForeignKey
ALTER TABLE "public"."TimeEntry" ADD CONSTRAINT "TimeEntry_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "public"."Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."TimeBreak" ADD CONSTRAINT "TimeBreak_entryId_fkey" FOREIGN KEY ("entryId") REFERENCES "public"."TimeEntry"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Shift" ADD CONSTRAINT "Shift_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "public"."Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
