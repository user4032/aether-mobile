import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════
// LUMYN THEME — DUAL DESIGN SYSTEM (Resend Dark + Liquid Glass)
// ═══════════════════════════════════════════════════════════

class LumynTheme {
  // ─── DESKTOP (Resend Dark) — Vercel/Resend style ───
  static const Color black      = Color(0xFF000000);
  static const Color surface    = Color(0xFF0A0A0A);
  static const Color border     = Color(0xFF1A1A1A);
  static const Color borderLoud = Color(0xFF333333);
  static const Color accent     = Color(0xFF9281F7); // Resend Purple (adjusted)
  static const Color textMuted  = Color(0xFF888888);
  static const Color text       = Color(0xFFEDEDED);

  // ─── MOBILE (Liquid Glass) ───
  static const Color glassBase     = Color(0x14FFFFFF);
  static const Color glassBorder   = Color(0x29FFFFFF);

  // ─── SHARED BRAND ───
  static const Color purple        = Color(0xFFB026FF);
  static const Color blue          = Color(0xFF007AFF);
  static const Color cyan          = Color(0xFF00C7FF);
  static const Color green         = Color(0xFF34C759);
  
  // ─── TYPOGRAPHY ───
  static const String fontFamily   = 'Inter';

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 720;
}

// ═══════════════════════════════════════════════════════════
// ADAPTIVE UI COMPONENTS
// ═══════════════════════════════════════════════════════════

/// Adaptive card — Resend Dark on desktop, Liquid Glass on mobile
class AetherCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? backgroundColor;

  const AetherCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 12,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isPc = LumynTheme.isDesktop(context);
    
    if (isPc) {
      // Desktop: Resend Dark style
      return Container(
        margin: margin,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor ?? LumynTheme.surface,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: LumynTheme.border, width: 1),
        ),
        child: child,
      );
    } else {
      // Mobile: Liquid Glass style
      return Container(
        margin: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: child,
            ),
          ),
        ),
      );
    }
  }
}

/// Animated loader in Vercel style
class VercelLoader extends StatefulWidget {
  final double size;
  const VercelLoader({super.key, this.size = 40});

  @override
  State<VercelLoader> createState() => _VercelLoaderState();
}

class _VercelLoaderState extends State<VercelLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing outer circle
              Container(
                width: 60 + (20 * _controller.value),
                height: 60 + (20 * _controller.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LumynTheme.accent.withValues(
                    alpha: 0.15 * (1 - _controller.value),
                  ),
                ),
              ),
              // Vercel-style triangle
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _VercelTrianglePainter(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VercelTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Responsive input field
class VercelInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscure;
  final Widget? suffixIcon;

  const VercelInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.obscure = false,
    this.suffixIcon,
  });

  @override
  State<VercelInput> createState() => _VercelInputState();
}

class _VercelInputState extends State<VercelInput> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPc = LumynTheme.isDesktop(context);

    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      obscureText: widget.obscure,
      decoration: InputDecoration(
        filled: true,
        fillColor: isPc ? Colors.black : Colors.white.withValues(alpha: 0.1),
        hintText: widget.hintText,
        hintStyle: TextStyle(
          color: isPc ? LumynTheme.textMuted : Colors.white.withValues(alpha: 0.4),
        ),
        suffixIcon: widget.suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: isPc ? LumynTheme.border : Colors.white.withValues(alpha: 0.1),
          ),
          borderRadius: BorderRadius.circular(isPc ? 6 : 12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: isPc ? LumynTheme.borderLoud : LumynTheme.accent,
          ),
          borderRadius: BorderRadius.circular(isPc ? 6 : 12),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// GRID BACKGROUND (Vercel-style for desktop)
// ═══════════════════════════════════════════════════════════
class GridBackground extends StatelessWidget {
  final Color gridColor;
  const GridBackground({super.key, this.gridColor = const Color(0xFF1A1A1A)});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainterVercel(color: gridColor),
      size: Size.infinite,
    );
  }
}

