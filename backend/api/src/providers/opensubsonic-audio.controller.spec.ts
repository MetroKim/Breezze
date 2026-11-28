import { METHOD_METADATA, PATH_METADATA } from '@nestjs/common/constants';
import { PassThrough } from 'node:stream';
import { RequestMethod } from '@nestjs/common';
import { OpenSubsonicAudioController } from './opensubsonic-audio.controller';
import { OpenSubsonicAdapter } from './opensubsonic.adapter';
import { RightsDecisionService } from '../rights/rights-decision.service';

describe('OpenSubsonic native relay route and rights', () => {
  const validGrant = {
    id: 'original-song',
    userId: 'user1',
    canonicalTrackId: 'e85df20d-45f8-4a40-a271-e00b314a47d7',
    territory: 'TZ',
    expires: Date.now() + 10_000,
  };

  it('registers separate HTTP GET and HEAD handlers', () => {
    expect(Reflect.getMetadata(METHOD_METADATA, OpenSubsonicAudioController.prototype.stream))
      .toBe(RequestMethod.GET);
    expect(Reflect.getMetadata(PATH_METADATA, OpenSubsonicAudioController.prototype.stream))
      .toBe(':id');
    expect(Reflect.getMetadata(METHOD_METADATA, OpenSubsonicAudioController.prototype.head))
      .toBe(RequestMethod.HEAD);
    expect(Reflect.getMetadata(PATH_METADATA, OpenSubsonicAudioController.prototype.head))
      .toBe(':id');
  });

  it('denies an invalid grant before any source or rights request', async () => {
    const adapter = {
      verifyGrant: jest.fn().mockReturnValue(null),
      fetchAuthorizedBytes: jest.fn(),
    };
    const rights = { decide: jest.fn() };
    const controller = new OpenSubsonicAudioController(
      adapter as unknown as OpenSubsonicAdapter,
      rights as unknown as RightsDecisionService,
    );
    await expect(controller.stream('original-song', 'tampered', undefined,
      {} as never, {} as never)).rejects.toThrow('AUDIO_GRANT_INVALID');
    expect(rights.decide).not.toHaveBeenCalled();
    expect(adapter.fetchAuthorizedBytes).not.toHaveBeenCalled();
  });

  it('rechecks a grant against live stream.full rights before upstream byte delivery', async () => {
    const adapter = {
      verifyGrant: jest.fn().mockReturnValue(validGrant),
      fetchAuthorizedBytes: jest.fn(),
    };
    const rights = { decide: jest.fn().mockResolvedValue({
      allowed: false, previewOnly: false, reason: 'TAKEDOWN_ACTIVE',
    }) };
    const controller = new OpenSubsonicAudioController(
      adapter as unknown as OpenSubsonicAdapter,
      rights as unknown as RightsDecisionService,
    );
    await expect(controller.stream('original-song', 'signed', 'bytes=64-127',
      {} as never, {} as never)).rejects.toThrow('AUDIO_RIGHTS_UNAVAILABLE');
    expect(rights.decide).toHaveBeenCalledWith({
      userId: 'user1', trackId: validGrant.canonicalTrackId,
      territory: 'TZ', action: 'stream.full',
    });
    expect(adapter.fetchAuthorizedBytes).not.toHaveBeenCalled();
  });

  it('streams real binary test bytes with backpressure and matching 206 headers', async () => {
    const payload = Buffer.from([0xff, 0xfb, 0x90, 0x64]);
    const upstream = new Response(payload, {
      status: 206, headers: {
        'content-type': 'audio/mpeg',
        'content-range': 'bytes 64-67/128',
        'content-length': '4',
      },
    });
    const adapter = {
      verifyGrant: jest.fn().mockReturnValue(validGrant),
      fetchAuthorizedBytes: jest.fn().mockResolvedValue(upstream),
    };
    const rights = { decide: jest.fn().mockResolvedValue({
      allowed: true, previewOnly: false, expiresAt: null,
    }) };
    const controller = new OpenSubsonicAudioController(
      adapter as unknown as OpenSubsonicAdapter,
      rights as unknown as RightsDecisionService,
    );

    const sink = new PassThrough() as PassThrough & {
      status: jest.Mock; setHeader: jest.Mock; setTimeout: jest.Mock;
    };
    sink.status = jest.fn().mockReturnValue(sink);
    sink.setHeader = jest.fn().mockReturnValue(sink);
    sink.setTimeout = jest.fn().mockReturnValue(sink);
    const chunks: Buffer[] = [];
    sink.on('data', (chunk: Buffer) => chunks.push(Buffer.from(chunk)));
    await controller.stream('original-song', 'signed', 'bytes=64-67',
      { method: 'GET' } as never, sink as never);
    expect(Buffer.concat(chunks)).toEqual(payload);
    expect(sink.status).toHaveBeenCalledWith(206);
    expect(sink.setHeader).toHaveBeenCalledWith('Content-Range', 'bytes 64-67/128');
    expect(sink.setHeader).toHaveBeenCalledWith('Cache-Control', 'private, no-store');
    expect(adapter.fetchAuthorizedBytes).toHaveBeenCalledWith(
      'original-song', 'bytes=64-67');
  });

  it('rejects malformed Range headers without contacting an upstream server', async () => {
    const adapter = {
      verifyGrant: jest.fn().mockReturnValue(validGrant),
      fetchAuthorizedBytes: jest.fn(),
    };
    const controller = new OpenSubsonicAudioController(
      adapter as unknown as OpenSubsonicAdapter,
      { decide: jest.fn() } as unknown as RightsDecisionService,
    );
    await expect(controller.stream('original-song', 'signed', 'bytes=0-1,20-30',
      {} as never, {} as never)).rejects.toThrow('AUDIO_RANGE_INVALID');
    expect(adapter.fetchAuthorizedBytes).not.toHaveBeenCalled();
  });
});
