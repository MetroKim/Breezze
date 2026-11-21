import { AdminService } from './admin.service';

describe('AdminService role management', () => {
  const prisma = {
    user: { findUnique: jest.fn(), update: jest.fn() },
    track: { count: jest.fn() }, album: { count: jest.fn() }, artist: { count: jest.fn() },
    playlist: { count: jest.fn() }, contentTakedownCase: { count: jest.fn() },
  };
  const service = new AdminService(prisma as any);

  beforeEach(() => jest.clearAllMocks());

  it('persists role assignment instead of returning a success-shaped placeholder', async () => {
    prisma.user.findUnique.mockResolvedValue({ id: 'target-user' });
    prisma.user.update.mockResolvedValue({ id: 'target-user', role: 'moderator' });
    await expect(service.createUserRole('target-user', 'moderator')).resolves.toEqual({
      id: 'target-user', role: 'moderator',
    });
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'target-user' }, data: { role: 'moderator' },
      select: { id: true, role: true },
    });
  });
});
