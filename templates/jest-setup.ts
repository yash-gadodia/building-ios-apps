// Global jest setup — every native module a screen might import is mocked here
// so components render in jest. New screen throws on a native import? Add it here;
// never disable the test. Referenced by jest config: setupFilesAfterEnv.
import '@testing-library/react-native/matchers';

// Default public env so the supabase client constructs in tests.
process.env.EXPO_PUBLIC_SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL || 'http://127.0.0.1:54321';
process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY || 'test-anon-key';

// reanimated — official mock + the helpers screens commonly use.
jest.mock('react-native-reanimated', () => {
  const Reanimated = require('react-native-reanimated/mock');
  Reanimated.default.call = () => {};
  return Reanimated;
});

// expo-router — router/Link/Stack/Tabs as inert stand-ins.
jest.mock('expo-router', () => ({
  useRouter: () => ({ push: jest.fn(), replace: jest.fn(), back: jest.fn(), canGoBack: () => true }),
  useLocalSearchParams: () => ({}),
  Link: ({ children }: { children: React.ReactNode }) => children,
  Redirect: () => null,
  Stack: Object.assign(() => null, { Screen: () => null }),
  Tabs: Object.assign(() => null, { Screen: () => null }),
}));

// expo-blur — render the frosted BlurView as a plain View in jest.
jest.mock('expo-blur', () => {
  const { View } = require('react-native');
  return { BlurView: View };
});

// safe-area-context — provider passthrough + fixed insets.
jest.mock('react-native-safe-area-context', () => {
  const { View } = require('react-native');
  return {
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => children,
    SafeAreaView: View,
    useSafeAreaInsets: () => ({ top: 47, bottom: 34, left: 0, right: 0 }),
  };
});

// async-storage — in-memory mock.
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);

// supabase-js — chainable from()/rpc()/channel()/auth returning empty, so hooks
// that query on mount don't throw. Override per-test where you need real data.
jest.mock('@supabase/supabase-js', () => {
  const chain: any = {
    select: () => chain, insert: () => chain, update: () => chain, delete: () => chain,
    eq: () => chain, or: () => chain, order: () => chain, limit: () => chain,
    single: () => Promise.resolve({ data: null, error: null }),
    maybeSingle: () => Promise.resolve({ data: null, error: null }),
    then: (r: any) => r({ data: [], error: null }),
  };
  const channel = { on: () => channel, subscribe: () => channel };
  return {
    createClient: () => ({
      from: () => chain,
      rpc: () => Promise.resolve({ data: null, error: null }),
      channel: () => channel,
      removeChannel: () => {},
      auth: {
        getUser: () => Promise.resolve({ data: { user: null }, error: null }),
        getSession: () => Promise.resolve({ data: { session: null }, error: null }),
        onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
        signOut: () => Promise.resolve({ error: null }),
      },
    }),
  };
});
