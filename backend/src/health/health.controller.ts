import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../common/auth/decorators';

@ApiTags('health')
@Controller('health')
export class HealthController {
  @Public()
  @Get()
  check(): { ok: true; service: string; timestamp: string } {
    return {
      ok: true,
      service: 'devepmax-emenu-backend',
      timestamp: new Date().toISOString(),
    };
  }
}
