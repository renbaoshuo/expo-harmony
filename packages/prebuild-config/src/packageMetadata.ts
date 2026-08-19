import fs from 'node:fs';
import path from 'node:path';

const PackageMetadata = JSON.parse(
  fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8')
) as Readonly<{ name: string; version: string }>;

export { PackageMetadata };
