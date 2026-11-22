import { PrismaService } from '../prisma.service';
import { OnboardingService } from './onboarding.service';

describe('OnboardingService', () => {
  const prisma = { userPreference: { upsert: jest.fn(), findUnique: jest.fn() } };
  let service: OnboardingService;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.userPreference.upsert.mockResolvedValue({ userId: 'user-1' });
    service = new OnboardingService(prisma as unknown as PrismaService);
  });

  it('normalizes and stores initial onboarding preferences', async () => {
    await service.savePreferences('user-1', {
      country: 'tz',
      language: ' en ',
      genres: [' Afrobeats ', 'Amapiano', ''],
      favoriteArtists: [' Artist A ', 'Artist B'],
    });

    expect(prisma.userPreference.upsert).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
      create: {
        userId: 'user-1',
        country: 'TZ',
        language: 'en',
        genres: ['Afrobeats', 'Amapiano'],
        favoriteArtists: ['Artist A', 'Artist B'],
      },
      update: {
        country: 'TZ',
        language: 'en',
        genres: ['Afrobeats', 'Amapiano'],
        favoriteArtists: ['Artist A', 'Artist B'],
      },
    });
  });

  it('preserves omitted preference fields during partial updates', async () => {
    await service.savePreferences('user-1', { country: 'tz' });

    expect(prisma.userPreference.upsert).toHaveBeenCalledWith({
      where: { userId: 'user-1' },
      create: {
        userId: 'user-1',
        country: 'TZ',
        language: undefined,
        genres: [],
        favoriteArtists: [],
      },
      update: { country: 'TZ' },
    });
  });

  it('returns a not-found signal when preferences do not exist', async () => {
    prisma.userPreference.findUnique.mockResolvedValue(null);
    await expect(service.getPreferences('user-1')).rejects.toThrow('PREFERENCES_NOT_FOUND');
  });
});
