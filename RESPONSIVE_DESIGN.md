# Lumyn Responsive Design System

## Overview

Lumyn automatically switches between two design systems based on screen width:

- **Desktop (≥720px)**: Resend Dark — Inspired by Vercel/Resend design language
- **Mobile (<720px)**: Liquid Glass — Modern glassmorphism UI

## Architecture

### Theme Colors (in `lib/widgets/ui_core.dart`)

#### Desktop (Resend Dark)
```dart
LumynTheme.black       = #000000 // Pure black background
LumynTheme.surface     = #0A0A0A // Subtle surface layer
LumynTheme.border      = #1A1A1A // Thin borders
LumynTheme.borderLoud  = #333333 // Prominent borders
LumynTheme.accent      = #9281F7 // Resend Purple
LumynTheme.textMuted   = #888888 // Low contrast text
LumynTheme.text        = #EDEDEDED // Primary text
```

#### Mobile (Liquid Glass)
```dart
LumynTheme.glassBase   = White @ 8% opacity    // Base glass color
LumynTheme.glassBorder = White @ 16% opacity   // Glass borders
```

#### Shared Brand Colors
```dart
LumynTheme.purple      = #B026FF // Primary action
LumynTheme.blue        = #007AFF // Secondary
LumynTheme.cyan        = #00C7FF // Accent
LumynTheme.green       = #34C759 // Success
```

## Responsive Components

### AetherCard

Adaptive container that changes style based on screen size:

```dart
AetherCard(
  padding: const EdgeInsets.all(16),
  child: Text('Responsive content'),
)
```

**Desktop rendering:**
- Solid color background (`#0A0A0A`)
- 1px border with `#1A1A1A` color
- 12px border radius

**Mobile rendering:**
- BackdropFilter for frosted glass effect (12px blur)
- Semi-transparent white border (`white @ 10%`)
- 24px border radius

### VercelInput

Smart input field with platform-specific styling:

```dart
VercelInput(
  controller: controller,
  hintText: 'Enter text...',
  obscure: false,
)
```

**Desktop:**
- Black background (`#000000`)
- 6px border radius
- Sharp focus states

**Mobile:**
- Semi-transparent background (`white @ 10%`)
- 12px border radius
- Glass effect on focus

### ShineButton

Adaptive primary button with loading state:

```dart
ShineButton(
  text: 'Continue',
  isLoading: false,
  onPressed: () { /* action */ },
)
```

**Desktop:**
- Purple accent color (`#9281F7`)
- 6px border radius
- Black text

**Mobile:**
- Purple accent color
- 12px border radius
- White text

### VercelLoader

Animated loader in Vercel triangle style with pulsing glow:

```dart
VercelLoader(size: 40)
```

- Pulsing outer circle with purple glow
- Central white triangle
- 2-second rotation cycle

## Responsive Layout Patterns

### Desktop Layout (Auth Screen)

The authentication screen uses a split layout on desktop:

```
┌─────────────────┬──────────────────┐
│   BRANDING      │     FORM         │
│   (Grid BG)     │  (Dark Surface)  │
│   Logo          │  Input Fields    │
│   Tagline       │  Buttons         │
└─────────────────┴──────────────────┘
```

- Left panel: 380px fixed width with grid background
- Right panel: Centered form container (360px max)
- Border divider between sections

### Mobile Layout (Auth Screen)

```
┌──────────────────────────┐
│   FULL-SCREEN FORM       │
│   With Glass Container   │
└──────────────────────────┘
```

- Full viewport width
- Glass effect background
- Scrollable form

### Chat Bubbles

Message bubbles adapt for optimal readability:

**Desktop:**
- 6px border radius (compact, professional)
- No box shadow (performance optimization)
- Compact padding
- Sent color: `#111111` (very dark gray)
- Received color: Accent with 92% opacity

**Mobile:**
- 18-24px border radius (rounded, friendly)
- 2px box shadow for depth
- Standard padding
- 12px blur backdrop filter for glass effect

## Performance Optimizations

### RepaintBoundary
Message bubbles are wrapped in `RepaintBoundary` to prevent cascading repaints when:
- Scrolling through message list
- Animations occur
- Other bubbles re-render

### BackdropFilter (Mobile Only)
Frosted glass effect only renders on mobile where performance is tested. Desktop uses solid colors for better frame rates on lower-spec machines.

### Grid Background Fade
The Vercel-style grid in auth screen has:
- Radial gradient fade to reduce junction artifacts
- Custom painter for efficient rendering
- Opacity animation on splash screen

## Breakpoint System

```dart
static bool isDesktop(BuildContext context) =>
    MediaQuery.of(context).size.width >= 720;
```

### Width Ranges
- **Mobile**: 0-719px (phones, small tablets)
- **Desktop**: 720px+ (laptops, large tablets, PCs)

This breakpoint ensures:
- Phone apps stay in mobile mode (typically 360-428px)
- iPad/tablets can use desktop layout in landscape (≥720px)
- PC apps always use desktop layout

## Typography

Font family: `Inter` (from Google Fonts)

### Scale
- **Headings**: 20-24px (desktop), 18-22px (mobile)
- **Body**: 14-15px (both platforms)
- **Labels**: 12-13px (both platforms)
- **Meta**: 10-11px (timestamps, etc)

Font weights:
- Regular: 400
- Medium: 500
- Semibold: 600
- Bold: 700

## Color Accessibility

All text/background combinations maintain WCAG AA contrast:
- White text on black: 21:1
- White text on dark gray: 13:1
- Muted text: 4.5:1+

## Animation Guidelines

### Desktop
- Shorter durations (200-300ms)
- Subtle easing (easeOut, easeInOut)
- Minimal blur effects

### Mobile
- Slightly longer durations (300-400ms)
- Use BackdropFilter sparingly (frame rate impact)
- Prefer scale/transform over blur

## Future Updates

When adding new screens or components:

1. **Always use adaptive components** (AetherCard, VercelInput, etc)
2. **Check breakpoint with**: `LumynTheme.isDesktop(context)`
3. **Set font size based on platform**: `isPc ? 13 : 15`
4. **Test on both platforms**

Example:
```dart
@override
Widget build(BuildContext context) {
  final isPc = LumynTheme.isDesktop(context);
  
  return AetherCard(
    child: Text(
      'Responsive text',
      style: TextStyle(
        fontSize: isPc ? 13 : 15,
        fontFamily: 'Inter',
      ),
    ),
  );
}
```

## Assets & Configuration

### pubspec.yaml
- Added `google_fonts: ^7.0.0` for Inter font
- Ensure `uses-material-design: true` is set

### Material Theme
- AppBar: Transparent with semi-transparent blur on mobile
- Surface: `#0A0A0A`
- Primary: `#FFFFFF`
- Secondary: `#888888`
- Scaffold background: `#000000`

## Testing Checklist

- [ ] Desktop (1920x1080, 1440x900, 1280x720)
- [ ] Tablet landscape (≥720px)
- [ ] Phone portrait (<720px)
- [ ] Landscape mode on phone
- [ ] Light/Dark material design (use dark only)
- [ ] RTL layout (if supported)
- [ ] Font scaling (accessibility)
- [ ] Slow frame rate (Performance)

## References

- **Resend**: https://resend.com (design inspiration)
- **Vercel**: https://vercel.com (grid background)
- **Inter Font**: https://rsms.me/inter/
- **Google Fonts**: https://fonts.google.com/specimen/Inter
