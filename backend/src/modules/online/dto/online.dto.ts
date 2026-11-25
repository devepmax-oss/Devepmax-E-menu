import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsEmail,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { OrderLineDto } from '../../orders/dto/order.dto';

export class OnlineCustomerDto {
  @IsString() @MinLength(2) @MaxLength(80) name: string;
  @Matches(/^[0-9+()\-.\s]{7,20}$/, { message: 'Teléfono inválido' }) phone: string;
  @IsOptional() @IsEmail({}, { message: 'Email inválido' }) email?: string;
}

export class DeliveryAddressDto {
  @IsString() @MinLength(3) @MaxLength(200) street: string;
  @IsString() @MinLength(2) @MaxLength(100) city: string;
  @IsString() @Length(2, 50) state: string;
  @Matches(/^\d{5}(-\d{4})?$/, { message: 'Código postal inválido' }) zipCode: string;
  @IsOptional() @IsString() @MaxLength(300) instructions?: string;
}

export class OnlineQuoteDto {
  @IsIn(['PICKUP', 'DELIVERY']) fulfillmentType: 'PICKUP' | 'DELIVERY';

  /** Propina en dólares (la web la calcula con los porcentajes sugeridos). */
  @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(500) tipAmount?: number;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => OrderLineDto)
  items: OrderLineDto[];
}

export class CreateOnlineOrderDto extends OnlineQuoteDto {
  /** Generado por la web: si el cliente toca "Pagar" dos veces, no se duplica el pedido. */
  @Matches(/^[A-Za-z0-9_-]{8,64}$/, { message: 'clientRequestId inválido' }) clientRequestId: string;

  @ValidateNested() @Type(() => OnlineCustomerDto) customer: OnlineCustomerDto;

  @IsOptional() @ValidateNested() @Type(() => DeliveryAddressDto) deliveryAddress?: DeliveryAddressDto;

  /** Con cuenta de cliente: guardar la dirección para la próxima vez. */
  @IsOptional() @IsBoolean() saveAddress?: boolean;

  @IsOptional() @IsString() @MaxLength(500) notes?: string;

  /** card = paga ahora con Stripe; pay_at_pickup = paga al recoger (solo Pickup). */
  @IsIn(['card', 'pay_at_pickup']) paymentMethod: 'card' | 'pay_at_pickup';
}
