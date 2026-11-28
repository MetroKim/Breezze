/** Expose developer endpoints only in non-production environments. */
export function shouldExposeSwaggerDocs(environment: string | undefined): boolean {
  // Edge-secret authentication protects the origin, but the public API
  // Worker can still forward /api/docs. Never advertise backend contracts
  // from the production listener-facing origin.
  return environment === 'development' || environment === 'test';
}
