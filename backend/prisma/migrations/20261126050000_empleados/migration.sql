-- Ficha completa del empleado y bajas
ALTER TABLE "public"."Employee" ADD COLUMN     "address" TEXT,
ADD COLUMN     "emergencyName" TEXT,
ADD COLUMN     "emergencyPhone" TEXT,
ADD COLUMN     "hireDate" DATE,
ADD COLUMN     "jobTitle" TEXT,
ADD COLUMN     "notes" TEXT,
ADD COLUMN     "photoUrl" TEXT,
ADD COLUMN     "terminatedAt" TIMESTAMP(3),
ADD COLUMN     "terminationReason" TEXT;

-- Roles propios con descripción
ALTER TABLE "public"."Role" ADD COLUMN     "description" TEXT;

-- Historial por empleado (lo que hizo cada uno)
CREATE INDEX "AuditLog_actor_createdAt_idx" ON "public"."AuditLog"("actor", "createdAt");