class _GridPainterVercel extends CustomPainter {
  final Color color;
  const _GridPainterVercel({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────
// SPLASH SCREEN
// ─────────────────────────────────────────────────────────
class LumynSplashScreen extends StatefulWidget {
  const LumynSplashScreen({super.key});

  @override
  State<LumynSplashScreen> createState() => _LumynSplashScreenState();
}

class _LumynSplashScreenState extends State<LumynSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _gridCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<double> _textSlide;
  late final Animation<double> _gridOpacity;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _textCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _gridCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

    _logoScale   = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack);
    _logoOpacity = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);
    _textOpacity = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut);
    _textSlide   = Tween<double>(begin: 10, end: 0)
        .animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _gridOpacity = CurvedAnimation(parent: _gridCtrl, curve: Curves.easeIn);

    _gridCtrl.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _logoCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _textCtrl.forward();
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _glowCtrl.dispose();
    _textCtrl.dispose();
    _gridCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Grid background (Vercel-style)
          FadeTransition(
            opacity: _gridOpacity,
            child: const _GridBackground(),
          ),

          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Full-screen Logo
                AnimatedBuilder(
                  animation: Listenable.merge([_logoCtrl, _glowCtrl]),
                  builder: (context, _) {
                    return ScaleTransition(
                      scale: _logoScale,
                      child: FadeTransition(
                        opacity: _logoOpacity,
                        child: SizedBox(
                          width: 300,
                          height: 300,
                          child: Image.asset(
                            'web/icons/logo-512.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Text
                AnimatedBuilder(
                  animation: _textCtrl,
                  builder: (context, _) {
                    return Transform.translate(
                      offset: Offset(0, _textSlide.value),
                      child: FadeTransition(
                        opacity: _textOpacity,
                        child: Column(
                          children: [
                            const Text(
                              'LUMYN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 6,
                                fontFamily: 'Inter',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Encrypted Protocol',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 2,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 56),

                // Loading dots
                AnimatedBuilder(
                  animation: _glowCtrl,
                  builder: (context, _) {
                    return _SplashDots(progress: _glowCtrl.value);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashDots extends StatelessWidget {
  final double progress;
  const _SplashDots({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final phase = (progress - i * 0.25).clamp(0.0, 1.0);
        final opacity = (sin(phase * pi)).clamp(0.15, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: opacity),
          ),
        );
      }),
    );
  }
}

class _GridBackground extends StatelessWidget {
  const _GridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(),
      size: MediaQuery.of(context).size,
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 0.5;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Fade gradient over grid
    final fadeRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final fadePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
      ).createShader(fadeRect);
    canvas.drawRect(fadeRect, fadePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────
// ADAPTIVE BACKGROUND
// Desktop: pure black with subtle grid
// Mobile: liquid glass gradient
// ─────────────────────────────────────────────────────────
class LumynBackground extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  const LumynBackground({super.key, required this.child, this.accentColor = const Color(0xFF1E1E2C)});

  @override
  Widget build(BuildContext context) {
    if (LumynTheme.isDesktop(context)) {
      return Container(color: Colors.black, child: child);
    }
    return _MobileLiquidBackground(accentColor: accentColor, child: child);
  }
}

// Legacy alias
class LiquidBackground extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  const LiquidBackground({super.key, required this.child, this.accentColor = const Color(0xFF1E1E2C)});

  @override
  Widget build(BuildContext context) => LumynBackground(accentColor: accentColor, child: child);
}

class _MobileLiquidBackground extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  const _MobileLiquidBackground({required this.child, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(seconds: 1),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.8, -0.5),
          radius: 1.5,
          colors: [accentColor, Colors.black],
        ),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────
// ADAPTIVE GLASS CONTAINER
// Desktop: sharp-bordered dark card (Vercel style)
// Mobile: frosted glass
// ─────────────────────────────────────────────────────────
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? color;

  const GlassContainer({super.key, required this.child, this.borderRadius = 20, this.padding, this.margin, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    if (LumynTheme.isDesktop(context)) {
      return _DesktopCard(
        borderRadius: borderRadius,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        color: color,
        child: child,
      );
    }
    return _MobileGlassContainer(
      borderRadius: borderRadius,
      padding: padding,
      margin: margin,
      width: width,
      height: height,
      color: color,
      child: child,
    );
  }
}

class _DesktopCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? color;

  const _DesktopCard({required this.child, this.borderRadius = 12, this.padding, this.margin, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: LumynTheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: LumynTheme.border, width: 1.0),
      ),
      child: child,
    );
  }
}

class _MobileGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? color;

  const _MobileGlassContainer({required this.child, this.borderRadius = 20, this.padding, this.margin, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width, height: height, margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (color ?? Colors.white).withValues(alpha: 0.08),
              border: Border.all(color: (color ?? Colors.white).withValues(alpha: 0.18), width: 1.5),
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 32, offset: const Offset(0, 8))],
            ),
            child: Stack(
              children: [
                Positioned(top: 0, left: 0, right: 0,
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.white.withValues(alpha: 0.12), Colors.transparent],
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// ADAPTIVE INPUT FIELD
// Desktop: Vercel/Resend sharp input
// Mobile: frosted glass input
// ─────────────────────────────────────────────────────────
class GlassInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;

  const GlassInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.keyboardType,
    this.inputFormatters,
    this.focusNode,
    this.onEditingComplete,
    this.onChanged,
  });

  @override
  State<GlassInput> createState() => _GlassInputState();
}

class _GlassInputState extends State<GlassInput> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(() { if (mounted) setState(() { _isFocused = _focusNode.hasFocus; }); });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (LumynTheme.isDesktop(context)) {
      return _DesktopInput(
        controller: widget.controller,
        hintText: widget.hintText,
        obscureText: widget.obscureText,
        suffixIcon: widget.suffixIcon,
        prefixIcon: widget.prefixIcon,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        focusNode: _focusNode,
        isFocused: _isFocused,
        onEditingComplete: widget.onEditingComplete,
        onChanged: widget.onChanged,
      );
    }
    return _MobileGlassInput(
      controller: widget.controller,
      hintText: widget.hintText,
      obscureText: widget.obscureText,
      suffixIcon: widget.suffixIcon,
      prefixIcon: widget.prefixIcon,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      focusNode: _focusNode,
      isFocused: _isFocused,
      onEditingComplete: widget.onEditingComplete,
      onChanged: widget.onChanged,
    );
  }
}

class _DesktopInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode focusNode;
  final bool isFocused;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;

  const _DesktopInput({
    required this.controller,
    required this.hintText,
    required this.focusNode,
    required this.isFocused,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.keyboardType,
    this.inputFormatters,
    this.onEditingComplete,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isFocused ? const Color(0xFF111111) : const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFocused ? const Color(0xFF444444) : const Color(0xFF1A1A1A),
          width: 1.0,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        inputFormatters: inputFormatters,
        keyboardType: keyboardType,
        onEditingComplete: onEditingComplete,
        onChanged: onChanged,
        style: const TextStyle(
          color: LumynTheme.text,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          fontFamily: 'Inter',
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: LumynTheme.textMuted,
            fontSize: 14,
            fontFamily: 'Inter',
          ),
          border: InputBorder.none,
          suffixIcon: suffixIcon != null
              ? Theme(
                  data: Theme.of(context).copyWith(
                    iconTheme: const IconThemeData(color: LumynTheme.textMuted),
                  ),
                  child: suffixIcon!,
                )
              : null,
          prefixIcon: prefixIcon,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _MobileGlassInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode focusNode;
  final bool isFocused;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;

  const _MobileGlassInput({
    required this.controller,
    required this.hintText,
    required this.focusNode,
    required this.isFocused,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.keyboardType,
    this.inputFormatters,
    this.onEditingComplete,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isFocused ? 1.02 : 1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            decoration: BoxDecoration(
              color: isFocused ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isFocused ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1), width: 1.5),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscureText,
              inputFormatters: inputFormatters,
              keyboardType: keyboardType,
              onEditingComplete: onEditingComplete,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                border: InputBorder.none,
                suffixIcon: suffixIcon,
                prefixIcon: prefixIcon,
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// ADAPTIVE BUTTON
// Desktop: Vercel-style solid white button
// Mobile: ShineButton (glass + shine animation)
// ─────────────────────────────────────────────────────────
class ShineButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  const ShineButton({super.key, required this.text, this.onPressed, this.isLoading = false});
  @override
  State<ShineButton> createState() => _ShineButtonState();
}

class _ShineButtonState extends State<ShineButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDesktop = LumynTheme.isDesktop(context);
    final disabled = widget.onPressed == null || widget.isLoading;

    if (isDesktop) {
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: disabled ? null : widget.onPressed,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: disabled ? 0.4 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 36,
              decoration: BoxDecoration(
                color: _isHovered ? const Color(0xFFE5E5E5) : Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        height: 14, width: 14,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                      )
                    : Text(
                        widget.text,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                          letterSpacing: 0,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    // Mobile: original shine effect
    return GestureDetector(
      onTap: disabled ? null : widget.onPressed,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: disabled ? 0.5 : 1.0,
        child: GlassContainer(
          height: 54, borderRadius: 50,
          child: Center(
            child: widget.isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    double progress = _controller.value <= 0.6 ? (_controller.value / 0.6) : 1.0;
                    return ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => LinearGradient(
                        colors: const [Color(0xFF888888), Colors.white, Color(0xFF888888)],
                        stops: const [0.3, 0.5, 0.7],
                        begin: Alignment(-2.0 + (progress * 4.0), 0),
                        end: Alignment(-1.0 + (progress * 4.0), 0),
                      ).createShader(bounds),
                      child: Text(widget.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    );
                  },
                ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// DESKTOP SIDEBAR ITEM (Vercel nav style)
// ─────────────────────────────────────────────────────────
class DesktopNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badgeCount;

  const DesktopNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount,
  });

  @override
  State<DesktopNavItem> createState() => _DesktopNavItemState();
}

class _DesktopNavItemState extends State<DesktopNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0xFF1A1A1A)
                : _hovered
                    ? const Color(0xFF111111)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.selected ? Colors.white : const Color(0xFF888888),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.selected ? Colors.white : const Color(0xFF888888),
                    fontSize: 13,
                    fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w400,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              if (widget.badgeCount != null && widget.badgeCount! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E2E2E)),
                  ),
                  child: Text(
                    '${widget.badgeCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// DESKTOP DIVIDER (Vercel style)
// ─────────────────────────────────────────────────────────
class DsHorizontalDivider extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  const DsHorizontalDivider({super.key, this.margin = const EdgeInsets.symmetric(vertical: 8)});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      height: 1,
      color: const Color(0xFF1A1A1A),
    );
  }
}

// ─────────────────────────────────────────────────────────
// DESKTOP LABEL (Vercel section label style)
// ─────────────────────────────────────────────────────────
class DsLabel extends StatelessWidget {
  final String text;
  const DsLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF444444),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// SNACKBAR (adaptive)
// ─────────────────────────────────────────────────────────
void showLumynSnack(BuildContext context, String message, {bool isError = false}) {
  final isDesktop = LumynTheme.isDesktop(context);
  if (isDesktop) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Inter'),
        ),
        backgroundColor: const Color(0xFF0A0A0A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isError ? const Color(0xFF4A1A1A) : const Color(0xFF1A1A1A),
          ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFF2A0A0A) : const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// BELOW: all existing components unchanged
// ─────────────────────────────────────────────────────────

class VerifiedBadge extends StatelessWidget {
  final double size;
  final Color color;
  const VerifiedBadge({super.key, this.size = 14, this.color = const Color(0xFF1DA1F2)});

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(color, Colors.black, 0.35) ?? color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color, dark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
      ),
      child: Icon(Icons.check, color: Colors.white, size: size * 0.65),
    );
  }
}

