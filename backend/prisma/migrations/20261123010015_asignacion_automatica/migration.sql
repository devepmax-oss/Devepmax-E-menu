-- AlterTable
ALTER TABLE "public"."DeliveryAssignment" ADD COLUMN     "autoAssigned" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "skippedDriverIds" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "public"."RestaurantSettings" ADD COLUMN     "autoAssignDrivers" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "driverOfferSeconds" INTEGER NOT NULL DEFAULT 60;
