import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import * as crypto from 'crypto';
import { AppModule } from './app.module';
import { ResponseEnvelopeInterceptor } from './response-envelope.interceptor';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.use(helmet());

  const edgeSecret = process.env.EDGE_SHARED_SECRET;
  if (process.env.NODE_ENV === 'production' && (!edgeSecret || edgeSecret.length < 32)) {
    throw new Error('EDGE_SHARED_SECRET must be configured with at least 32 characters in production');
  }

  // When configured, only the Cloudflare API Worker may reach the API.
  // The Worker strips any client-supplied value and injects this secret.
  if (edgeSecret) {
    app.use((req: any, res: any, next: () => void) => {
      const supplied = req.headers['x-breezze-edge-secret'];
      const expectedBuffer = Buffer.from(edgeSecret);
      const suppliedBuffer = Buffer.from(typeof supplied === 'string' ? supplied : '');
      const valid = suppliedBuffer.length === expectedBuffer.length
        && crypto.timingSafeEqual(suppliedBuffer, expectedBuffer);
      if (!valid) {
        res.status(403).json({ statusCode: 403, error: 'EDGE_ACCESS_DENIED' });
        return;
      }
      next();
    });
  }

  app.use((req: any, res: any, next: () => void) => {
    req.requestId = crypto.randomUUID();
    res.setHeader('X-Request-Id', req.requestId);
    next();
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.useGlobalInterceptors(new ResponseEnvelopeInterceptor());

  app.setGlobalPrefix('api/v1');
  const allowedOrigins = (process.env.CORS_ALLOWED_ORIGINS
    ?? (process.env.NODE_ENV === 'production' ? '' : 'http://localhost:3000,http://localhost:5173'))
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  // Never reflect arbitrary browser origins while allowing credentials.
  // Native clients normally omit Origin and are unaffected by browser CORS.
  app.enableCors({
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.includes(origin)) {
        return callback(null, true);
      }
      return callback(null, false);
    },
    credentials: true,
  });

  const swagger = new DocumentBuilder()
    .setTitle('Breezze API')
    .setVersion('0.1.0')
    .addBearerAuth()
    .build();
  SwaggerModule.setup('api/docs', app, SwaggerModule.createDocument(app, swagger));

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
}
bootstrap();
