// Isolated, nonproduction InnerTube experiment; never loaded by main API.
// All HTTP handling and safety logic is independently tested in handler.mjs.
import { createServer } from 'node:http';
import { Innertube } from 'youtubei.js';
import { createExperimentHandler } from './handler.mjs';

const port = Number(process.env.PORT || '8181');
let active;
let pending;

async function getClient() {
  if (active) return active;
  if (!pending) {
    pending = Innertube.create({ lang: 'en', location: 'US' })
      .then(client => (active = client))
      .finally(() => { pending = undefined; });
  }
  return pending;
}

const server = createServer(createExperimentHandler({ createClient: getClient }));
server.headersTimeout = 15000;
server.requestTimeout = 30000;
server.listen(port, '0.0.0.0', () => {
  console.log('Breezze isolated, nonproduction audio experiment listening');
});
