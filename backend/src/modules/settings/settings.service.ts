import { BadRequestException, Injectable } from '@nestjs/common';
import { RestaurantSettings } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { ImageService } from '../../storage/image.service';
import { AuditService } from '../audit/audit.service';
import { ReplaceOpeningHoursDto, UpdateSettingsDto } from './dto/settings.dto';

const SETTINGS_ID = 1;
const DEFAULT_NAME = 'Mi Restaurante';

function isValidTimezone(timezone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: timezone });
    return true;
  } catch {
    return false;
  }
}

@Injectable()
export class SettingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly images: ImageService,
  ) {}

  async get(): Promise<RestaurantSettings> {
    return (
      (await this.prisma.restaurantSettings.findUnique({ where: { id: SETTINGS_ID } })) ??
      this.prisma.restaurantSettings.create({ data: { id: SETTINGS_ID, name: DEFAULT_NAME } })
    );
  }

  /** Lo que pueden ver la web pública y las tablets sin autenticación. */
  async getPublic() {
    const [settings, hours] = await Promise.all([
      this.get(),
      this.prisma.openingHour.findMany({ orderBy: [{ dayOfWeek: 'asc' }, { opensAt: 'asc' }] }),
    ]);
    return {
      name: settings.name,
      logoUrl: settings.logoUrl,
      primaryColor: settings.primaryColor,
      accentColor: settings.accentColor,
      themeMode: settings.themeMode,
      fontPair: settings.fontPair,
      phone: settings.phone,
      whatsapp: settings.whatsapp,
      email: settings.email,
      address: {
        line: settings.addressLine,
        city: settings.city,
        state: settings.state,
        zipCode: settings.zipCode,
        lat: settings.lat,
        lng: settings.lng,
      },
      socialLinks: settings.socialLinks,
      timezone: settings.timezone,
      currency: settings.currency,
      locales: settings.locales,
      channels: {
        dineIn: settings.acceptsDineIn,
        pickup: settings.acceptsPickup,
        delivery: settings.acceptsDelivery,
        onlineOrderingPaused: settings.onlineOrderingPaused,
      },
      prepTimeMinutes: settings.prepTimeMinutes,
      tipPresets: settings.tipPresets,
      maintenanceMode: settings.maintenanceMode,
      loyalty: {
        enabled: settings.loyaltyEnabled,
        pointsPerDollar: settings.loyaltyPointsPerDollar,
        rewardPoints: settings.loyaltyRewardPoints,
        rewardAmount: settings.loyaltyRewardAmount,
        birthday: settings.birthdayRewardEnabled,
        birthdayAmount: settings.birthdayRewardAmount,
      },
      openingHours: hours.map(({ dayOfWeek, opensAt, closesAt }) => ({ dayOfWeek, opensAt, closesAt })),
    };
  }

  async update(actor: EmployeeActor, dto: UpdateSettingsDto): Promise<RestaurantSettings> {
    if (dto.timezone && !isValidTimezone(dto.timezone)) {
      throw new BadRequestException('Zona horaria inválida');
    }
    const data = { ...dto, currency: dto.currency?.toUpperCase() };
    const settings = await this.prisma.restaurantSettings.upsert({
      where: { id: SETTINGS_ID },
      update: data,
      create: { ...data, id: SETTINGS_ID, name: dto.name ?? DEFAULT_NAME },
    });
    await this.audit.log(actor, 'settings.update', 'settings', String(SETTINGS_ID), {
      fields: Object.keys(dto),
    });
    return settings;
  }

  async replaceOpeningHours(actor: EmployeeActor, dto: ReplaceOpeningHoursDto) {
    if (dto.hours.some((h) => h.opensAt === h.closesAt)) {
      throw new BadRequestException('La hora de apertura y cierre no pueden ser iguales');
    }
    await this.prisma.$transaction([
      this.prisma.openingHour.deleteMany(),
      this.prisma.openingHour.createMany({ data: dto.hours }),
    ]);
    await this.audit.log(actor, 'settings.opening_hours', 'settings', String(SETTINGS_ID), {
      count: dto.hours.length,
    });
    return this.prisma.openingHour.findMany({ orderBy: [{ dayOfWeek: 'asc' }, { opensAt: 'asc' }] });
  }

  async setLogo(actor: EmployeeActor, file: { buffer: Buffer; mimetype: string; size: number }) {
    const current = await this.get();
    const logoUrl = await this.images.save('brand', file);
    const settings = await this.prisma.restaurantSettings.update({ where: { id: SETTINGS_ID }, data: { logoUrl } });
    await this.images.remove(current.logoUrl);
    await this.audit.log(actor, 'settings.logo', 'settings', String(SETTINGS_ID));
    return settings;
  }

  async removeLogo(actor: EmployeeActor) {
    const current = await this.get();
    const settings = await this.prisma.restaurantSettings.update({
      where: { id: SETTINGS_ID },
      data: { logoUrl: null },
    });
    await this.images.remove(current.logoUrl);
    await this.audit.log(actor, 'settings.logo_removed', 'settings', String(SETTINGS_ID));
    return settings;
  }
}