class StoryRingAvatar extends StatelessWidget {
  final String? avatarBase64;
  final String fallbackName;
  final double radius;
  final bool isGroup;
  final bool hasUnread;

  const StoryRingAvatar({
    super.key,
    this.avatarBase64,
    required this.fallbackName,
    this.radius = 26,
    this.isGroup = false,
    this.hasUnread = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasUnread) {
      return SafeAvatar(avatarBase64: avatarBase64, fallbackName: fallbackName, radius: radius, isGroup: isGroup);
    }
    return Container(
      width: radius * 2 + 6,
      height: radius * 2 + 6,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFB026FF), Color(0xFF00C7FF), Color(0xFFB026FF)],
          stops: [0.0, 0.5, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          width: radius * 2 + 1,
          height: radius * 2 + 1,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
          child: Center(
            child: SafeAvatar(avatarBase64: avatarBase64, fallbackName: fallbackName, radius: radius - 2, isGroup: isGroup),
          ),
        ),
      ),
    );
  }
}

class ReactionPicker extends StatefulWidget {
  final Function(String) onSelect;
  const ReactionPicker({super.key, required this.onSelect});
  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  static const _emojis = ['❤️', '😂', '🔥', '👍', '😮', '🎉', '🤯', '😢'];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: _opacity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 6))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _emojis.asMap().entries.map((entry) {
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 200 + entry.key * 30),
                    curve: Curves.elasticOut,
                    builder: (ctx, v, child) => Transform.scale(scale: v, child: child),
                    child: GestureDetector(
                      onTap: () => widget.onSelect(entry.value),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Text(entry.value, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReactionsBar extends StatefulWidget {
  final Map<String, List<String>> reactions;
  final String myName;
  final Function(String) onToggle;
  const ReactionsBar({super.key, required this.reactions, required this.myName, required this.onToggle});
  @override
  State<ReactionsBar> createState() => _ReactionsBarState();
}

class _ReactionsBarState extends State<ReactionsBar> {
  final Map<String, GlobalKey<_PopBadgeState>> _keys = {};

  @override
  Widget build(BuildContext context) {
    if (widget.reactions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 5, runSpacing: 4,
      children: widget.reactions.entries.map((entry) {
        final emoji = entry.key;
        final users = entry.value;
        final isMine = users.contains(widget.myName);
        _keys[emoji] ??= GlobalKey<_PopBadgeState>();
        return GestureDetector(
          onTap: () { _keys[emoji]?.currentState?.pop(); widget.onToggle(emoji); },
          child: _PopBadge(key: _keys[emoji], emoji: emoji, count: users.length, isMine: isMine),
        );
      }).toList(),
    );
  }
}

class _PopBadge extends StatefulWidget {
  final String emoji;
  final int count;
  final bool isMine;
  const _PopBadge({super.key, required this.emoji, required this.count, required this.isMine});
  @override
  State<_PopBadge> createState() => _PopBadgeState();
}

class _PopBadgeState extends State<_PopBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 0.85).chain(CurveTween(curve: Curves.easeIn)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 30),
    ]).animate(_ctrl);
  }

  void pop() { _ctrl.forward(from: 0); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.isMine ? const Color(0xFFB026FF).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: widget.isMine ? const Color(0xFFB026FF).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 4),
          Text('${widget.count}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;

  const HighlightedText({super.key, required this.text, required this.query, required this.baseStyle});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: baseStyle);
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) { spans.add(TextSpan(text: text.substring(start), style: baseStyle)); break; }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: baseStyle.copyWith(backgroundColor: const Color(0xFFFFD700).withValues(alpha: 0.5), color: Colors.white),
      ));
      start = idx + query.length;
    }
    return RichText(text: TextSpan(children: spans));
  }
}

