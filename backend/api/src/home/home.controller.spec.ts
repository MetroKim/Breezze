import { GoneException } from '@nestjs/common';
import { HomeController } from './home.controller';

describe('HomeController qualified play integrity', () => {
  it('rejects client-reported qualified plays in favor of server playback sessions', () => {
    const home = { feed: jest.fn(), recordRecent: jest.fn(), recordPlay: jest.fn() };
    const controller = new HomeController(home as any);

    expect(() => controller.recordPlay()).toThrow(GoneException);
    expect(home.recordPlay).not.toHaveBeenCalled();
  });
});
