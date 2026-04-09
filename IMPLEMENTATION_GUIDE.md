# Implementation Guide: Responsive Components

## Quick Start

### 1. Basic Responsive Text

```dart
@override
Widget build(BuildContext context) {
  final isPc = LumynTheme.isDesktop(context);
  
  return Text(
    'Hello',
    style: TextStyle(
      fontSize: isPc ? 13 : 15,
      fontWeight: FontWeight.w600,
      fontFamily: 'Inter',
    ),
  );
}
```

### 2. Responsive Container

```dart
AetherCard(
  padding: const EdgeInsets.all(16),
  borderRadius: 12,
  child: Column(
    children: [/* content */],
  ),
)
```

### 3. Adaptive Layout (Side-by-side on desktop)

```dart
@override
Widget build(BuildContext context) {
  final isPc = LumynTheme.isDesktop(context);
  
  return isPc
    ? Row(children: [
        Container(width: 300, child: _sidebar()),
        Expanded(child: _content()),
      ])
    : Column(children: [
        _header(),
        Expanded(child: _content()),
      ]);
}
```

### 4. Adaptive Forms

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Text('Username', style: _labelStyle()),
    const SizedBox(height: 8),
    VercelInput(
      controller: _controller,
      hintText: 'Enter username',
    ),
    const SizedBox(height: 16),
    ShineButton(
      text: 'Submit',
      isLoading: _isLoading,
      onPressed: _submit,
    ),
  ],
)
```

## Component API Reference

### AetherCard

```dart
AetherCard({
  required Widget child,
  EdgeInsetsGeometry? padding,        // Inner spacing
  EdgeInsetsGeometry? margin,         // Outer spacing
  double borderRadius = 12,           // Corner rounding
  Color? backgroundColor,             // Override default
})
```

**Desktop Output:**
```
┌────────────────────────┐
│  #0A0A0A (Surface)     │  ← Background
│  [1px border #1A1A1A]  │
│  [12px radius]         │
│  Content               │
└────────────────────────┘
```

**Mobile Output:**
```
┌────────────────────────┐
│ [Blur 12, Glass Effect] │
│ [1px border white 10%]  │
│ [24px radius]          │
│ Content                │
└────────────────────────┘
```

### VercelInput

```dart
VercelInput({
  required TextEditingController controller,
  required String hintText,
  bool obscure = false,
  Widget? suffixIcon,
})
```

**States:**
- Enabled: Border `#1A1A1A`, fill `#000000` (desktop)
- Focused: Border `#333333`, stronger presence
- Mobile: All effects scale up (16px radius, larger padding)

### ShineButton

```dart
ShineButton({
  required String text,
  required VoidCallback onPressed,
  bool isLoading = false,
})
```

**States:**
- Normal: Purple accent `#9281F7`
- Loading: Muted color + spinning indicator
- Disabled: Not clickable when `isLoading=true`

### VercelLoader

```dart
VercelLoader({
  double size = 40,
})
```

**Animation:**
- Outer circle: Pulsing from 60→80px (opacity fade)
- Inner triangle: Steady white
- Duration: 2 seconds per cycle

## Pattern Examples

### Authentication Form Pattern

```dart
// lib/screens/auth_screen_example.dart
@override
Widget build(BuildContext context) {
  final isPc = LumynTheme.isDesktop(context);
  
  return Scaffold(
    backgroundColor: Colors.black,
    body: isPc ? _buildDesktop() : _buildMobile(),
  );
}

Widget _buildDesktop() {
  return Row(
    children: [
      // Left panel: Branding
      Container(
        width: 380,
        decoration: const BoxDecoration(
          color: Color(0xFF050505),
          border: Border(right: BorderSide(color: Color(0xFF1A1A1A))),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _GridBackground()),
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  _buildLogo(),
                  const Spacer(),
                  _buildBranding(),
                ],
              ),
            ),
          ],
        ),
      ),
      // Right panel: Form
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: _buildForm(),
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _buildMobile() {
  return Center(
    child: SingleChildScrollView(
      child: SizedBox(
        width: 320,
        child: _buildForm(),
      ),
    ),
  );
}

Widget _buildForm() {
  return AetherCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Sign In'),
        // Form fields...
        ShineButton(
          text: 'Continue',
          isLoading: _isLoading,
          onPressed: _handleLogin,
        ),
      ],
    ),
  );
}
```

### Chat Message Bubble Pattern

```dart
// In chat_screen.dart - existing code structure
final isPc = LumynTheme.isDesktop(context);

Widget bubble = RepaintBoundary(
  child: AetherCard(
    padding: EdgeInsets.symmetric(
      horizontal: isPc ? 12 : 14,
      vertical: isPc ? 8 : 10,
    ),
    borderRadius: isPc ? 6 : 18,
    backgroundColor: isPc 
      ? (isMe ? const Color(0xFF111111) : Colors.white.withOpacity(0.05))
      : (isMe ? LumynTheme.accent : Colors.white.withOpacity(0.08)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMessageContent(message),
        const SizedBox(height: 4),
        _buildMessageMeta(isEdited, timestamp),
      ],
    ),
  ),
);
```

### Responsive Grid Layout

```dart
Widget buildResponsiveGrid(BuildContext context) {
  final isPc = LumynTheme.isDesktop(context);
  
  return GridView.builder(
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: isPc ? 4 : 2,
      childAspectRatio: isPc ? 1.2 : 1.0,
      mainAxisSpacing: isPc ? 16 : 12,
      crossAxisSpacing: isPc ? 16 : 12,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) => AetherCard(
      padding: const EdgeInsets.all(16),
      child: _buildGridItem(items[index]),
    ),
  );
}
```

## CSS-like Media Queries in Dart

```dart
// Helper mixin for responsive values
mixin ResponsiveValues {
  double iPhoneTextSize(BuildContext context) =>
    LumynTheme.isDesktop(context) ? 13 : 15;
    
  double tabletPadding(BuildContext context) =>
    LumynTheme.isDesktop(context) ? 24 : 16;
    
  int gridColumns(BuildContext context) =>
    LumynTheme.isDesktop(context) ? 4 : 2;
}

// Usage
class MyWidget extends StatelessWidget with ResponsiveValues {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(tabletPadding(context)),
      child: Text(
        'Text',
        style: TextStyle(fontSize: iPhoneTextSize(context)),
      ),
    );
  }
}
```

## Common Mistakes to Avoid

### ❌ Hard-coded dimensions
```dart
// DON'T do this
Container(width: 300, height: 600)
```

### ✅ Responsive dimensions
```dart
// DO this
Container(
  width: MediaQuery.of(context).size.width * 0.8,
  child: ...
)
```

### ❌ No breakpoint checking
```dart
// DON'T do this - same layout for all sizes
Row(children: [sidebar, content])
```

### ✅ Check breakpoint
```dart
// DO this
final isPc = LumynTheme.isDesktop(context);
return isPc
  ? Row(children: [sidebar, content])
  : Column(children: [sidebar, content]);
```

### ❌ Different text styles everywhere
```dart
// DON'T do this
Text('Title', style: TextStyle(fontSize: 18))
Text('Body', style: TextStyle(fontSize: 14))
Text('Label', style: TextStyle(fontSize: 12))
```

### ✅ Helper method for styles
```dart
// DO this
TextStyle _titleStyle(BuildContext context) => TextStyle(
  fontSize: LumynTheme.isDesktop(context) ? 16 : 18,
  fontWeight: FontWeight.w600,
  fontFamily: 'Inter',
);
```

## Testing Responsive Layouts

```dart
// test/responsive_test.dart
void main() {
  testWidgets('Widget adapts to desktop size', (tester) async {
    addTearDown(tester.binding.window.physicalSizeTestValue =
      const Size(1920, 1080)); // Desktop
    addTearDown(
      () => addTearDown(tester.binding.window.clearPhysicalSizeTestValue),
    );
    
    await tester.pumpWidget(const MyApp());
    
    expect(find.byType(Row), findsOneWidget); // Desktop layout
  });

  testWidgets('Widget adapts to mobile size', (tester) async {
    addTearDown(tester.binding.window.physicalSizeTestValue =
      const Size(390, 844)); // iPhone
    addTearDown(
      () => addTearDown(tester.binding.window.clearPhysicalSizeTestValue),
    );
    
    await tester.pumpWidget(const MyApp());
    
    expect(find.byType(Column), findsOneWidget); // Mobile layout
  });
}
```

## Debug Tools

### Show Breakpoint State
```dart
// Add to AppBar for debugging
Text(
  LumynTheme.isDesktop(context) ? 'DESKTOP' : 'MOBILE',
  style: const TextStyle(color: Colors.red, fontSize: 10),
)
```

### Highlight Safe Areas
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Container(
      color: LumynTheme.isDesktop(context) ? Colors.blue : Colors.green,
      child: _buildContent(),
    ),
  );
}
```

## Performance Monitoring

Watch for performance issues on low-end devices:

```dart
// Use RepaintBoundary for complex widgets
RepaintBoundary(
  child: _expensiveWidget(),
)

// Avoid BackdropFilter on desktop
if (!LumynTheme.isDesktop(context)) {
  BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
    child: _widget(),
  )
} else {
  _widget()
}
```
