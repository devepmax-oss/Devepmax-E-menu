import { Controller, Get } from '@nestjs/common';

@Controller('health')
export class HealthController {
  @Get()
  check(): { ok: true; service: string; timestamp: string } {
    return {
      ok: true,
      service: 'devepmax-emenu-backend',
      timestamp: new Date().toISOString(),
    };
  }
}