class TypingIndicator extends StatefulWidget {
  final Color color;
  final double size;
  const TypingIndicator({super.key, this.color = Colors.white, this.size = 6.0});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 5,
      height: widget.size * 3,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              double val = _controller.value;
              double delay = index * 0.2;
              double adjustedVal = (val - delay) % 1.0;
              if (adjustedVal < 0) adjustedVal += 1.0;
              double dy = 0;
              if (adjustedVal < 0.4) {
                dy = -sin(adjustedVal * pi / 0.4) * widget.size;
              }
              return Transform.translate(offset: Offset(0, dy), child: child);
            },
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
          );
        }),
      ),
    );
  }
}

class HoldToRevealWrapper extends StatefulWidget {
  final Widget child;
  final bool isEphemeral;
  final VoidCallback? onRevealStarted;
  final int durationSeconds;

  const HoldToRevealWrapper({
    super.key,
    required this.child,
    required this.isEphemeral,
    this.onRevealStarted,
    this.durationSeconds = 5,
  });

  @override
  State<HoldToRevealWrapper> createState() => _HoldToRevealWrapperState();
}

class _HoldToRevealWrapperState extends State<HoldToRevealWrapper> with SingleTickerProviderStateMixin {
  bool _isRevealed = false;
  bool _hasBeenRevealedOnce = false;
  late AnimationController _timerController;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(vsync: this, duration: Duration(seconds: widget.durationSeconds));
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEphemeral) return widget.child;
    return Listener(
      onPointerDown: (_) {
        if (!mounted) return;
        setState(() => _isRevealed = true);
        if (!_hasBeenRevealedOnce) {
          _hasBeenRevealedOnce = true;
          _timerController.forward();
          widget.onRevealStarted?.call();
        }
      },
      onPointerUp: (_) { if (mounted) setState(() => _isRevealed = false); },
      onPointerCancel: (_) { if (mounted) setState(() => _isRevealed = false); },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 20.0, end: _isRevealed ? 0.0 : 20.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            builder: (context, blurValue, child) => ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue), child: widget.child),
          ),
        ],
      ),
    );
  }
}

class ElegantButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  const ElegantButton({super.key, required this.text, required this.onPressed});

  @override
  State<ElegantButton> createState() => _ElegantButtonState();
}

class _ElegantButtonState extends State<ElegantButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isHovered = true),
      onTapUp: (_) { setState(() => _isHovered = false); widget.onPressed(); },
      onTapCancel: () => setState(() => _isHovered = false),
      child: AnimatedContainer( 
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
        decoration: BoxDecoration(
          color: _isHovered ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: _isHovered ? Colors.white.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1), width: 1.5),
          borderRadius: BorderRadius.circular(30),
        ),
        alignment: Alignment.center,
        child: Text(widget.text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      ),
    );
  }
}

class SafeAvatar extends StatefulWidget {
  final String? avatarBase64;
  final String fallbackName;
  final double radius;
  final bool isGroup;
  const SafeAvatar({super.key, this.avatarBase64, required this.fallbackName, this.radius = 26, this.isGroup = false});
  @override
  State<SafeAvatar> createState() => _SafeAvatarState();
}

class _SafeAvatarState extends State<SafeAvatar> {
  Uint8List? _imageBytes;
  String? _lastBase64;

  @override
  void initState() { super.initState(); _decodeImage(); }

  @override
  void didUpdateWidget(covariant SafeAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarBase64 != widget.avatarBase64) _decodeImage();
  }

  void _decodeImage() {
    if (widget.avatarBase64 != null && widget.avatarBase64!.isNotEmpty) {
      if (_lastBase64 != widget.avatarBase64) { _lastBase64 = widget.avatarBase64; _imageBytes = base64Decode(widget.avatarBase64!); }
    } else { _imageBytes = null; _lastBase64 = null; }
  }

  Widget _buildFallback() {
    final initials = widget.fallbackName.isNotEmpty ? widget.fallbackName[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.radius * 0.7,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarContent = widget.isGroup
        ? Container(
            key: const ValueKey<String>('group_avatar'),
            color: const Color(0xFF1A1A1A),
            child: Icon(Icons.group, color: Colors.white54, size: widget.radius * 0.9),
          )
        : (_imageBytes != null
            ? Image.memory(
                _imageBytes!,
                key: ValueKey<String>('img_${widget.avatarBase64?.hashCode ?? _imageBytes.hashCode}'),
                width: widget.radius * 2,
                height: widget.radius * 2,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (ctx, err, stack) => _buildFallback(),
              )
            : _buildFallback());

    return SizedBox(
      width: widget.radius * 2,
      height: widget.radius * 2,
      child: ClipOval(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: avatarContent,
        ),
      ),
    );
  }
}

