# Lefty-Wefty

Stock and sales, in order.

Lefty-Wefty helps small businesses track products, stock and sales. The identity is friendly, straightforward and easy to recognise without competing with the work on screen.

## Name and phrase

Write the name as **Lefty-Wefty**, with both initials capitalised and a hyphen. Use **Stock and sales, in order.** as the main phrase on the public introduction, share cards and selected brand surfaces. It does not need to appear on every app screen.

Use the description “Track products, stock and sales for your small business” when a short functional description is more useful than the phrase.

## The mark

The symbol is a small shop with a gently tilted canopy. Its rounded silhouette gives the name a little character while remaining readable in a browser tab. The horizontal logo is the usual choice for headers, footers, documentation and email.

Use the supplied SVGs for the website. The wordmark is outlined, so it does not depend on a font loading. PNG versions are included for email and other places that need raster images. The simplified, padded icon files are intended for browser tabs and home screens.

- `logos/logo-horizontal.svg`: default forest-green header/footer logo.
- `logos/logo-with-tagline.svg`: logo and phrase for larger brand surfaces.
- `logos/logo-stacked.svg`: centred compositions with enough vertical space.
- `logos/wordmark.svg`: name without the symbol.
- `logos/mark.svg`: symbol without the name.
- `logos/*-reversed.svg`: white artwork for an existing forest-green or other suitable dark background.
- `logos/*-ink.svg`: one-colour ink artwork for print or other neutral uses.
- `logos/email-logo.png`: transparent PNG for a styled email, displayed at 165 × 32 CSS pixels or a similar proportional size.

Keep at least one canopy section of clear space around the artwork. Keep its proportions. A horizontal logo should normally be at least 165 CSS pixels wide; at smaller sizes, use the symbol with readable adjacent text. The symbol normally starts at 24 CSS pixels; the optical favicon exports handle smaller sizes.

Do not stretch, rotate, add shadows, recolour individual letters or put a new gradient behind the mark. Do not substitute the product mark for a business's uploaded logo. A business retains its own name and identity.

The reversed logo is a supplied asset variant, not a request to add dark navigation or dark application panels.

## Colours

| Token | Colour | Use |
| --- | --- | --- |
| Forest | `#245C43` | Brand identity, selected navigation, success feedback |
| Ink | `#203A32` | Headings, primary text |
| Supporting text | `#53675C` | Secondary labels and explanations |
| Canvas | `#F4F7F2` | App background |
| Surface | `#FFFFFF` | Forms, menus, tables and panels |
| Border | `#DCE5DC` | Quiet structural dividers |
| Soft green | `#E7F0E9` | Selected and success surfaces |
| Action blue | `#245FD6` | Primary positive actions |
| Action hover | `#1C4DAC` | Blue hover/pressed treatment |
| Destructive red | `#B52F36` | Destructive actions and logout |
| Soft red | `#FBEEF0` | Error/destructive supporting surfaces |
| Warning amber | `#8A580E` | Low-stock or warning text |
| Soft amber | `#FBF3E3` | Warning background |

Use white text on the blue and red filled buttons. Use ink or the appropriate darker semantic colour on pale backgrounds. The border colour is for structure; an input or control may need a stronger border for clear identification. Do not use pale fills as small text colours. Pair status colour with words, not colour alone.

## Typography and hierarchy

Rubik is the supplied UI family. Use the included regular 400 and bold 700 web fonts with a system sans-serif fallback. Keep the OFL license and notices with the files. The artwork's wordmark has already been converted to paths.

Use the existing application's spacing and layout as a base. A useful working hierarchy is:

| Element | Desktop | Narrow screens |
| --- | --- | --- |
| Page heading | 30–32 px / 700 | 26–28 px / 700 |
| Panel heading | 17–18 px / 700 | 17–18 px / 700 |
| Body and form text | 15–16 px / 400 | 16 px for editable fields |
| Labels and supporting text | 13–14 px | 13–14 px |
| Small nonessential metadata | At least 12 px | At least 12 px |

Use ink for page headings, full opacity and a comfortable line height. “Overview” must remain immediately readable on its actual background. Do not turn the only page heading into a faint uppercase eyebrow.

Use tabular figures for aligned prices, quantities and totals. Right-align numeric table columns. Keep important currency amounts readable when values are large.

## Interface language

Be direct, practical and approachable. Use familiar words. Keep help short and place it beside the relevant decision. Avoid forced slang, padded introductions, inflated claims and generic marketing slogans.

Prefer “Add product,” “Record sale,” “Add stock,” “Low stock,” “Product code” and “Stock history.” State consequences plainly: “Cancelling this sale returns its items to stock.” A normal Back or Cancel-editing control stays neutral.

A business name is the display name entered by its owner. Preserve its internal spaces, spelling, punctuation and capitalisation. Do not render a slug, email fragment or lowercased identifier in its place.

## Web and social assets

| File | Purpose |
| --- | --- |
| `icons/favicon.svg` | Scalable browser icon |
| `icons/favicon.ico` | Multi-size 16/32/48 fallback |
| `icons/favicon-16.png`, `favicon-32.png`, `favicon-48.png`, `favicon-96.png` | Raster browser/search icons |
| `icons/apple-touch-icon.png` | 180 × 180 home-screen icon |
| `icons/icon-192.png`, `icon-512.png` | General application icons |
| `icons/icon-maskable-192.png`, `icon-maskable-512.png` | Full-bleed icons with safe padding |
| `icons/safari-pinned-tab.svg` | Single-colour pinned-tab silhouette |
| `social/og-image.png` | 1200 × 630 link preview and large social card |
| `social/github-social.png` | 1280 × 640 repository social image |
| `social/social-square.png` | 1080 × 1080 square social graphic |
| `site.webmanifest` | Browser identity and icon configuration |

SVG sources are included for the social cards. The manifest uses browser display mode and does not imply offline capability, background sync or an installed-app feature. No service worker is included.

The default share image is brand artwork. It contains no business account, stock, sales or customer information.
