import { HttpException } from '@nestjs/common';
import { AttemptLimiter } from './attempt-limiter';

describe('AttemptLimiter', () => {
  it('bloquea tras el máximo de fallos y libera al vencer la ventana', () => {
    let now = 0;
    const limiter = new AttemptLimiter(3, 1000, () => now);
    for (let i = 0; i < 3; i++) {
      limiter.assertAllowed('k');
      limiter.fail('k');
    }
    expect(() => limiter.assertAllowed('k')).toThrow(HttpException);
    now = 1001;
    expect(() => limiter.assertAllowed('k')).not.toThrow();
  });

  it('reset limpia los fallos', () => {
    const limiter = new AttemptLimiter(1, 1000);
    limiter.fail('k');
    limiter.reset('k');
    expect(() => limiter.assertAllowed('k')).not.toThrow();
  });
});