// Waveform painter (unchanged)
class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  const WaveformPainter({required this.amplitudes, required this.progress, required this.activeColor, required this.inactiveColor});

  @override
  void paint(Canvas canvas, Size size) {
    final count = amplitudes.length;
    const barWidth = 2.5;
    final spacing = (size.width - barWidth * count) / (count - 1);
    final centerY = size.height / 2;
    final paint = Paint()..strokeWidth = barWidth..strokeCap = StrokeCap.round;
    for (int i = 0; i < count; i++) {
      final double x = i * (barWidth + spacing) + (barWidth / 2);
      paint.color = (i / count) <= progress ? activeColor : inactiveColor;
      canvas.drawLine(Offset(x, centerY - amplitudes[i] / 2), Offset(x, centerY + amplitudes[i] / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AudioMessagePlayer extends StatefulWidget {
  final String base64Audio;
  final bool isMe;
  final bool isEphemeral;
  final bool showUnreadDot;
  final VoidCallback? onPlay;
  final Color? themeColor;

  const AudioMessagePlayer({super.key, required this.base64Audio, required this.isMe, this.isEphemeral = false, this.showUnreadDot = false, this.onPlay, this.themeColor});

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  static final ValueNotifier<int?> _activeAudioInstance = ValueNotifier<int?>(null);
  static final AudioPlayer _sharedAudioPlayer = AudioPlayer();
  static final ValueNotifier<PlayerState> _sharedPlayerState = ValueNotifier<PlayerState>(PlayerState.stopped);
  static final ValueNotifier<Duration> _sharedDuration = ValueNotifier<Duration>(Duration.zero);
  static final ValueNotifier<Duration> _sharedPosition = ValueNotifier<Duration>(Duration.zero);
  static bool _sharedEventsBound = false;

  late final int _instanceId;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _filePath;
  late List<double> _waveHeights;

  void _bindSharedEventsIfNeeded() {
    if (_sharedEventsBound) return;
    _sharedEventsBound = true;
    _sharedAudioPlayer.onPlayerStateChanged.listen((state) { _sharedPlayerState.value = state; });
    _sharedAudioPlayer.onDurationChanged.listen((d) { _sharedDuration.value = d; });
    _sharedAudioPlayer.onPositionChanged.listen((p) { _sharedPosition.value = p; });
    _sharedAudioPlayer.onPlayerComplete.listen((_) { _activeAudioInstance.value = null; _sharedPosition.value = Duration.zero; });
  }

  void _syncFromShared() {
    if (!mounted) return;
    final isActive = _activeAudioInstance.value == _instanceId;
    final nextIsPlaying = isActive && _sharedPlayerState.value == PlayerState.playing;
    final nextDuration = isActive ? _sharedDuration.value : _duration;
    final nextPosition = isActive ? _sharedPosition.value : (_isPlaying ? Duration.zero : _position);
    if (_isPlaying != nextIsPlaying || _duration != nextDuration || _position != nextPosition) {
      setState(() { _isPlaying = nextIsPlaying; _duration = nextDuration; _position = nextPosition; });
    }
  }

  int _computeStableSeed(String data) {
    int hash = 0x811C9DC5;
    for (final b in utf8.encode(data)) { hash ^= b; hash = (hash * 0x01000193) & 0x7fffffff; }
    return hash;
  }

  List<double> _buildWaveHeights(String audioData) {
    final rand = Random(_computeStableSeed(audioData));
    return List.generate(35, (_) => rand.nextDouble() * 20 + 4);
  }

  @override
  void initState() {
    super.initState();
    _instanceId = identityHashCode(this);
    _waveHeights = _buildWaveHeights(widget.base64Audio);
    _bindSharedEventsIfNeeded();
    _prepareAudio();
    _activeAudioInstance.addListener(_syncFromShared);
    _sharedPlayerState.addListener(_syncFromShared);
    _sharedDuration.addListener(_syncFromShared);
    _sharedPosition.addListener(_syncFromShared);
  }

  @override
  void didUpdateWidget(covariant AudioMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64Audio != widget.base64Audio) {
      _position = Duration.zero; _duration = Duration.zero; _isPlaying = false;
      _waveHeights = _buildWaveHeights(widget.base64Audio);
      if (_activeAudioInstance.value == _instanceId) _activeAudioInstance.value = null;
      _prepareAudio();
    }
  }

  Future<void> _prepareAudio() async {
    try {
      if (_filePath != null) {
        try { final prev = File(_filePath!); if (await prev.exists()) await prev.delete(); } catch (_) {}
      }
      final bytes = base64Decode(widget.base64Audio);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/audio_${_computeStableSeed(widget.base64Audio)}.m4a');
      await file.writeAsBytes(bytes);
      if (mounted) _filePath = file.path;
    } catch (e) { debugPrint("Audio load error: $e"); }
  }

  @override
  void dispose() {
    if (_activeAudioInstance.value == _instanceId) _activeAudioInstance.value = null;
    _activeAudioInstance.removeListener(_syncFromShared);
    _sharedPlayerState.removeListener(_syncFromShared);
    _sharedDuration.removeListener(_syncFromShared);
    _sharedPosition.removeListener(_syncFromShared);
    if (_filePath != null) { try { final f = File(_filePath!); if (f.existsSync()) f.deleteSync(); } catch (e) { debugPrint('Error deleting file'); } }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTheme = widget.themeColor != null && ThemeData.estimateBrightnessForColor(widget.themeColor!) == Brightness.dark ? Colors.white : Colors.black;
    final color = widget.isEphemeral ? const Color(0xFFE5B3FF) : (widget.isMe ? Colors.black : (widget.themeColor != null ? onTheme : Colors.white));
    final bgColor = widget.isEphemeral ? const Color(0xFFB026FF).withValues(alpha: 0.4) : (widget.isMe ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      width: MediaQuery.of(context).size.width * 0.55,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          GestureDetector(
            onTap: () async {
              if (_filePath == null) return;
              widget.onPlay?.call();
              final isCurrentActive = _activeAudioInstance.value == _instanceId;
              if (isCurrentActive && _sharedPlayerState.value == PlayerState.playing) {
                await _sharedAudioPlayer.stop();
                _activeAudioInstance.value = null;
                _sharedPosition.value = Duration.zero;
              } else {
                await _sharedAudioPlayer.stop();
                _activeAudioInstance.value = _instanceId;
                await _sharedAudioPlayer.play(DeviceFileSource(_filePath!));
              }
            },
            child: CircleAvatar(radius: 18, backgroundColor: bgColor, child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: color, size: 24)),
          ),
          if (widget.showUnreadDot) Positioned(top: -2, right: -2, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.themeColor ?? const Color(0xFF00C7FF), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 1.5)))),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              onTapDown: (details) async {
                if (_duration.inMilliseconds > 0) {
                  final pct = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                  if (_activeAudioInstance.value == _instanceId) {
                    await _sharedAudioPlayer.seek(Duration(milliseconds: (pct * _duration.inMilliseconds).toInt()));
                  }
                }
              },
              child: CustomPaint(
                size: const Size(double.infinity, 30),
                painter: WaveformPainter(
                  amplitudes: _waveHeights,
                  progress: _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0,
                  activeColor: color,
                  inactiveColor: color.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
  
}

// ─────────────────────────────────────────────────────────
// Віджет для свайпу повідомлення (Reply)
// ─────────────────────────────────────────────────────────
class SwipeToReplyWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback onSwipe;
  final Key messageKey;

  const SwipeToReplyWrapper({
    super.key,
    required this.child,
    required this.onSwipe,
    required this.messageKey,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Якщо свайпнули вправо
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          onSwipe();
        }
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────
// Анімований пошук (Search Input)
// ─────────────────────────────────────────────────────────
class AnimatedSearchInput extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  const AnimatedSearchInput({
    super.key, 
    required this.controller, 
    this.onSubmitted
  });

  @override
  State<AnimatedSearchInput> createState() => _AnimatedSearchInputState();
}

class _AnimatedSearchInputState extends State<AnimatedSearchInput> {
  @override
  Widget build(BuildContext context) {
    return GlassInput(
      controller: widget.controller,
      hintText: "Пошук...",
      prefixIcon: const Icon(Icons.search, color: Colors.white54),
      onEditingComplete: () {
        if (widget.onSubmitted != null) {
          widget.onSubmitted!(widget.controller.text);
        }
        FocusScope.of(context).unfocus();
      },
    );
  }
}