# Sahlha logo assets

Drop the brand PNGs here (the robot logo from chat):

1. `sahlha_logo.png` — full lockup (robot + "Sahlha" wordmark), transparent
   background, ~1024px wide. Used in-app by `SahlhaFullLogo`
   (splash, login). Falls back to the SVG mark if missing.

2. `sahlha_icon.png` — icon-only (robot head, NO wordmark), 1024x1024 PNG
   with transparent background + padding (~15% safe area). Used by
   `flutter_launcher_icons` to generate Android / iOS / Web icons.

> The preview in chat has a black background. Re-export with a transparent
> background before saving — otherwise the launcher icon will have a black
> square baked in. For the launcher, crop out the "Sahlha" text; wordmarks
> are unreadable at 48dp.

Existing vector fallback: `sahlha_mark.svg` (small inline uses).

After adding both PNGs, run from `mobile/`:

```sh
dart run flutter_launcher_icons
```
