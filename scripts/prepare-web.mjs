import { mkdir, copyFile, access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { resolve } from 'node:path';

const root = process.cwd();
const output = resolve(root, 'www');
const required = [
  'index.html',
  'privacy.html',
  'delete-account.html',
  'community-guidelines.html',
  'manifest.webmanifest',
  'sw.js',
  'icon-192.png',
  'icon-512.png'
];

await mkdir(output, { recursive: true });
for (const file of required) {
  const source = resolve(root, file);
  await access(source, constants.R_OK);
  await copyFile(source, resolve(output, file));
}
console.log(`Prepared ${required.length} MUSEA web assets in www/.`);
