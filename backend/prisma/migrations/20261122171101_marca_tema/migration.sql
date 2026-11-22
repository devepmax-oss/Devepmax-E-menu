-- AlterTable
ALTER TABLE "public"."RestaurantSettings" ADD COLUMN     "fontPair" TEXT NOT NULL DEFAULT 'bricolage-inter',
ADD COLUMN     "themeMode" TEXT NOT NULL DEFAULT 'dark',
ALTER COLUMN "primaryColor" SET DEFAULT '#FF7A1A',
ALTER COLUMN "accentColor" SET DEFAULT '#FFC247';
