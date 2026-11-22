import { NotFoundException, UnauthorizedException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { UsersService } from './users.service';

jest.mock('argon2', () => ({ verify: jest.fn() }));

describe('UsersService account security and preferences', () => {
  const tx = {
    user: {
      findUnique: jest.fn(),
      update: jest.fn(),
    },
    userPreference: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
    },
  };
  const prisma = {
    user: {
      findUnique: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    userPreference: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
    },
    $transaction: jest.fn(),
  };
  const service = new UsersService(prisma as any);

  beforeEach(() => {
    jest.clearAllMocks();
    (argon2.verify as jest.Mock).mockResolvedValue(true);
    prisma.$transaction.mockImplementation((callback: (client: typeof tx) => unknown) => callback(tx));
    tx.user.findUnique.mockResolvedValue({ id: 'user-a', displayName: 'Metro' });
    tx.userPreference.findUnique.mockResolvedValue(null);
    tx.userPreference.upsert.mockImplementation(({ create, update }: any) =>
      Promise.resolve({ ...create, ...update }),
    );
  });

  it('requires a valid password before deleting the account', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-a',
      passwordHash: 'argon-hash',
    });
    prisma.user.delete.mockResolvedValue({ id: 'user-a' });

    await expect(service.delete('user-a', 'current-password')).resolves.toEqual({
      deleted: true,
    });
    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { id: 'user-a' },
      select: { id: true, passwordHash: true },
    });
    expect(argon2.verify).toHaveBeenCalledWith('argon-hash', 'current-password');
    expect(prisma.user.delete).toHaveBeenCalledWith({ where: { id: 'user-a' } });
  });

  it('does not delete an account when password reauthentication fails', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-a',
      passwordHash: 'argon-hash',
    });
    (argon2.verify as jest.Mock).mockResolvedValue(false);

    await expect(service.delete('user-a', 'wrong-password'))
      .rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.delete).not.toHaveBeenCalled();
  });

  it('does not delete an account that no longer exists', async () => {
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.delete('missing-user', 'password'))
      .rejects.toBeInstanceOf(NotFoundException);
    expect(argon2.verify).not.toHaveBeenCalled();
    expect(prisma.user.delete).not.toHaveBeenCalled();
  });

  it('stores a normalized territory and listener preferences atomically', async () => {
    tx.userPreference.upsert.mockResolvedValue({
      country: 'TZ',
      language: 'sw',
      genres: ['bongo flava', 'afrobeats'],
      favoriteArtists: ['Artist One'],
    });

    await expect(service.update('user-a', {
      country: 'tz',
      language: ' sw ',
      genres: ['bongo flava', 'afrobeats'],
      favoriteArtists: [' Artist One '],
    })).resolves.toMatchObject({
      id: 'user-a',
      preference: {
        country: 'TZ',
        language: 'sw',
        genres: ['bongo flava', 'afrobeats'],
        favoriteArtists: ['Artist One'],
      },
    });

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.userPreference.upsert).toHaveBeenCalledWith({
      where: { userId: 'user-a' },
      create: {
        userId: 'user-a',
        country: 'TZ',
        language: 'sw',
        genres: ['bongo flava', 'afrobeats'],
        favoriteArtists: ['Artist One'],
      },
      update: {
        country: 'TZ',
        language: 'sw',
        genres: ['bongo flava', 'afrobeats'],
        favoriteArtists: ['Artist One'],
      },
    });
  });

  it('allows a listener to clear the territory and preference lists', async () => {
    tx.userPreference.upsert.mockResolvedValue({
      country: null,
      language: null,
      genres: [],
      favoriteArtists: [],
    });

    await expect(service.update('user-a', {
      country: null,
      language: null,
      genres: null,
      favoriteArtists: null,
    })).resolves.toMatchObject({
      preference: { country: null, language: null, genres: [], favoriteArtists: [] },
    });
  });

  it('does not write a preference row for a display-name-only update', async () => {
    tx.user.update.mockResolvedValue({ id: 'user-a', displayName: 'New name' });

    await expect(service.update('user-a', { displayName: 'New name' }))
      .resolves.toMatchObject({ id: 'user-a', displayName: 'New name', preference: null });
    expect(tx.userPreference.upsert).not.toHaveBeenCalled();
  });
});
