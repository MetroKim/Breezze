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
