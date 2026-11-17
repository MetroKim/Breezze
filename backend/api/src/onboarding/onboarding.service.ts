import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

@Injectable()
export class OnboardingService {
  constructor(private readonly prisma: PrismaService) {}

  async savePreferences(
    userId: string,
    dto: {
      country?: string;
      language?: string;
      genres?: string[];
      favoriteArtists?: string[];
    },
  ) {
    return this.prisma.userPreference.upsert({
      where: { userId },
      create: {
        userId,
        country: dto.country,
        language: dto.language,
        genres: dto.genres ?? [],
        favoriteArtists: dto.favoriteArtists ?? [],
      },
      update: {
        country: dto.country,
        language: dto.language,
        genres: dto.genres ?? [],
        favoriteArtists: dto.favoriteArtists ?? [],
      },
    });
  }

  async getPreferences(userId: string) {
    return this.prisma.userPreference.findUnique({
      where: { userId },
    });
  }
}
