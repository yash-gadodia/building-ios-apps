# React Native fidelity (hard-won)

Porting a web/design prototype to RN. The traps that cause real visual bugs, in priority order:

- **`lineHeight` is PIXELS, not a CSS multiplier.** `lineHeight: 1.5` clips text to a ~1.5px sliver (invisible). Use `lineHeight: fontSize * ~1.4` (14 → 20, button 16.5 → 20).
- **Every `<Text>` needs its own explicit `color`.** RN does NOT inherit color from a parent `<View>` (default black). White-on-dark renders invisible until each Text gets `color`.
- **Reuse the atom library** (Button, Press, Card, Icon, Text wrappers, design tokens). Do NOT reimplement per screen. Tokens (colors/space/radius/shadow + typography) live in `src/design` — no hardcoded hex duplicating a token.
- **Web→RN swaps:** gradient text → MaskedView (not `-webkit-background-clip`); frosted blur → expo-blur; CSS `linear-gradient(...)`/`radial-gradient(...)` **strings** are NOT valid RN `backgroundColor`/`color` (render nothing) → use expo-linear-gradient; CSS keyframes → Reanimated; SVG → react-native-svg; `pointerEvents` is a PROP, not a style key. `inset` and `display:'flex'` ARE valid in RN 0.71+ — don't "fix" them.
- **Absolute overlays (header bars, toasts, FABs) need an opaque or blurred backdrop** spanning the safe-area inset too, or scrolling content bleeds through them.
- **No fake phone frame / status bar** from the prototype — use real safe-area insets (`react-native-safe-area-context`).
- **Floating tab bar**: an absolute overlay sibling to `<Tabs>` (default bar hidden), full-width via `Dimensions` — NOT react-navigation's `tabBar` wrapper. Tab screens need bottom padding so content clears the pill.
- **TypeScript**: no `any` / `@ts-ignore`. Avoid defensive try/catch around `Animated.createAnimatedComponent`.

## Reload caveat
Component edits hot-reload via Fast Refresh, but **route `_layout`/structural changes need a full reload** and the bundle can be cached — verify a layout change with `npx expo export` and/or a manual reload. Adding a **native-module dep requires `npx expo run:ios`** (rebuild), not just a Metro restart.
