/**
 * Datos iniciales de una instalación: roles de fábrica, ajustes y primer administrador.
 * Es seguro ejecutarlo varias veces. Uso: npm run db:seed
 */
import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/common/crypto';
import { ADMIN_ROLE_NAME, DEFAULT_ROLES, PERMISSIONS } from '../src/common/permissions';

const prisma = new PrismaClient();

async function main(): Promise<void> {
  try {
    process.loadEnvFile();
  } catch {
    // variables del sistema
  }

  for (const role of DEFAULT_ROLES) {
    const existing = await prisma.role.findUnique({ where: { name: role.name } });
    if (!existing) {
      await prisma.role.create({
        data: { name: role.name, permissions: [...role.permissions], isSystem: true },
      });
      console.log(`Rol creado: ${role.name}`);
    } else if (role.name === ADMIN_ROLE_NAME) {
      // El administrador siempre recibe los permisos nuevos que traiga cada versión.
      await prisma.role.update({ where: { id: existing.id }, data: { permissions: [...PERMISSIONS] } });
    }
  }

  const restaurantName = process.env.SEED_RESTAURANT_NAME?.trim() || 'Mi Restaurante';
  await prisma.restaurantSettings.upsert({
    where: { id: 1 },
    update: {},
    create: { id: 1, name: restaurantName },
  });

  if ((await prisma.kitchenStation.count()) === 0) {
    await prisma.kitchenStation.create({ data: { name: 'Cocina', color: '#EF4444' } });
    console.log('Estación creada: Cocina');
  }

  if ((await prisma.taxRate.count()) === 0) {
    // Se ajusta luego en el panel con la tasa real del condado.
    await prisma.taxRate.create({ data: { name: 'Sales tax', rate: 0, isDefault: true } });
    console.log('Impuesto creado: Sales tax (0 %). Ajusta la tasa en el panel.');
  }

  const adminRole = await prisma.role.findUniqueOrThrow({ where: { name: ADMIN_ROLE_NAME } });
  const hasAdmin = await prisma.employee.count({ where: { roleId: adminRole.id, isActive: true } });
  const email = process.env.SEED_ADMIN_EMAIL?.trim().toLowerCase();
  const password = process.env.SEED_ADMIN_PASSWORD ?? '';

  if (hasAdmin === 0) {
    if (!email || password.length < 8) {
      console.warn('Sin administrador: define SEED_ADMIN_EMAIL y SEED_ADMIN_PASSWORD (mín. 8) y repite.');
    } else {
      await prisma.employee.create({
        data: {
          name: process.env.SEED_ADMIN_NAME?.trim() || 'Administrador',
          email,
          passwordHash: await hashPassword(password),
          roleId: adminRole.id,
        },
      });
      console.log(`Administrador creado: ${email}`);
    }
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
