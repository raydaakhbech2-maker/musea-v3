import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'io.github.raydaakhbech2_maker.twa',
  appName: 'MUSEA',
  webDir: 'www',
  backgroundColor: '#f6f5fb',
  android: {
    allowMixedContent: false,
    captureInput: true
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 0,
      launchAutoHide: true,
      backgroundColor: '#f6f5fb'
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#f6f5fb'
    }
  }
};

export default config;
