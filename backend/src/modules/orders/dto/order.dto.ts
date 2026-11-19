import { FulfillmentType, TicketStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

export class OrderLineDto {
  @IsString() productId: string;
  @IsInt() @Min(1) @Max(99) quantity: number;
  /** Opciones de modificadores elegidas. */
  @IsOptional() @IsArray() @ArrayUnique() @ArrayMaxSize(50) @IsString({ each: true }) optionIds?: string[];
  @IsOptional() @IsString() @MaxLength(300) notes?: string;
  /** Asiento (para dividir la cuenta). */
  @IsOptional() @IsInt() @Min(1) @Max(50) seat?: number;
}

export class CreateOrderDto {
  /** Identificador único generado por la app: si se reenvía, no se duplica la orden. */
  @Matches(/^[A-Za-z0-9_-]{8,64}$/, { message: 'clientRequestId inválido' })
  clientRequestId: string;

  @IsIn(['DINE_IN', 'TAKEOUT', 'PICKUP'])
  fulfillmentType: Extract<FulfillmentType, 'DINE_IN' | 'TAKEOUT' | 'PICKUP'>;

  /** Mesa (órdenes en sala desde POS o mesero). Las tablets usan su propia mesa. */
  @IsOptional() @IsString() tableId?: string;

  @IsOptional() @IsString() @MaxLength(80) customerName?: string;
  @IsOptional() @IsString() @MaxLength(30) customerPhone?: string;
  @IsOptional() @IsString() @MaxLength(500) notes?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => OrderLineDto)
  items: OrderLineDto[];
}

export class CancelOrderDto {
  @IsString() @MinLength(3) @MaxLength(300) reason: string;
}

export class OrdersQueryDto {
  /** active = en curso; today = todas las del día de operación. */
  @IsOptional() @IsIn(['active', 'today']) scope?: 'active' | 'today';
}

export class UpdateTicketDto {
  @IsIn(['NEW', 'ACCEPTED', 'PREPARING', 'READY', 'COMPLETED'])
  status: Exclude<TicketStatus, 'CANCELLED'>;
}

export class KitchenQueryDto {
  @IsOptional() @IsString() stationId?: string;
}
