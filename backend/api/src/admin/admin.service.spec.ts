import { AdminService } from './admin.service';

describe('AdminService privileged audit trail', () => {
  const tx = {
    user: { findUnique: jest.fn(), update: jest.fn() },
    contentTakedownCase: { updateMany: jest.fn() },
    adminAuditEvent: { create: jest.fn(), findMany: jest.fn() },
  };
  const prisma = {
    user: { count: jest.fn() },
    track: { count: jest.fn() },
    album: { count: jest.fn() },
    artist: { count: jest.fn() },
    playlist: { count: jest.fn() },
    contentTakedownCase: { count: jest.fn(), findMany: jest.fn() },
    adminAuditEvent: { findMany: jest.fn() },
    $transaction: jest.fn((callback: (client: typeof tx) => unknown) => callback(tx)),
  };
  const service = new AdminService(prisma as any);

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.$transaction.mockImplementation((callback: (client: typeof tx) => unknown) => callback(tx) as any);
  });

  it('updates a role and records actor plus before/after values in the same transaction', async () => {
    tx.user.findUnique.mockResolvedValue({ id: 'target-user', role: 'user' });
    tx.user.update.mockResolvedValue({ id: 'target-user', role: 'moderator' });
    tx.adminAuditEvent.create.mockResolvedValue({});

    await expect(service.createUserRole('admin-user', 'target-user', 'moderator')).resolves.toEqual({
      id: 'target-user',
      role: 'moderator',
    });
    expect(tx.user.update).toHaveBeenCalledWith({
      where: { id: 'target-user' },
      data: { role: 'moderator' },
      select: { id: true, role: true },
    });
    expect(tx.adminAuditEvent.create).toHaveBeenCalledWith({
      data: {
        actorId: 'admin-user',
        action: 'user.role.updated',
        targetType: 'user',
        targetId: 'target-user',
        metadata: { previousRole: 'user', newRole: 'moderator' },
      },
    });
  });

  it('does not mutate or audit a missing target user', async () => {
    tx.user.findUnique.mockResolvedValue(null);
    await expect(service.createUserRole('admin-user', 'missing-user', 'admin')).rejects.toThrow('USER_NOT_FOUND');
    expect(tx.user.update).not.toHaveBeenCalled();
    expect(tx.adminAuditEvent.create).not.toHaveBeenCalled();
  });

  it('resolves a takedown and records the acting administrator transactionally', async () => {
    tx.contentTakedownCase.updateMany.mockResolvedValue({ count: 1 });
    tx.adminAuditEvent.create.mockResolvedValue({});
    await expect(service.resolveTakedown('admin-user', 'case-1')).resolves.toEqual({ resolved: true });
    expect(tx.contentTakedownCase.updateMany).toHaveBeenCalledWith({
      where: { id: 'case-1', status: 'active' },
      data: { status: 'resolved' },
    });
    expect(tx.adminAuditEvent.create).toHaveBeenCalledWith({
      data: {
        actorId: 'admin-user',
        action: 'takedown.resolved',
        targetType: 'content_takedown_case',
        targetId: 'case-1',
        metadata: { newStatus: 'resolved' },
      },
    });
  });

  it('does not audit a takedown that was already resolved or missing', async () => {
    tx.contentTakedownCase.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.resolveTakedown('admin-user', 'case-1')).rejects.toThrow('CASE_NOT_FOUND_OR_RESOLVED');
    expect(tx.adminAuditEvent.create).not.toHaveBeenCalled();
  });

  it('returns a bounded newest-first audit feed', async () => {
    tx.adminAuditEvent.findMany.mockResolvedValue([]);
    await service.listAuditEvents();
    expect(tx.adminAuditEvent.findMany).toHaveBeenCalledWith({
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  });
});
