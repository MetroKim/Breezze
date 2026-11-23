import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { map, Observable } from 'rxjs';

@Injectable()
export class ResponseEnvelopeInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const req = context.switchToHttp().getRequest();
    const cacheableCatalogRead = req.method === 'GET'
      && /^\/api\/v1\/catalog\/(?:songs|albums|artists)\/[A-Za-z0-9_-]{1,128}$/.test(req.path ?? '');
    return next.handle().pipe(
      map((data) => ({
        data,
        meta: {
          request_id: cacheableCatalogRead ? null : req.requestId,
          next_cursor: null,
        },
      })),
    );
  }
}
