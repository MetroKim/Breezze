import { Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';

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
      },
    });
    if (!user) throw new NotFoundException('USER_NOT_FOUND');
    return user;
  }

  async update(userId: string, body: { displayName?: string }) {
    const data: { displayName?: string } = {};
    const name = body['displayName'];
    if (typeof name === 'string') {
      data.displayName = name;
    }
    const updated = await this.prisma.user.update({
      where: { id: userId },
      data,
    });
    return { id: updated.id, displayName: updated.displayName };
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
