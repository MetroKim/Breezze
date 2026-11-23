import { Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';

export interface UpdateUserProfile {
  displayName?: string;
  country?: string | null;
  language?: string | null;
  genres?: string[] | null;
  favoriteArtists?: string[] | null;
}

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async profile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        displayName: true,
        createdAt: true,
        preference: {
          select: {
            country: true,
            language: true,
            genres: true,
            favoriteArtists: true,
          },
        },
      },
    });
    if (!user) throw new NotFoundException('USER_NOT_FOUND');
    return user;
  }

  async update(userId: string, body: UpdateUserProfile) {
    return this.prisma.$transaction(async (tx) => {
      let user = await tx.user.findUnique({
        where: { id: userId },
        select: { id: true, displayName: true },
      });
      if (!user) throw new NotFoundException('USER_NOT_FOUND');

      if (body.displayName !== undefined) {
        user = await tx.user.update({
          where: { id: userId },
          data: { displayName: body.displayName },
          select: { id: true, displayName: true },
        });
      }

      const preferenceChanged =
        body.country !== undefined ||
        body.language !== undefined ||
        body.genres !== undefined ||
        body.favoriteArtists !== undefined;

      let preference = await tx.userPreference.findUnique({
        where: { userId },
      });

      if (preferenceChanged) {
        const data: {
          country?: string | null;
          language?: string | null;
          genres?: string[];
          favoriteArtists?: string[];
        } = {};
        if (body.country !== undefined) {
          data.country = body.country === null ? null : body.country.trim().toUpperCase();
        }
        if (body.language !== undefined) {
          data.language = body.language === null ? null : body.language.trim();
        }
        if (body.genres !== undefined) {
          data.genres = (body.genres ?? []).map((item) => item.trim()).filter(Boolean);
        }
        if (body.favoriteArtists !== undefined) {
          data.favoriteArtists = (body.favoriteArtists ?? [])
            .map((item) => item.trim())
            .filter(Boolean);
        }

        preference = await tx.userPreference.upsert({
          where: { userId },
          create: { userId, ...data },
          update: data,
        });
      }

      return {
        id: user.id,
        displayName: user.displayName,
        preference: preference
          ? {
              country: preference.country,
              language: preference.language,
              genres: preference.genres,
              favoriteArtists: preference.favoriteArtists,
            }
          : null,
      };
    });
  }

  async delete(userId: string, password: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, passwordHash: true },
    });
    if (!user) throw new NotFoundException('USER_NOT_FOUND');

    const passwordValid = await argon2.verify(user.passwordHash, password).catch(() => false);
    if (!passwordValid) throw new UnauthorizedException('INVALID_CREDENTIALS');

    await this.prisma.user.delete({ where: { id: userId } });
    return { deleted: true };
  }
}
