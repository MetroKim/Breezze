import { Injectable, NotAcceptableException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RightsDecisionService } from '../rights/rights-decision.service';
import { MediaSigner } from './media-signer.service';

@Injectable()
export class PlaybackResolveService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rights: RightsDecisionService,
    private readonly signer: MediaSigner,
  ) {}

  async resolve(
    userId: string | null,
    dto: { trackId: string; territory: string; requestedQuality?: string },
  ) {
    const decision = await this.rights.decide({
      userId,
      trackId: dto.trackId,
      authorization_placeholder
  }
}
