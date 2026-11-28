import { shouldExposeSwaggerDocs } from './api-docs-policy';

describe('production API documentation isolation', () => {
  it('blocks Swagger on the public production API', () => {
    expect(shouldExposeSwaggerDocs('production')).toBe(false);
  });

  it('allows documentation only for an explicit development or test runtime', () => {
    expect(shouldExposeSwaggerDocs('development')).toBe(true);
    expect(shouldExposeSwaggerDocs('test')).toBe(true);
  });

  it('fails closed on missing or unknown runtime configuration', () => {
    expect(shouldExposeSwaggerDocs(undefined)).toBe(false);
    expect(shouldExposeSwaggerDocs('')).toBe(false);
    expect(shouldExposeSwaggerDocs('prod')).toBe(false);
    expect(shouldExposeSwaggerDocs('Production')).toBe(false);
  });
});
