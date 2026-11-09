import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.wavoworld.app',
  appName: 'WAVO',
  webDir: 'www',
  bundledWebRuntime: false,
  backgroundColor: '#080b0e',
  android: {
    allowMixedContent: false
  },
  ios: {
    contentInset: 'automatic'
  }
};

export default config;
