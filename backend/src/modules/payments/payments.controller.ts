import { BadRequestException, Controller, Headers, HttpCode, Post, RawBodyRequest, Req } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Request } from 'express';
import type Stripe from 'stripe';
import { Public } from '../../common/auth/decorators';
import { PaymentsService } from './payments.service';
import { StripeService } from './stripe.service';

/** Avisos de Stripe (webhook). Stripe firma cada aviso; sin firma válida se rechaza. */
@ApiExcludeController()
@Controller('payments/stripe')
export class StripeWebhookController {
  constructor(
    private readonly stripe: StripeService,
    private readonly payments: PaymentsService,
  ) {}

  @Public()
  @Post('webhook')
  @HttpCode(200)
  async webhook(@Req() req: RawBodyRequest<Request>, @Headers('stripe-signature') signature?: string) {
    if (!signature || !req.rawBody) throw new BadRequestException('Falta la firma de Stripe');
    const event = this.stripe.constructEvent(req.rawBody, signature);
    if (event.type === 'payment_intent.succeeded' || event.type === 'payment_intent.canceled') {
      await this.payments.applyPaymentIntent(event.data.object as Stripe.PaymentIntent);
    }
    return { received: true };
  }
}
