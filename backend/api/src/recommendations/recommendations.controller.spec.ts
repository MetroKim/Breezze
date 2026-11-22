import { RecommendationsService } from './recommendations.service';
import { RecommendationsController } from './recommendations.controller';

describe('RecommendationsController', () => {
  it('passes the trusted edge country to rights-filtered recommendations', async () => {
    const recs = { forUser: jest.fn().mockResolvedValue([]) };
    const controller = new RecommendationsController(
      recs as unknown as RecommendationsService,
    );

    await expect(controller.forUser('user-1', 'TZ')).resolves.toEqual([]);
    expect(recs.forUser).toHaveBeenCalledWith('user-1', 'TZ');
  });

  it('does not substitute a client profile country when the edge country is absent', async () => {
    const recs = { forUser: jest.fn().mockResolvedValue([]) };
    const controller = new RecommendationsController(
      recs as unknown as RecommendationsService,
    );

    await controller.forUser('user-1', undefined);
    expect(recs.forUser).toHaveBeenCalledWith('user-1', undefined);
  });
});
