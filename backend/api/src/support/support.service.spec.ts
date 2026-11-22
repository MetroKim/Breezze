import { PrismaService } from '../prisma.service';
import { SupportService } from './support.service';

describe('SupportService', () => {
  const prisma = {
    supportRequest: {
      create: jest.fn(),
      findMany: jest.fn(),
    },
  };
  const service = new SupportService(prisma as unknown as PrismaService);

  beforeEach(() => jest.clearAllMocks());

  it('creates a request under the authenticated user and trims user input', async () => {
    prisma.supportRequest.create.mockResolvedValue({ id: 'request-1' });

    await service.create('user-a', {
      category: 'playback',
      subject: '  Playback issue  ',
      message: '  The player stops after a few seconds.  ',
    });

    expect(prisma.supportRequest.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-a',
        category: 'playback',
        subject: 'Playback issue',
        message: 'The player stops after a few seconds.',
      },
      select: {
        id: true,
        category: true,
        subject: true,
        message: true,
        status: true,
        createdAt: true,
      },
    });
  });

  it('lists only the authenticated user requests', async () => {
    prisma.supportRequest.findMany.mockResolvedValue([]);

    await service.list('user-b');

    expect(prisma.supportRequest.findMany).toHaveBeenCalledWith({
      where: { userId: 'user-b' },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: {
        id: true,
        category: true,
        subject: true,
        message: true,
        status: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  });
});
