import {
  Controller, Delete, Get, Header, HttpCode, HttpStatus,
  Post, Query, Res, UseGuards, Param,
} from '@nestjs/common';
import type { Response } from 'express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { YoutubeAccountService } from './youtube-account.service';

/**
 * Separate opt-in YouTube account connection.
 * It never reuses Breezze's Supabase/Google social login authorization.
 */
@Controller('youtube-account')
export class YoutubeAccountController {
  constructor(private readonly accounts: YoutubeAccountService) {}

  @Get('status')
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  status(@CurrentUser() userId: string) {
    return this.accounts.status(userId);
  }

  @Get('diagnostics')
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  diagnostics(@CurrentUser() userId: string) {
    return this.accounts.diagnostics(userId);
  }

  @Post('start')
  @HttpCode(HttpStatus.OK)
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  start(@CurrentUser() userId: string) {
    return this.accounts.start(userId);
  }

  @Get('playlists')
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  playlists(@CurrentUser() userId: string) {
    return this.accounts.playlists(userId);
  }

  @Get('playlists/:playlistId/items')
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  playlistItems(
    @CurrentUser() userId: string,
    @Param('playlistId') playlistId: string,
  ) {
    return this.accounts.playlistItems(userId, playlistId);
  }

  @Delete('connection')
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  disconnect(@CurrentUser() userId: string) {
    return this.accounts.disconnect(userId);
  }

  @Get('callback')
  @Header('Cache-Control', 'no-store')
  async callback(
    @Query('state') state: string | undefined,
    @Query('code') code: string | undefined,
    @Query('error') error: string | undefined,
    @Res() res: Response,
  ) {
    const ok = await this.accounts.callback(state ?? '', code, error);
    // No token, state, auth code, email, or user identifiers ever reach
    // the rendered browser response.
    res.status(ok ? 200 : 400)
      .type('html')
      .send(
        '<!doctype html><html lang="en"><head><meta name="viewport" ' +
        'content="width=device-width,initial-scale=1">' +
        '<meta name="referrer" content="no-referrer">' +
        '<title>Breezze YouTube connection</title></head>' +
        '<body style="background:#080808;color:#fff;font-family:system-ui;' +
        'max-width:460px;margin:12vh auto;padding:24px">' +
        '<h1>' + (ok ? 'YouTube account connected' : 'Connection not completed') + '</h1>' +
        '<p>' + (ok
          ? 'Return to Breezze and select Refresh connection.'
          : 'Return to Breezze and try connecting again.') +
        '</p></body></html>',
      );
  }
}
