import { Injectable, NotFoundException } from '@nestjs/common';
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
    const data: {
      country?: string;
      language?: string;
      genres?: string[];
      favoriteArtists?: string[];
    } = {};

    if (dto.country !== undefined) data.country = dto.country.trim().toUpperCase();
    if (dto.language !== undefined) data.language = dto.language.trim();
    if (dto.genres !== undefined) {
      data.genres = dto.genres.map((item) => item.trim()).filter(Boolean);
    }
    if (dto.favoriteArtists !== undefined) {
      data.favoriteArtists = dto.favoriteArtists.map((item) => item.trim()).filter(Boolean);
    }

    return this.prisma.userPreference.upsert({
      where: { userId },
      create: {
        userId,
        country: data.country,
        language: data.language,
        genres: data.genres ?? [],
        favoriteArtists: data.favoriteArtists ?? [],
      },
      // PATCH-like behavior: omitted fields are preserved rather than reset.
      update: data,
    });
  }

  async getPreferences(userId: string) {
    const preferences = await this.prisma.userPreference.findUnique({
      where: { userId },
    });
    // No saved preferences = first-time user. 404 is the explicit
    // signal the app's auth gate uses to decide whether to show
    // onboarding — a 200-null would be ambiguous.
    if (!preferences) throw new NotFoundException('PREFERENCES_NOT_FOUND');
    return preferences;
  }
}
