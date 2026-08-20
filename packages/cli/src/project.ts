import fs from 'node:fs';
import path from 'node:path';

import { HarmonyCliError } from './errors';

function resolveProject(start = process.cwd()) {
  let current = path.resolve(start);

  if (fs.existsSync(current) && fs.statSync(current).isFile()) current = path.dirname(current);

  while (true) {
    if (fs.existsSync(path.join(current, 'package.json'))) return fs.realpathSync(current);
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }

  throw new HarmonyCliError('ERR_HARMONY_CONFIG_INVALID', `No package.json was found from ${start}.`, { operation: 'resolve-project' });
}

export { resolveProject };
