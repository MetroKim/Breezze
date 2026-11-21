import { ModerationService } from './moderation.service';

describe('ModerationService audit trail', () => {
  const tx = {
    contentReport: { updateMany: jest.fn() },
    adminAuditEvent: { create: jest.fn() },
  };
  const prisma = {
    contentReport: { create: jest.fn(), findMany: jest.fn() },
    $transaction: jest.fn((callback: (client: typeof tx) => unknown) => callback(tx)),
  };
  const service = new ModerationService(prisma as any);

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.$transaction.mockImplementation((callback: (client: typeof tx) => unknown) => callback(tx) as any);
  });

  it('records moderator, report and decision in the same transaction', async () => {
    tx.contentReport.updateMany.mockResolvedValue({ count: 1 });
    tx.adminAuditEvent.create.mockResolvedValue({});

    await expect(service.resolve('admin-1', 'report-1', 'actioned')).resolves.toEqual({
      resolved: true,
      resolution: 'actioned',
    });
    expect(tx.adminAuditEvent.create).toHaveBeenCalledWith({
      data: {
        actorId: 'admin-1',
        action: 'moderation.report.resolved',
        targetType: 'content_report',
        targetId: 'report-1',
        metadata: { resolution: 'actioned' },
      },
    });
  });

  it('does not audit a missing or already-resolved report', async () => {
    tx.contentReport.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.resolve('admin-1', 'report-1', 'dismissed')).rejects.toThrow(
      'REPORT_NOT_FOUND_OR_RESOLVED',
    );
    expect(tx.adminAuditEvent.create).not.toHaveBeenCalled();
  });
});
