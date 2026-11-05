import { readFile, writeFile } from 'node:fs/promises';

const file = 'android/app/build.gradle';
let gradle = await readFile(file, 'utf8');
if (!gradle.includes('signingConfigs')) {
  const androidBlock = /android\s*\{/;
  if (!androidBlock.test(gradle)) throw new Error('Could not locate android { } in app/build.gradle');
  const signing = `
    signingConfigs {
        release {
            def ksPath = System.getenv('MUSEA_KEYSTORE_PATH')
            if (ksPath) {
                storeFile file(ksPath)
                storePassword System.getenv('MUSEA_KEYSTORE_PASSWORD')
                keyAlias System.getenv('MUSEA_KEY_ALIAS')
                keyPassword System.getenv('MUSEA_KEY_PASSWORD')
            }
        }
    }
`;
  gradle = gradle.replace(androidBlock, match => match + signing);
}
const releaseBlock = /release\s*\{/;
if (!releaseBlock.test(gradle)) throw new Error('Could not locate release buildType');
if (!gradle.includes('signingConfig signingConfigs.release')) {
  gradle = gradle.replace(releaseBlock, match => match + '\n            if (System.getenv("MUSEA_KEYSTORE_PATH")) { signingConfig signingConfigs.release }');
}
await writeFile(file, gradle);
console.log('Android release signing configuration prepared.');
