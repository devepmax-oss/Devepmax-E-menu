import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Patch,
  Post,
  Put,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { MAX_IMAGE_BYTES } from '../../storage/image.service';
import { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, Public, RequirePermissions } from '../../common/auth/decorators';
import { ReplaceOpeningHoursDto, UpdateSettingsDto } from './dto/settings.dto';
import { SettingsService } from './settings.service';

@ApiTags('settings')
@Controller('settings')
export class SettingsController {
  constructor(private readonly settings: SettingsService) {}

  /** Marca, canales y horarios para la web pública y las apps. */
  @Public()
  @Get('public')
  getPublic() {
    return this.settings.getPublic();
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Get()
  get() {
    return this.settings.get();
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Patch()
  update(@CurrentActor() actor: EmployeeActor, @Body() dto: UpdateSettingsDto) {
    return this.settings.update(actor, dto);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Put('opening-hours')
  replaceOpeningHours(@CurrentActor() actor: EmployeeActor, @Body() dto: ReplaceOpeningHoursDto) {
    return this.settings.replaceOpeningHours(actor, dto);
  }

  @ApiBearerAuth()
  @ApiConsumes('multipart/form-data')
  @ApiBody({ schema: { type: 'object', properties: { file: { type: 'string', format: 'binary' } } } })
  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Post('logo')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_IMAGE_BYTES, files: 1 } }))
  setLogo(@CurrentActor() actor: EmployeeActor, @UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('Falta la imagen (campo "file")');
    return this.settings.setLogo(actor, file);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Delete('logo')
  removeLogo(@CurrentActor() actor: EmployeeActor) {
    return this.settings.removeLogo(actor);
  }
}
