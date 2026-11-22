import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

export interface NewSupportRequest {
  category: string;
  subject: string;
  message: string;
}

@Injectable()
export class SupportService {
  constructor(private readonly prisma: PrismaService) {}

  create(userId: string, input: NewSupportRequest) {
    return this.prisma.supportRequest.create({
      data: {
        userId,
        category: input.category,
        subject: input.subject.trim(),
        message: input.message.trim(),
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
  }

  list(userId: string) {
    return this.prisma.supportRequest.findMany({
      where: { userId },
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
  }
}
