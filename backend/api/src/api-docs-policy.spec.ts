import { shouldExposeSwaggerDocs } from './api-docs-policy';

describe('production API documentation isolation', () => {
  it('blocks Swagger on the public production API', () => {
    expect(shouldExposeSwaggerDocs('production')).toBe(false);
  });

  it('allows local and test-only documentation for contract development', () => {
    expect(shouldExposeSwaggerDocs('development')).toBe(true);
    expect(shouldExposeSwaggerDocs('test')).toBe(true);
    expect(shouldExposeSwaggerDocs(undefined)).toBe(true);
  });

  it('fails closed when production is explicitly selected', () => {
    expect(shouldExposeSwaggerDocs(process.env.NODE_ENV === 'production'
      ? 'production' : 'production')).toBe(false);
  });
});
