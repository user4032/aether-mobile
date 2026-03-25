import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:cryptography/cryptography.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

String? currentActiveChat;

String lang = 'uk';
String t(String uk, String en) => lang == 'uk' ? uk : en;

const String kAdminUsername = 'den';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, 
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aether',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black, 
        fontFamily: 'Inter', 
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xFF888888),
          surface: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      home: const MainGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ДИЗАЙН
// ─────────────────────────────────────────────────────────────────────────────

Color getProminentColor(String? base64) {
  if (base64 == null || base64.isEmpty) return const Color(0xFF1E1E2C);
  try {
    final bytes = base64Decode(base64);
    if (bytes.length < 100) return const Color(0xFF1E1E2C);
    int r = 0, g = 0, b = 0;
    int samples = 0;
    for (int i = bytes.length ~/ 4; i < bytes.length ~/ 2; i += 100) {
      r += bytes[i];
      g += bytes[(i + 1) % bytes.length];
      b += bytes[(i + 2) % bytes.length];
      samples++;
    }
    return Color.fromARGB(255, (r ~/ samples) ~/ 2, (g ~/ samples) ~/ 2, (b ~/ samples) ~/ 2);
  } catch (e) {
    return const Color(0xFF1E1E2C);
  }
}

class LiquidBackground extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  const LiquidBackground({super.key, required this.child, this.accentColor = const Color(0xFF1E1E2C)});

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

// ── Verified Badge ────────────────────────────────────────────────────────────
class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF1DA1F2), Color(0xFF0066CC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: const Color(0xFF1DA1F2).withValues(alpha: 0.5), blurRadius: 6)],
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
  const HoldToRevealWrapper({super.key, required this.child, required this.isEphemeral, this.onRevealStarted});
  @override
  State<HoldToRevealWrapper> createState() => _HoldToRevealWrapperState();
}

class _HoldToRevealWrapperState extends State<HoldToRevealWrapper> {
  bool _isRevealed = false;
  bool _hasBeenRevealedOnce = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isEphemeral) return widget.child;
    return Listener(
      onPointerDown: (_) {
        if (!mounted) return;
        setState(() => _isRevealed = true);
        if (!_hasBeenRevealedOnce) { _hasBeenRevealedOnce = true; widget.onRevealStarted?.call(); }
      },
      onPointerUp: (_) { if (mounted) setState(() => _isRevealed = false); },
      onPointerCancel: (_) { if (mounted) setState(() => _isRevealed = false); },
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 20.0, end: _isRevealed ? 0.0 : 20.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            builder: (context, blurValue, child) => ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue), child: widget.child),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _isRevealed ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFB026FF).withValues(alpha: 0.5), width: 1.5),
                  boxShadow: [BoxShadow(color: const Color(0xFFB026FF).withValues(alpha: 0.3), blurRadius: 10)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.fingerprint, color: Color(0xFFE5B3FF), size: 16),
                  const SizedBox(width: 6),
                  Text(t("Утримуйте", "Hold to reveal"), style: const TextStyle(color: Color(0xFFE5B3FF), fontSize: 12, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SwipeToReplyWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback onSwipe;
  final Key messageKey;
  const SwipeToReplyWrapper({super.key, required this.child, required this.onSwipe, required this.messageKey});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: messageKey,
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.15},
      movementDuration: const Duration(milliseconds: 200),
      confirmDismiss: (direction) async { HapticFeedback.lightImpact(); onSwipe(); return false; },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.reply, color: Colors.white, size: 20),
        ),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INPUTS & BUTTONS
// ─────────────────────────────────────────────────────────────────────────────

class GlassInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  const GlassInput({super.key, required this.controller, required this.hintText, this.obscureText = false, this.inputFormatters, this.focusNode, this.keyboardType});
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
    _focusNode.addListener(() { setState(() { _isFocused = _focusNode.hasFocus; }); });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _isFocused ? 1.02 : 1.0,
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
              color: _isFocused ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _isFocused ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1), width: 1.5),
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              obscureText: widget.obscureText,
              inputFormatters: widget.inputFormatters,
              keyboardType: widget.keyboardType,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              ),
            ),
          ),
        ),
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
  @override
  void initState() { super.initState(); _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (widget.onPressed == null || widget.isLoading) ? null : widget.onPressed,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: (widget.onPressed == null || widget.isLoading) ? 0.5 : 1.0,
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

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: Colors.white.withValues(alpha: 0.1),
      child: widget.isGroup
        ? Icon(Icons.group, color: Colors.white70, size: widget.radius * 0.9)
        : (_imageBytes != null
          ? ClipOval(child: Image.memory(_imageBytes!, width: widget.radius * 2, height: widget.radius * 2, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (ctx, err, stack) => _buildFallback()))
          : _buildFallback()),
    );
  }

  Widget _buildFallback() => Text(
    widget.fallbackName.isNotEmpty ? widget.fallbackName[0].toUpperCase() : '?',
    style: TextStyle(color: Colors.white, fontSize: widget.radius * 0.7, fontWeight: FontWeight.w600),
  );
}

class AnimatedSearchInput extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onSubmitted;
  const AnimatedSearchInput({super.key, required this.controller, required this.onSubmitted});
  @override
  State<AnimatedSearchInput> createState() => _AnimatedSearchInputState();
}

class _AnimatedSearchInputState extends State<AnimatedSearchInput> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() { super.initState(); _focusNode.addListener(() { setState(() { _isFocused = _focusNode.hasFocus; }); }); }
  @override
  void dispose() { _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final double targetWidth = _isFocused ? MediaQuery.of(context).size.width - 32 : 150.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: targetWidth,
      height: 40,
      child: GlassContainer(
        borderRadius: 9999,
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isCollapsed: true,
            hintText: t("Пошук", "Search"),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: _isFocused ? 0.7 : 0.4), height: 1.2),
            prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: _isFocused ? 0.7 : 0.4), size: 18),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  WaveformPainter({required this.amplitudes, this.progress = 0.0, required this.activeColor, required this.inactiveColor});

  @override
  void paint(Canvas canvas, Size size) {
    final int count = amplitudes.length;
    if (count == 0) return;
    final double spacing = 3.0;
    final double barWidth = (size.width - (spacing * (count - 1))) / count;
    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = barWidth > 0 ? barWidth : 2.0;
    final double centerY = size.height / 2;
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _filePath;
  late List<double> _waveHeights;

  @override
  void initState() {
    super.initState();
    _prepareAudio();
    final seed = widget.base64Audio.length > 20 ? widget.base64Audio.substring(0, 20).hashCode : widget.base64Audio.hashCode;
    final rand = Random(seed);
    _waveHeights = List.generate(35, (_) => rand.nextDouble() * 20 + 4);
    _audioPlayer.onPlayerStateChanged.listen((state) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _isPlaying = state == PlayerState.playing); }); });
    _audioPlayer.onDurationChanged.listen((d) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _duration = d); }); });
    _audioPlayer.onPositionChanged.listen((p) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _position = p); }); });
  }

  Future<void> _prepareAudio() async {
    try {
      final bytes = base64Decode(widget.base64Audio);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await file.writeAsBytes(bytes);
      if (mounted) { _filePath = file.path; await _audioPlayer.setSourceDeviceFile(_filePath!); }
    } catch (e) { debugPrint("Audio load error: $e"); }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    if (_filePath != null) { try { final f = File(_filePath!); if (f.existsSync()) f.deleteSync(); } catch (e) {} }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isEphemeral ? const Color(0xFFE5B3FF) : (widget.isMe ? Colors.black : Colors.white);
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
              if (_isPlaying) { await _audioPlayer.pause(); } else { await _audioPlayer.play(DeviceFileSource(_filePath!)); }
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
                  await _audioPlayer.seek(Duration(milliseconds: (pct * _duration.inMilliseconds).toInt()));
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

// ─────────────────────────────────────────────────────────────────────────────
// ШЛЮЗ
// ─────────────────────────────────────────────────────────────────────────────
class MainGate extends StatefulWidget {
  const MainGate({super.key});
  @override
  State<MainGate> createState() => _MainGateState();
}

class _MainGateState extends State<MainGate> {
  bool _isLoading = true;
  String? _deviceId, _userName, _publicKey;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    lang = prefs.getString('lang') ?? 'uk';
    String? id = prefs.getString('device_id');
    String? pub = prefs.getString('public_key');
    String? priv = await _storage.read(key: 'private_key');
    if (id == null || pub == null || priv == null) {
      id = const Uuid().v4();
      final keyPair = await X25519().newKeyPair();
      final pubKeyBytes = await keyPair.extractPublicKey();
      final privKeyBytes = await keyPair.extractPrivateKeyBytes();
      await prefs.setString('device_id', id);
      await prefs.setString('public_key', base64Encode(pubKeyBytes.bytes));
      await _storage.write(key: 'private_key', value: base64Encode(privKeyBytes));
      pub = base64Encode(pubKeyBytes.bytes);
    }
    setState(() { _deviceId = id; _publicKey = pub; _userName = prefs.getString('user_name'); _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.white)));
    if (_userName == null) return AuthScreen(deviceId: _deviceId!, publicKey: _publicKey!, onSuccess: (name) { setState(() { _userName = name; }); });
    return ContactsScreen(deviceId: _deviceId!, userName: _userName!, publicKey: _publicKey!);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// АВТОРИЗАЦІЯ — 3 КРОКИ: логін / реєстрація / код email
// ─────────────────────────────────────────────────────────────────────────────
class AuthScreen extends StatefulWidget {
  final String deviceId, publicKey;
  final Function(String) onSuccess;
  const AuthScreen({super.key, required this.deviceId, required this.publicKey, required this.onSuccess});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // 0=login, 1=register_form, 2=verify_code
  int _step = 0;
  bool isLoading = false;
  final _nameController = TextEditingController();
  final _passController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  String? _pendingEmail;

  void _login() async {
    final name = _nameController.text.trim();
    final pass = _passController.text.trim();
    if (name.isEmpty || pass.isEmpty) return;
    setState(() => isLoading = true);
    io.Socket s = io.io('https://aether-mu-red.vercel.app/', {'transports': ['websocket'], 'forceNew': true});
    s.connect();
    s.onConnect((_) {
      s.emitWithAck('login', {'userName': name, 'password': pass, 'publicKey': widget.publicKey}, ack: (dynamic response) async {
        s.dispose();
        if (response['success'] == true) {
          await (await SharedPreferences.getInstance()).setString('user_name', name);
          widget.onSuccess(name);
        } else {
          setState(() => isLoading = false);
          _showSnack(response['message'] ?? t('Помилка', 'Error'), isError: true);
        }
      });
    });
  }

  void _sendCode() async {
    final name = _nameController.text.trim();
    final pass = _passController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || pass.isEmpty || email.isEmpty) return;
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      _showSnack(t('Невірний формат email', 'Invalid email format'), isError: true);
      return;
    }
    setState(() => isLoading = true);
    io.Socket s = io.io('https://aether-mu-red.vercel.app/', {'transports': ['websocket'], 'forceNew': true});
    s.connect();
    s.onConnect((_) {
      s.emitWithAck('send_verification_email', {
        'userName': name, 'email': email, 'password': pass, 'publicKey': widget.publicKey,
      }, ack: (dynamic response) {
        s.dispose();
        setState(() => isLoading = false);
        if (response['success'] == true) {
          _pendingEmail = email;
          setState(() => _step = 2);
        } else {
          _showSnack(response['message'] ?? t('Помилка', 'Error'), isError: true);
        }
      });
    });
  }

  void _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;
    setState(() => isLoading = true);
    io.Socket s = io.io('https://aether-mu-red.vercel.app/', {'transports': ['websocket'], 'forceNew': true});
    s.connect();
    s.onConnect((_) {
      s.emitWithAck('verify_email_code', {'email': _pendingEmail, 'code': code}, ack: (dynamic response) async {
        s.dispose();
        setState(() => isLoading = false);
        if (response['success'] == true) {
          final name = _nameController.text.trim();
          await (await SharedPreferences.getInstance()).setString('user_name', name);
          widget.onSuccess(name);
        } else {
          _showSnack(response['message'] ?? t('Невірний код', 'Invalid code'), isError: true);
        }
      });
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? Colors.red.shade900 : const Color(0xFF333333),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LiquidBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: _step == 2 ? _buildCodeStep() : (_step == 1 ? _buildRegisterStep() : _buildLoginStep()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginStep() {
    return Column(
      key: const ValueKey('login'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t("З поверненням.", "Welcome back."), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8),
        const Text("Aether Core Protocol", style: TextStyle(fontSize: 16, color: Colors.white70)),
        const SizedBox(height: 48),
        GlassInput(controller: _nameController, hintText: t("Нікнейм", "Username"), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))]),
        const SizedBox(height: 16),
        GlassInput(controller: _passController, hintText: t("Пароль", "Password"), obscureText: true),
        const SizedBox(height: 32),
        ShineButton(text: t("Увійти", "Sign In"), isLoading: isLoading, onPressed: _login),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() => _step = 1),
          child: Text(t("Немає акаунту? Створити", "Don't have an account? Register"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _buildRegisterStep() {
    return Column(
      key: const ValueKey('register'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t("Створити акаунт.", "Create account."), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8),
        const Text("Aether Core Protocol", style: TextStyle(fontSize: 16, color: Colors.white70)),
        const SizedBox(height: 48),
        GlassInput(controller: _nameController, hintText: t("Нікнейм", "Username"), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))]),
        const SizedBox(height: 16),
        GlassInput(controller: _emailController, hintText: t("Email адреса", "Email address"), keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        GlassInput(controller: _passController, hintText: t("Пароль", "Password"), obscureText: true),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t("На вказаний email прийде код підтвердження", "A verification code will be sent to your email"),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
        ),
        const SizedBox(height: 24),
        ShineButton(text: t("Отримати код", "Get Code"), isLoading: isLoading, onPressed: _sendCode),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() => _step = 0),
          child: Text(t("Вже є акаунт? Увійти", "Already have an account? Sign In"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      key: const ValueKey('code'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.email_outlined, color: Colors.white70, size: 48),
        const SizedBox(height: 24),
        Text(t("Перевір пошту.", "Check your email."), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8),
        Text(t("Код надіслано на", "Code sent to"), style: const TextStyle(color: Colors.white70, fontSize: 14)),
        Text(_pendingEmail ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 48),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 16),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 32, letterSpacing: 16),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        ShineButton(text: t("Підтвердити", "Verify"), isLoading: isLoading, onPressed: _verifyCode),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() { _step = 1; _codeController.clear(); }),
          child: Text(t("← Назад", "← Back"), style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ГОЛОВНИЙ ЕКРАН
// ─────────────────────────────────────────────────────────────────────────────
class ContactsScreen extends StatefulWidget {
  final String deviceId, userName, publicKey;
  const ContactsScreen({super.key, required this.deviceId, required this.userName, required this.publicKey});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  int _currentIndex = 0;
  late io.Socket _bgSocket;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();
  final AesGcm _aes = AesGcm.with256bits();
  bool _isSearching = false;

  List<Map<String, dynamic>> _recentChats = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  String? _myAvatar;
  String _myBio = "";
  bool _myVerified = false;
  bool get _isAdmin => widget.userName == kAdminUsername;

  final _addFriendController = TextEditingController();
  final _searchController = TextEditingController();

  // Адмін: пошук юзерів для верифікації
  final _verifySearchController = TextEditingController();
  List<Map<String, dynamic>> _verifyResults = [];

  @override
  void initState() {
    super.initState();
    _bgSocket = io.io('https://aether-mu-red.vercel.app/', {'transports': ['websocket'], 'forceNew': true});
    _bgSocket.connect();
    _bgSocket.onConnect((_) { _bgSocket.emit('set_active', widget.userName); _loadData(); });
    _bgSocket.on('message', (data) {
      var msg = Map<String, dynamic>.from(data);
      if (msg['receiverName'] == widget.userName || (msg['receiverName'].toString().startsWith('GROUP_') && msg['senderName'] != widget.userName)) {
        if (currentActiveChat != msg['senderName'] && currentActiveChat != msg['receiverName']) { _audioPlayer.play(AssetSource('ding.mp3')); }
        _loadData();
      }
    });
    _bgSocket.on('refresh_chats', (data) { if (data['userName'] == widget.userName || data['userName'] == 'all') _loadData(); });
    _bgSocket.on('messages_read', (data) { _loadData(); });
    _bgSocket.on('friends_data', (data) {
      if (mounted) {
        setState(() {
          _myAvatar = data['myAvatar'];
          _myBio = data['myBio'] ?? "";
          _myVerified = data['myVerified'] == true;
          _friends = List<Map<String, dynamic>>.from(data['friends']);
          _pendingRequests = List<Map<String, dynamic>>.from(data['pending']);
        });
      }
    });
  }

  Future<SecretKey> _getSecretKey(String remotePub, bool isGroup) async {
    if (isGroup) {
      final hash = await Sha256().hash(utf8.encode(remotePub));
      return await _aes.newSecretKeyFromBytes(hash.bytes);
    } else {
      final priv = await const FlutterSecureStorage().read(key: 'private_key');
      final secret = await X25519().sharedSecretKey(
        keyPair: SimpleKeyPairData(base64Decode(priv!), publicKey: SimplePublicKey(base64Decode(widget.publicKey), type: KeyPairType.x25519), type: KeyPairType.x25519),
        remotePublicKey: SimplePublicKey(base64Decode(remotePub), type: KeyPairType.x25519),
      );
      return await _aes.newSecretKeyFromBytes(await secret.extractBytes());
    }
  }

  Future<String> _decrypt(String cipher, String nonce, String macString, String remotePub, bool isGroup) async {
    try {
      final key = await _getSecretKey(remotePub, isGroup);
      final box = SecretBox(base64Decode(cipher), nonce: base64Decode(nonce), mac: Mac(base64Decode(macString)));
      return utf8.decode(await _aes.decrypt(box, secretKey: key));
    } catch (e) { return "Encrypted"; }
  }

  void _loadData() {
    _bgSocket.emitWithAck('get_recent_chats', widget.userName, ack: (dynamic data) async {
      List<Map<String, dynamic>> tempChats = List<Map<String, dynamic>>.from(data);
      for (var chat in tempChats) {
        if (chat['lastMessage'] != null) {
          var m = Map<String, dynamic>.from(chat['lastMessage']);
          String msgType = m['type'] ?? 'text';
          bool isEph = m['isEphemeral'] == true || msgType.startsWith('ephemeral_');
          msgType = msgType.replaceFirst('ephemeral_', '');
          if (isEph) {
            chat['decryptedText'] = "✨ ${t('Ефірне повідомлення', 'Aether message')}";
          } else if (msgType == 'audio') {
            chat['decryptedText'] = t("Голосове повідомлення", "Voice message");
          } else if (msgType == 'image') {
            chat['decryptedText'] = t("Фотографія", "Image");
          } else if (m['ciphertext'] != null && chat['publicKey'] != null) {
            String dec = await _decrypt(m['ciphertext'], m['nonce'], m['mac'], chat['publicKey'], chat['isGroup'] == true);
            try {
              if (dec.startsWith('{') && dec.endsWith('}')) { chat['decryptedText'] = jsonDecode(dec)['text']; }
              else { chat['decryptedText'] = dec; }
            } catch (e) { chat['decryptedText'] = dec; }
          } else {
            chat['decryptedText'] = m['text'] ?? t("Повідомлення", "Message");
          }
          if (m['senderName'] == widget.userName) {
            chat['decryptedText'] = "${t('Ви', 'You')}: ${chat['decryptedText']}";
          } else if (chat['isGroup'] == true) {
            chat['decryptedText'] = "${m['senderName']}: ${chat['decryptedText']}";
          }
        }
      }
      tempChats.removeWhere((c) => c['isHidden'] == true);
      if (mounted) setState(() { _recentChats = tempChats; });
    });
    _bgSocket.emit('get_friends_data', widget.userName);
  }

  Future<void> _updateAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50, maxWidth: 256, maxHeight: 256);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final base64String = base64Encode(bytes);
      setState(() { _myAvatar = base64String; });
      _bgSocket.emit('update_avatar', {'userName': widget.userName, 'avatar': base64String});
      _loadData();
    }
  }

  void _sendFriendRequest() {
    final target = _addFriendController.text.trim();
    if (target.isEmpty) return;
    _bgSocket.emitWithAck('send_friend_request', {'requester': widget.userName, 'receiver': target}, ack: (dynamic data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'], style: const TextStyle(color: Colors.white)), backgroundColor: data['success'] ? const Color(0xFF333333) : Colors.red.shade900, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
        _addFriendController.clear();
      }
    });
  }

  void _respondToRequest(String requester, String action) {
    _bgSocket.emit('respond_friend_request', {'requester': requester, 'receiver': widget.userName, 'action': action});
    _loadData();
  }

  void _showCreateGroupDialog() {
    if (_friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Спочатку додайте друзів!', 'Add friends first!'), style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
      return;
    }
    final groupNameController = TextEditingController();
    List<String> selectedFriends = [];
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('Створити групу', 'Create Group'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                GlassInput(controller: groupNameController, hintText: t('Назва групи', 'Group Name')),
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: Text(t("Учасники", "Members"), style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70, fontSize: 13))),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _friends.length,
                    itemBuilder: (context, index) {
                      final friend = _friends[index]['userName'];
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(friend, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        value: selectedFriends.contains(friend),
                        activeColor: Colors.white,
                        checkColor: Colors.black,
                        side: const BorderSide(color: Colors.white54),
                        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        onChanged: (bool? value) { setStateSB(() { if (value == true) { selectedFriends.add(friend); } else { selectedFriends.remove(friend); } }); },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: Colors.white70, fontSize: 14))),
                    TextButton(
                      onPressed: () {
                        if (groupNameController.text.trim().isNotEmpty && selectedFriends.isNotEmpty) {
                          _bgSocket.emitWithAck('create_group', {'name': groupNameController.text.trim(), 'participants': selectedFriends, 'creator': widget.userName}, ack: (dynamic data) { if (data['success'] == true) _loadData(); });
                          Navigator.pop(context);
                        }
                      },
                      child: Text(t('Створити', 'Create'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditBioDialog() {
    final TextEditingController bioController = TextEditingController(text: _myBio);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t("Про себе", "About"), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: bioController,
                maxLength: 100,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: t("Напишіть щось...", "Write something..."),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4))),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  counterStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(t("Скасувати", "Cancel"), style: const TextStyle(color: Colors.white70))),
                  TextButton(
                    onPressed: () {
                      _bgSocket.emit('update_bio', {'userName': widget.userName, 'bio': bioController.text.trim()});
                      setState(() => _myBio = bioController.text.trim());
                      Navigator.pop(context);
                    },
                    child: Text(t("Зберегти", "Save"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserProfile(String partnerName, String? initialAvatar, String? publicKey, bool isGroup) {
    if (isGroup || partnerName == widget.userName) return;
    String? currentBio;
    String? currentAvatar = initialAvatar;
    bool fetched = false;
    bool isVerifiedUser = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        Map<String, dynamic>? chatSettings;
        try { chatSettings = _recentChats.firstWhere((c) => c['partnerName'] == partnerName); } catch (e) {}
        bool isBlocked = chatSettings?['isBlocked'] == true;
        bool isPinned = chatSettings?['isPinned'] == true;
        return StatefulBuilder(
          builder: (context, setStateSB) {
            if (!fetched) {
              fetched = true;
              _bgSocket.emitWithAck('get_user_profile', partnerName, ack: (dynamic data) {
                if (data['success'] == true) setStateSB(() { currentBio = data['bio']; currentAvatar = data['avatar'] ?? currentAvatar; isVerifiedUser = data['isVerified'] == true; });
              });
            }
            return Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SafeAvatar(avatarBase64: currentAvatar, fallbackName: partnerName, radius: 46),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(partnerName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                            if (isVerifiedUser) ...[const SizedBox(width: 8), const VerifiedBadge(size: 22)],
                          ],
                        ),
                        if (currentBio != null && currentBio!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(currentBio!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15)),
                        ],
                        const SizedBox(height: 32),
                        GlassContainer(
                          child: Column(children: [
                            ListTile(leading: const Icon(Icons.chat_bubble_outline, color: Colors.white), title: Text(t("Написати", "Message"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), onTap: () { Navigator.pop(context); _startChat(partnerName, publicKey, targetAvatar: currentAvatar, isVerified: isVerifiedUser); }),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white), title: Text(isPinned ? t("Відкріпити чат", "Unpin Chat") : t("Закріпити чат", "Pin Chat"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), onTap: () { _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': !isPinned, 'isHidden': chatSettings?['isHidden'] == true, 'isDeleted': false, 'isBlocked': isBlocked}); Navigator.pop(context); }),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(leading: const Icon(Icons.visibility_off, color: Colors.white), title: Text(t("Приховати чат", "Hide Chat"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), onTap: () { _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': isPinned, 'isHidden': true, 'isDeleted': false, 'isBlocked': isBlocked}); Navigator.pop(context); }),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          child: Column(children: [
                            ListTile(leading: Icon(isBlocked ? Icons.lock_open : Icons.block, color: const Color(0xFFFF3B30)), title: Text(isBlocked ? t("Розблокувати", "Unblock") : t("Заблокувати", "Block"), style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500)), onTap: () { _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': isPinned, 'isHidden': chatSettings?['isHidden'] == true, 'isDeleted': false, 'isBlocked': !isBlocked}); setStateSB(() { isBlocked = !isBlocked; }); _loadData(); }),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)), title: Text(t("Видалити історію", "Delete History"), style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500)), onTap: () { _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': false, 'isHidden': false, 'isDeleted': true, 'isBlocked': isBlocked}); Navigator.pop(context); }),
                          ]),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showChatOptions(Map<String, dynamic> chat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(leading: Icon(chat['isPinned'] == true ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white), title: Text(chat['isPinned'] == true ? t('Відкріпити', 'Unpin') : t('Закріпити', 'Pin'), style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': !(chat['isPinned'] == true), 'isHidden': chat['isHidden'] == true, 'isDeleted': false, 'isBlocked': chat['isBlocked'] == true}); }),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ListTile(leading: const Icon(Icons.visibility_off, color: Colors.white), title: Text(t('Приховати чат', 'Hide Chat'), style: const TextStyle(color: Colors.white)), subtitle: Text(t('Можна знайти через пошук', 'Can be found via search'), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)), onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': chat['isPinned'] == true, 'isHidden': true, 'isDeleted': false, 'isBlocked': chat['isBlocked'] == true}); }),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)), title: Text(t('Видалити', 'Delete'), style: const TextStyle(color: Color(0xFFFF3B30))), onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': false, 'isHidden': false, 'isDeleted': true, 'isBlocked': chat['isBlocked'] == true}); }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startChat(String targetName, String? targetKey, {String? targetAvatar, bool isVerified = false}) {
    if (targetName.isEmpty) return;
    if (targetKey != null) { _openChatScreen(targetName, targetKey, avatar: targetAvatar, isVerified: isVerified); return; }
    setState(() => _isSearching = true);
    _bgSocket.emitWithAck('get_key', targetName, ack: (dynamic response) {
      if (mounted) setState(() { _isSearching = false; });
      if (response['success'] == true) {
        _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': targetName, 'isPinned': false, 'isHidden': false, 'isDeleted': false, 'isBlocked': false});
        _openChatScreen(targetName, response['publicKey'], avatar: response['avatar'], isVerified: response['isVerified'] == true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? t('Не знайдено', 'Not found'), style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red.shade900, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
      }
    });
  }

  void _openChatScreen(String targetName, String targetKey, {String? avatar, bool isVerified = false}) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
      deviceId: widget.deviceId, userName: widget.userName, myPublicKey: widget.publicKey,
      partnerName: targetName, partnerPublicKey: targetKey, partnerAvatar: avatar,
      partnerIsVerified: isVerified,
      friends: _friends,
    ))).then((_) => _loadData());
  }

  void _logout() async {
    await (await SharedPreferences.getInstance()).remove('user_name');
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const MainGate()), (r) => false);
  }

  void _changeLanguage(String newLang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', newLang);
    setState(() { lang = newLang; });
    _loadData();
  }

  // Адмін: пошук юзерів
  void _searchUsersForVerify() {
    final q = _verifySearchController.text.trim();
    if (q.isEmpty) return;
    _bgSocket.emitWithAck('search_users_for_verify', {'adminName': widget.userName, 'query': q}, ack: (dynamic data) {
      if (mounted) setState(() { _verifyResults = List<Map<String, dynamic>>.from(data); });
    });
  }

  void _toggleVerification(String targetName, bool currentlyVerified) {
    final event = currentlyVerified ? 'revoke_verification' : 'grant_verification';
    _bgSocket.emitWithAck(event, {'adminName': widget.userName, 'targetName': targetName}, ack: (dynamic data) {
      if (mounted) {
        _showSnack(data['success'] ? (currentlyVerified ? t('Верифікацію знято', 'Verification revoked') : t('Верифіковано!', 'Verified!')) : (data['message'] ?? 'Error'));
        _searchUsersForVerify(); // оновити список
      }
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
  }

  @override
  void dispose() { _bgSocket.dispose(); _audioPlayer.dispose(); super.dispose(); }

  Widget _buildChatsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
          child: Center(child: AnimatedSearchInput(controller: _searchController, onSubmitted: (_) => _isSearching ? null : _startChat(_searchController.text.trim(), null))),
        ),
        if (_isSearching) const Center(child: Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))),
        Expanded(
          child: _recentChats.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(t("Чатів поки що немає.", "No chats yet."), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
                const SizedBox(height: 4),
                Text(t("Напишіть щось друзям.", "Write something to friends."), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: _recentChats.length,
                separatorBuilder: (context, index) => Padding(padding: const EdgeInsets.only(left: 76.0), child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.05))),
                itemBuilder: (context, index) {
                  final chat = _recentChats[index];
                  final isGroup = chat['isGroup'] == true;
                  final unreadCount = chat['unreadCount'] ?? 0;
                  final isSelf = chat['partnerName'] == widget.userName;
                  final chatVerified = chat['isVerified'] == true;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: GestureDetector(
                      onTap: () => isSelf ? null : _showUserProfile(chat['partnerName'], chat['avatar'], chat['publicKey'], isGroup),
                      child: isSelf
                        ? CircleAvatar(radius: 24, backgroundColor: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.bookmark, color: Colors.white70))
                        : StoryRingAvatar(avatarBase64: chat['avatar'], fallbackName: chat['partnerName'], radius: 24, isGroup: isGroup, hasUnread: unreadCount > 0),
                    ),
                    title: Row(children: [
                      Expanded(child: Text(isSelf ? t("Нотатник", "Saved Messages") : chat['partnerName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: -0.2), overflow: TextOverflow.ellipsis)),
                      if (!isGroup && chatVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
                      if (chat['isPinned'] == true) ...[const SizedBox(width: 4), Icon(Icons.push_pin, color: Colors.white.withValues(alpha: 0.5), size: 14)],
                    ]),
                    subtitle: Text(
                      chat['decryptedText'] ?? (isGroup ? t("Груповий чат", "Group Chat") : t("Почніть чат", "Start chatting")),
                      style: TextStyle(color: unreadCount > 0 ? Colors.white : Colors.white.withValues(alpha: 0.6), fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (chat['lastMessage'] != null) Text(DateFormat('HH:mm').format(DateTime.parse(chat['timestamp']).toLocal()), style: TextStyle(fontSize: 12, color: unreadCount > 0 ? Colors.white : Colors.white.withValues(alpha: 0.5))),
                        const SizedBox(height: 4),
                        if (unreadCount > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50)), child: Text('$unreadCount', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    onLongPress: () => _showChatOptions(chat),
                    onTap: () => _startChat(chat['partnerName'], chat['publicKey'], targetAvatar: chat['avatar'], isVerified: chatVerified),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildFriendsTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 20, bottom: 100),
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("ДОДАТИ ДРУГА", "ADD FRIEND"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: GlassInput(controller: _addFriendController, hintText: t("Нікнейм", "Username"), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))])),
            const SizedBox(width: 10),
            ElegantButton(text: t("ДОДАТИ", "ADD"), onPressed: _sendFriendRequest),
          ]),
        ),
        const SizedBox(height: 32),
        if (_pendingRequests.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("ЗАПИТИ В ДРУЗІ", "REQUESTS"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
          GlassContainer(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: _pendingRequests.asMap().entries.map((entry) {
              int idx = entry.key; var req = entry.value;
              return Column(children: [
                ListTile(
                  leading: GestureDetector(onTap: () => _showUserProfile(req['userName'], req['avatar'], null, false), child: SafeAvatar(avatarBase64: req['avatar'], fallbackName: req['userName'], radius: 20)),
                  title: Row(children: [
                    Text(req['userName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16)),
                    if (req['isVerified'] == 1) ...[const SizedBox(width: 5), const VerifiedBadge(size: 13)],
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(onTap: () => _respondToRequest(req['userName'], 'accept'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50)), child: Text(t("Прийняти", "Accept"), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)))),
                    const SizedBox(width: 8),
                    GestureDetector(onTap: () => _respondToRequest(req['userName'], 'reject'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), border: Border.all(color: Colors.white.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(50)), child: Text(t("Сховати", "Deny"), style: const TextStyle(color: Colors.white, fontSize: 12)))),
                  ]),
                ),
                if (idx != _pendingRequests.length - 1) Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
              ]);
            }).toList()),
          ),
          const SizedBox(height: 24),
        ],
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("ДРУЗІ", "FRIENDS"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
        _friends.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("У вас ще немає друзів.", "No friends yet."), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)))
          : GlassContainer(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: _friends.asMap().entries.map((entry) {
                int idx = entry.key; var f = entry.value;
                return Column(children: [
                  ListTile(
                    leading: GestureDetector(onTap: () => _showUserProfile(f['userName'], f['avatar'], f['publicKey'], false), child: SafeAvatar(avatarBase64: f['avatar'], fallbackName: f['userName'], radius: 20)),
                    title: Row(children: [
                      Text(f['userName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16)),
                      if (f['isVerified'] == true) ...[const SizedBox(width: 5), const VerifiedBadge(size: 13)],
                    ]),
                    onTap: () => _startChat(f['userName'], f['publicKey'], targetAvatar: f['avatar'], isVerified: f['isVerified'] == true),
                  ),
                  if (idx != _friends.length - 1) Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ]);
              }).toList()),
            ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 20, bottom: 100),
      children: [
        Center(
          child: Stack(children: [
            SafeAvatar(avatarBase64: _myAvatar, fallbackName: widget.userName, radius: 46),
            Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _updateAvatar, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF1E1E2C), border: Border.all(color: Colors.black, width: 2), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 14)))),
          ]),
        ),
        const SizedBox(height: 12),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              if (_myVerified) ...[const SizedBox(width: 8), const VerifiedBadge(size: 18)],
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showEditBioDialog,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(_myBio.isEmpty ? t("Додати інформацію про себе", "Add a bio") : _myBio, textAlign: TextAlign.center, style: TextStyle(color: _myBio.isEmpty ? Colors.white.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.7), fontSize: 14, fontStyle: _myBio.isEmpty ? FontStyle.italic : FontStyle.normal))),
                const SizedBox(width: 6),
                Icon(Icons.edit, size: 14, color: Colors.white.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("МОВА", "LANGUAGE"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ListTile(title: const Text("Українська", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), trailing: lang == 'uk' ? const Icon(Icons.check, color: Colors.white) : null, onTap: () => _changeLanguage('uk')),
            Divider(height: 1, indent: 16, color: Colors.white.withValues(alpha: 0.05)),
            ListTile(title: const Text("English", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), trailing: lang == 'en' ? const Icon(Icons.check, color: Colors.white) : null, onTap: () => _changeLanguage('en')),
          ]),
        ),

        // ── Адмін: панель верифікації ──────────────────────────────────────
        if (_isAdmin) ...[
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const VerifiedBadge(size: 14),
              const SizedBox(width: 8),
              Text(t("ВЕРИФІКАЦІЯ АКАУНТІВ", "ACCOUNT VERIFICATION"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1)),
            ]),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: GlassInput(controller: _verifySearchController, hintText: t("Знайти користувача...", "Find user..."), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))])),
              const SizedBox(width: 10),
              ElegantButton(text: t("ЗНАЙТИ", "FIND"), onPressed: _searchUsersForVerify),
            ]),
          ),
          if (_verifyResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassContainer(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _verifyResults.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final user = entry.value;
                  final isVerified = user['isVerified'] == 1;
                  return Column(children: [
                    ListTile(
                      leading: SafeAvatar(fallbackName: user['userName'], radius: 18),
                      title: Row(children: [
                        Text(user['userName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        if (isVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 13)],
                      ]),
                      trailing: GestureDetector(
                        onTap: () => _toggleVerification(user['userName'], isVerified),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: isVerified ? Colors.red.withValues(alpha: 0.12) : const Color(0xFF1DA1F2).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: isVerified ? Colors.red.withValues(alpha: 0.4) : const Color(0xFF1DA1F2).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            isVerified ? t('Зняти', 'Revoke') : t('Верифікувати', 'Verify'),
                            style: TextStyle(color: isVerified ? Colors.red : const Color(0xFF1DA1F2), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    if (idx != _verifyResults.length - 1) Divider(height: 1, indent: 56, color: Colors.white.withValues(alpha: 0.05)),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ],

        const SizedBox(height: 40),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: _logout,
            child: Container(height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(50), border: Border.all(color: Colors.red.withValues(alpha: 0.3))), alignment: Alignment.center, child: Text(t("Вийти з акаунту", "Log Out"), style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 14, fontWeight: FontWeight.w600))),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalUnread = _recentChats.fold(0, (sum, chat) => sum + ((chat['unreadCount'] ?? 0) as int));
    int totalPending = _pendingRequests.length;
    String appBarTitle = _currentIndex == 0 ? t("Чати", "Chats") : (_currentIndex == 1 ? t("Друзі", "Friends") : t("Профіль", "Profile"));
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        title: Text(appBarTitle),
        flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.black.withValues(alpha: 0.5)))),
        actions: _currentIndex == 0 ? [Container(margin: const EdgeInsets.only(right: 16), child: IconButton(icon: const Icon(Icons.group_add, color: Colors.white, size: 24), onPressed: _showCreateGroupDialog))] : null,
      ),
      body: LiquidBackground(child: _currentIndex == 0 ? _buildChatsTab() : (_currentIndex == 1 ? _buildFriendsTab() : _buildSettingsTab())),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 30, right: 30, bottom: 30),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 65,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1), borderRadius: BorderRadius.circular(35)),
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                backgroundColor: Colors.transparent,
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.white.withValues(alpha: 0.4),
                selectedFontSize: 11, unselectedFontSize: 11,
                type: BottomNavigationBarType.fixed, elevation: 0,
                onTap: (index) { setState(() { _currentIndex = index; }); },
                items: [
                  BottomNavigationBarItem(icon: Badge(isLabelVisible: totalUnread > 0, backgroundColor: Colors.white, textColor: Colors.black, label: Text('$totalUnread'), child: const Icon(Icons.chat_bubble)), label: t("Чати", "Chats")),
                  BottomNavigationBarItem(icon: Badge(isLabelVisible: totalPending > 0, backgroundColor: Colors.white, textColor: Colors.black, label: Text('$totalPending'), child: const Icon(Icons.people)), label: t("Друзі", "Friends")),
                  BottomNavigationBarItem(icon: const Icon(Icons.settings_outlined), label: t("Профіль", "Profile")),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ЧАТ ЕКРАН
// ─────────────────────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String deviceId, userName, myPublicKey, partnerName, partnerPublicKey;
  final String? partnerAvatar;
  final bool partnerIsVerified;
  final List<Map<String, dynamic>> friends;

  const ChatScreen({
    super.key, required this.deviceId, required this.userName,
    required this.myPublicKey, required this.partnerName,
    required this.partnerPublicKey, this.partnerAvatar,
    this.partnerIsVerified = false,
    this.friends = const [],
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late io.Socket socket;
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _c = TextEditingController();
  final TextEditingController _searchBarController = TextEditingController();
  final AesGcm _aes = AesGcm.with256bits();
  final _storage = const FlutterSecureStorage();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FocusNode _chatFocusNode = FocusNode();

  bool _isRecordingAudio = false;
  bool _isPartnerTyping = false;
  bool _isPartnerOnline = false;
  bool _isCheckingPresence = true;
  bool _isLoadingHistory = true;
  bool _isAetherMode = false;
  bool _isSearchMode = false;

  String _searchQuery = '';
  List<int> _searchMatchIndices = [];
  int _currentSearchIdx = -1;

  final Map<String, SecretKey> _keyCache = {};
  final Map<String, Map<String, List<String>>> _reactions = {};
  final ScrollController _scrollController = ScrollController();

  Timer? _typingTimer;
  late String _currentPartnerKey;
  Map<String, dynamic>? _replyingTo;
  Map<String, dynamic>? _editingMessage;
  bool _hasText = false;

  StreamSubscription<Amplitude>? _amplitudeSub;
  List<double> _recordAmplitudes = [];
  int _recordDuration = 0;
  Timer? _recordTimer;
  late Color _partnerColor;

  @override
  void initState() {
    super.initState();
    _partnerColor = getProminentColor(widget.partnerAvatar);
    _currentPartnerKey = widget.partnerPublicKey;
    currentActiveChat = widget.partnerPublicKey.startsWith('GROUP_') ? widget.partnerPublicKey : widget.partnerName;
    _connect();
  }

  Future<SecretKey> _getSecretKey(String remotePub) async {
    if (_keyCache.containsKey(remotePub)) return _keyCache[remotePub]!;
    SecretKey finalKey;
    if (remotePub.startsWith('GROUP_')) {
      final hash = await Sha256().hash(utf8.encode(remotePub));
      finalKey = await _aes.newSecretKeyFromBytes(hash.bytes);
    } else {
      final priv = await _storage.read(key: 'private_key');
      final secret = await X25519().sharedSecretKey(
        keyPair: SimpleKeyPairData(base64Decode(priv!), publicKey: SimplePublicKey(base64Decode(widget.myPublicKey), type: KeyPairType.x25519), type: KeyPairType.x25519),
        remotePublicKey: SimplePublicKey(base64Decode(remotePub), type: KeyPairType.x25519),
      );
      finalKey = await _aes.newSecretKeyFromBytes(await secret.extractBytes());
    }
    _keyCache[remotePub] = finalKey;
    return finalKey;
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() { _isRecordingAudio = true; _recordDuration = 0; _recordAmplitudes = List.generate(30, (_) => 2.0); });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _recordDuration++); });
        _amplitudeSub = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 50)).listen((amp) {
          if (mounted) {
            setState(() {
              double height = (amp.current + 50).clamp(0.0, 50.0) / 50.0 * 28.0;
              List<double> newAmps = List.from(_recordAmplitudes);
              newAmps.add(max(2.0, height));
              if (newAmps.length > 30) newAmps.removeAt(0);
              _recordAmplitudes = newAmps;
            });
          }
        });
      }
    } catch (e) { debugPrint("Recording error: $e"); }
  }

  Future<void> _stopRecording() async {
    try {
      _recordTimer?.cancel();
      _amplitudeSub?.cancel();
      final path = await _audioRecorder.stop();
      setState(() => _isRecordingAudio = false);
      if (path != null) { final bytes = await File(path).readAsBytes(); _send(textOverride: base64Encode(bytes), type: 'audio'); }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _processMessage(Map<String, dynamic> msg) async {
    String msgType = msg['type'] ?? 'text';
    if (msgType.startsWith('ephemeral_')) { msg['isEphemeral'] = true; msg['type'] = msgType.replaceFirst('ephemeral_', ''); }
    if (msg['type'] == 'audio') {
      final prefs = await SharedPreferences.getInstance();
      msg['isListened'] = prefs.getBool('listened_${msg['timestamp']}') ?? false;
    }
    if (msg['reactions'] != null) {
      final msgKey = '${msg['timestamp']}_${msg['senderName']}';
      final rawReactions = Map<String, dynamic>.from(msg['reactions']);
      _reactions[msgKey] = rawReactions.map((emoji, users) => MapEntry(emoji, List<String>.from(users)));
    }
    if (msg['ciphertext'] != null) {
      String remotePub = _currentPartnerKey;
      if (!_currentPartnerKey.startsWith('GROUP_')) {
        remotePub = (msg['senderName'] == widget.partnerName) ? (msg['publicKey'] ?? _currentPartnerKey) : _currentPartnerKey;
      }
      try {
        final key = await _getSecretKey(remotePub);
        final box = SecretBox(base64Decode(msg['ciphertext']), nonce: base64Decode(msg['nonce']), mac: Mac(base64Decode(msg['mac'])));
        String dec = utf8.decode(await _aes.decrypt(box, secretKey: key));
        if (dec.startsWith('{') && dec.endsWith('}')) {
          final parsed = jsonDecode(dec);
          msg['text'] = parsed['text'];
          msg['replyTo'] = parsed['replyTo'];
        } else { msg['text'] = dec; }
      } catch (e) { msg['text'] = "Encrypted"; }
    }
    if (msg['senderName'] == widget.partnerName && msg['publicKey'] != null && !msg['publicKey'].toString().startsWith('GROUP_')) {
      _currentPartnerKey = msg['publicKey'];
    }
    if (msg['type'] == 'image' && msg['text'] != null && msg['text'].toString().length > 100) {
      try { msg['imageBytes'] = base64Decode(msg['text']); } catch (_) {}
    }
  }

  void _connect() {
    socket = io.io('https://aether-mu-red.vercel.app/', {'transports': ['websocket'], 'forceNew': true});
    socket.connect();
    socket.onConnect((_) {
      socket.emit('set_active', widget.userName);
      if (!widget.partnerPublicKey.startsWith('GROUP_')) {
        socket.emitWithAck('check_presence', widget.partnerName, ack: (dynamic data) { if (mounted) setState(() { _isPartnerOnline = data['isOnline']; _isCheckingPresence = false; }); });
      } else {
        if (mounted) setState(() { _isCheckingPresence = false; });
      }
      String historyPartner = widget.partnerPublicKey.startsWith('GROUP_') ? widget.partnerPublicKey : widget.partnerName;
      socket.emitWithAck('get_direct_history', {'me': widget.userName, 'partner': historyPartner}, ack: (dynamic data) async {
        List<Map<String, dynamic>> temp = [];
        for (var m in (data as List)) {
          var msgMap = Map<String, dynamic>.from(m);
          await _processMessage(msgMap);
          temp.add(msgMap);
        }
        if (mounted) {
          setState(() { _messages.clear(); _messages.addAll(temp); _isLoadingHistory = false; });
          socket.emit('mark_read', {'chatId': historyPartner, 'readerName': widget.userName});
          WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.jumpTo(_scrollController.position.maxScrollExtent); });
        }
      });
    });

    socket.on('user_presence', (data) { if (data['userName'] == widget.partnerName && mounted) setState(() => _isPartnerOnline = data['isOnline']); });

    socket.on('message', (data) async {
      var msg = Map<String, dynamic>.from(data);
      bool isRelevant = _currentPartnerKey.startsWith('GROUP_')
          ? msg['receiverName'] == _currentPartnerKey
          : ((msg['senderName'] == widget.userName && msg['receiverName'] == widget.partnerName) || (msg['senderName'] == widget.partnerName && msg['receiverName'] == widget.userName));
      if (isRelevant) {
        await _processMessage(msg);
        if (mounted && !_messages.any((m) => m['timestamp'] == msg['timestamp'] && m['senderName'] == msg['senderName'])) {
          setState(() {
            _messages.add(msg);
            if (_isSearchMode && _searchQuery.isNotEmpty) _updateSearchResults();
          });
          WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); });
          if (msg['senderName'] != widget.userName && msg['isEphemeral'] != true) {
            String chatId = _currentPartnerKey.startsWith('GROUP_') ? _currentPartnerKey : msg['senderName'];
            socket.emit('mark_read', {'chatId': chatId, 'readerName': widget.userName});
          }
        }
      }
    });

    socket.on('messages_read', (data) {
      if (mounted) {
        bool changed = false;
        String chatId = data['chatId'] ?? '';
        String reader = data['readerName'] ?? '';
        if ((chatId == _currentPartnerKey || chatId == widget.userName) && reader != widget.userName) {
          for (var m in _messages) { if (m['senderName'] == widget.userName && m['status'] != 'read') { m['status'] = 'read'; changed = true; } }
        }
        if (changed) setState(() {});
      }
    });

    socket.on('message_deleted', (data) { if (mounted) setState(() => _messages.removeWhere((m) => m['timestamp'] == data['timestamp'] && m['senderName'] == data['senderName'])); });

    socket.on('message_edited', (data) async {
      var editedMsgData = Map<String, dynamic>.from(data);
      if (mounted) {
        int idx = _messages.indexWhere((m) => m['timestamp'] == editedMsgData['timestamp'] && m['senderName'] == editedMsgData['senderName']);
        if (idx != -1) {
          _messages[idx]['ciphertext'] = editedMsgData['ciphertext'];
          _messages[idx]['nonce'] = editedMsgData['nonce'];
          _messages[idx]['mac'] = editedMsgData['mac'];
          _messages[idx]['isEdited'] = 1;
          await _processMessage(_messages[idx]);
          setState(() {});
        }
      }
    });

    socket.on('typing', (data) { if (data['senderName'] == widget.partnerName && data['receiverName'] == widget.userName && mounted) setState(() => _isPartnerTyping = data['isTyping']); });

    socket.on('reaction_update', (data) {
      if (!mounted) return;
      final msgKey = '${data['msgTimestamp']}_${data['msgSender']}';
      setState(() {
        _reactions[msgKey] ??= {};
        final emoji = data['emoji'] as String?;
        final reactor = data['reactorName'] as String;
        if (emoji == null) {
          _reactions[msgKey]!.forEach((e, list) => list.remove(reactor));
          _reactions[msgKey]!.removeWhere((_, list) => list.isEmpty);
        } else {
          _reactions[msgKey]!.forEach((e, list) { list.remove(reactor); });
          _reactions[msgKey]!.removeWhere((_, list) => list.isEmpty);
          _reactions[msgKey]![emoji] ??= [];
          if (!_reactions[msgKey]![emoji]!.contains(reactor)) _reactions[msgKey]![emoji]!.add(reactor);
        }
      });
    });
  }

  void _toggleReaction(Map<String, dynamic> msg, String emoji) {
    final msgKey = '${msg['timestamp']}_${msg['senderName']}';
    final myList = _reactions[msgKey]?[emoji] ?? [];
    if (myList.contains(widget.userName)) {
      socket.emit('remove_reaction', {'msgTimestamp': msg['timestamp'], 'msgSender': msg['senderName'], 'reactorName': widget.userName});
    } else {
      socket.emit('add_reaction', {'msgTimestamp': msg['timestamp'], 'msgSender': msg['senderName'], 'reactorName': widget.userName, 'emoji': emoji});
    }
  }

  void _updateSearchResults() {
    _searchMatchIndices = [];
    if (_searchQuery.isEmpty) { _currentSearchIdx = -1; return; }
    for (int i = 0; i < _messages.length; i++) {
      final text = _messages[i]['text']?.toString().toLowerCase() ?? '';
      if (text.contains(_searchQuery.toLowerCase())) _searchMatchIndices.add(i);
    }
    if (_searchMatchIndices.isNotEmpty) {
      _currentSearchIdx = _searchMatchIndices.length - 1;
      _scrollToSearchMatch();
    } else {
      _currentSearchIdx = -1;
    }
  }

  void _scrollToSearchMatch() {
    if (_currentSearchIdx < 0 || _currentSearchIdx >= _searchMatchIndices.length) return;
    if (!_scrollController.hasClients) return;
    final msgIdx = _searchMatchIndices[_currentSearchIdx];
    final total = _messages.length;
    if (total == 0) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final targetScroll = (msgIdx / total) * maxScroll;
    _scrollController.animateTo(targetScroll.clamp(0.0, maxScroll), duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _prevMatch() { if (_searchMatchIndices.isEmpty) return; setState(() { _currentSearchIdx = (_currentSearchIdx - 1 + _searchMatchIndices.length) % _searchMatchIndices.length; }); _scrollToSearchMatch(); }
  void _nextMatch() { if (_searchMatchIndices.isEmpty) return; setState(() { _currentSearchIdx = (_currentSearchIdx + 1) % _searchMatchIndices.length; }); _scrollToSearchMatch(); }

  void _closeSearch() {
    setState(() { _isSearchMode = false; _searchQuery = ''; _searchMatchIndices = []; _currentSearchIdx = -1; _searchBarController.clear(); });
  }

  void _onTextChanged(String text) {
    bool currentHasText = text.trim().isNotEmpty;
    if (_hasText != currentHasText) setState(() { _hasText = currentHasText; });
    socket.emit('typing', {'senderName': widget.userName, 'receiverName': widget.partnerName, 'isTyping': true});
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1500), () { socket.emit('typing', {'senderName': widget.userName, 'receiverName': widget.partnerName, 'isTyping': false}); });
  }

  void _send({String? textOverride, String type = 'text'}) async {
    final text = textOverride ?? _c.text.trim();
    if (text.isEmpty && type == 'text') return;
    final isEditingMode = _editingMessage != null;
    if (type == 'text' && !isEditingMode) { _c.clear(); setState(() { _hasText = false; }); }
    final replyData = _replyingTo != null ? {'senderName': _replyingTo!['senderName'] ?? 'Unknown', 'text': _replyingTo!['type'] == 'image' ? t('Фото', 'Image') : (_replyingTo!['type'] == 'audio' ? t('Голосове повідомлення', 'Voice message') : (_replyingTo!['text']?.toString() ?? t('Повідомлення', 'Message')))} : null;
    setState(() { _replyingTo = null; });
    socket.emit('typing', {'senderName': widget.userName, 'receiverName': widget.partnerName, 'isTyping': false});
    final key = await _getSecretKey(_currentPartnerKey);
    String payloadStr = replyData != null ? jsonEncode({'text': text, 'replyTo': replyData}) : text;
    final box = await _aes.encrypt(utf8.encode(payloadStr), secretKey: key);
    String actualType = type;
    if (_isAetherMode) actualType = 'ephemeral_$type';
    if (isEditingMode) {
      socket.emit('edit_message', {'text': text, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'timestamp': _editingMessage!['timestamp'], 'senderName': widget.userName});
      setState(() { _editingMessage = null; });
      _c.clear();
      setState(() { _hasText = false; });
    } else {
      socket.emit('message', {'type': actualType, 'text': text, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': _currentPartnerKey.startsWith('GROUP_') ? _currentPartnerKey : widget.partnerName});
    }
  }

  Future<void> _sendScheduled(DateTime scheduledAt) async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _c.clear();
    setState(() { _hasText = false; });
    final key = await _getSecretKey(_currentPartnerKey);
    final box = await _aes.encrypt(utf8.encode(text), secretKey: key);
    socket.emitWithAck('schedule_message', {
      'type': 'text',
      'senderName': widget.userName,
      'receiverName': _currentPartnerKey.startsWith('GROUP_') ? _currentPartnerKey : widget.partnerName,
      'text': text,
      'ciphertext': base64Encode(box.cipherText),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'publicKey': widget.myPublicKey,
      'scheduledAt': scheduledAt.toUtc().toIso8601String(),
    }, ack: (dynamic response) {
      if (mounted && response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${t("Заплановано на", "Scheduled for")} ${DateFormat('dd.MM HH:mm').format(scheduledAt)}', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ));
      }
    });
  }

  Future<void> _showScheduleDialog() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFB026FF), surface: Color(0xFF1E1E2C))), child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      builder: (ctx, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFB026FF), surface: Color(0xFF1E1E2C))), child: child!),
    );
    if (time == null || !mounted) return;
    final scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (scheduledAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Час вже минув!', 'Time is in the past!'), style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red.shade900, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
      return;
    }
    await _sendScheduled(scheduledAt);
  }

  void _showForwardDialog(Map<String, dynamic> msg) {
    final targetController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.forward, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(t('Переслати повідомлення', 'Forward message'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 16),
                    if (widget.friends.isNotEmpty) ...[
                      Text(t('Друзі', 'Friends'), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.friends.length,
                          itemBuilder: (context, index) {
                            final f = widget.friends[index];
                            return GestureDetector(
                              onTap: () async {
                                Navigator.pop(ctx);
                                final friendKey = f['publicKey'];
                                if (friendKey == null) return;
                                final key = await _getSecretKey(friendKey);
                                final originalText = msg['text'] ?? '';
                                final box = await _aes.encrypt(utf8.encode(originalText), secretKey: key);
                                socket.emit('message', {'type': 'text', 'text': originalText, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': f['userName']});
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t("Переслано до", "Forwarded to")} ${f['userName']}', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  SafeAvatar(avatarBase64: f['avatar'], fallbackName: f['userName'], radius: 24),
                                  const SizedBox(height: 4),
                                  Text(f['userName'], style: const TextStyle(color: Colors.white, fontSize: 11)),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    GlassInput(controller: targetController, hintText: t('Або введіть нікнейм...', 'Or enter username...')),
                    const SizedBox(height: 12),
                    ShineButton(
                      text: t('Переслати', 'Forward'),
                      onPressed: () async {
                        final target = targetController.text.trim();
                        if (target.isEmpty) return;
                        Navigator.pop(ctx);
                        socket.emitWithAck('get_key', target, ack: (dynamic response) async {
                          if (response['success'] == true) {
                            final targetKey = response['publicKey'];
                            final key = await _getSecretKey(targetKey);
                            final originalText = msg['text'] ?? '';
                            final box = await _aes.encrypt(utf8.encode(originalText), secretKey: key);
                            socket.emit('message', {'type': 'text', 'text': originalText, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': target});
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t("Переслано до", "Forwarded to")} $target', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Користувача не знайдено', 'User not found'), style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red.shade900, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 30);
    if (image != null) { _send(textOverride: base64Encode(await image.readAsBytes()), type: 'image'); }
  }

  void _showMessageOptions(Map<String, dynamic> m, bool isMe) {
    if (m['isEphemeral'] == true) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['❤️', '😂', '🔥', '👍', '😮', '🎉', '🤯', '😢'].map((emoji) {
                        final msgKey = '${m['timestamp']}_${m['senderName']}';
                        final isMine = _reactions[msgKey]?[emoji]?.contains(widget.userName) ?? false;
                        return GestureDetector(
                          onTap: () { Navigator.pop(context); _toggleReaction(m, emoji); },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: isMine ? const Color(0xFFB026FF).withValues(alpha: 0.3) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                            child: Text(emoji, style: const TextStyle(fontSize: 26)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                ListTile(leading: const Icon(Icons.reply, color: Colors.white), title: Text(t('Відповісти', 'Reply'), style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() => _replyingTo = m); _chatFocusNode.requestFocus(); }),
                if (isMe && m['type'] == 'text') ...[
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                  ListTile(leading: const Icon(Icons.edit_outlined, color: Colors.white), title: Text(t('Редагувати', 'Edit'), style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() { _editingMessage = m; _replyingTo = null; _c.text = m['text'] ?? ''; _hasText = _c.text.trim().isNotEmpty; }); _chatFocusNode.requestFocus(); }),
                ],
                if (m['type'] == 'text') ...[
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                  ListTile(leading: const Icon(Icons.forward, color: Colors.white), title: Text(t('Переслати', 'Forward'), style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); _showForwardDialog(m); }),
                ],
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                if (isMe) ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)), title: Text(t('Видалити', 'Delete'), style: const TextStyle(color: Color(0xFFFF3B30))), onTap: () { Navigator.pop(context); socket.emit('delete_message', {'timestamp': m['timestamp'], 'senderName': m['senderName']}); }),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChatUserProfile() {
    if (widget.partnerPublicKey.startsWith('GROUP_')) return;
    String? currentBio;
    String? currentAvatar = widget.partnerAvatar;
    bool isVerifiedUser = widget.partnerIsVerified;
    bool fetched = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) {
          if (!fetched) {
            fetched = true;
            socket.emitWithAck('get_user_profile', widget.partnerName, ack: (dynamic data) {
              if (data['success'] == true) setStateSB(() { currentBio = data['bio']; currentAvatar = data['avatar'] ?? currentAvatar; isVerifiedUser = data['isVerified'] == true; });
            });
          }
          return Container(
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SafeAvatar(avatarBase64: currentAvatar, fallbackName: widget.partnerName, radius: 56),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.partnerName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                          if (isVerifiedUser) ...[const SizedBox(width: 8), const VerifiedBadge(size: 22)],
                        ],
                      ),
                      if (currentBio != null && currentBio!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(currentBio!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15)),
                      ],
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    currentActiveChat = null;
    _typingTimer?.cancel();
    socket.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _chatFocusNode.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  String _formatTime(String? isoTime) { if (isoTime == null) return ""; try { return DateFormat('HH:mm').format(DateTime.parse(isoTime).toLocal()); } catch (e) { return ""; } }

  Widget _buildImage(dynamic bytesOrString) {
    final Widget errorWidget = Container(padding: const EdgeInsets.all(12), color: const Color(0xFF222222), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.broken_image, color: Colors.white70), const SizedBox(width: 8), Text(t("Помилка", "Error"), style: const TextStyle(color: Colors.white70))]));
    if (bytesOrString is Uint8List) return Image.memory(bytesOrString, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (ctx, err, stack) => errorWidget);
    return Image.memory(base64Decode(bytesOrString), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (ctx, err, stack) => errorWidget);
  }

  @override
  Widget build(BuildContext context) {
    final isGroupChat = _currentPartnerKey.startsWith('GROUP_');
    final isSelf = widget.partnerName == widget.userName;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        // Кнопка назад без підпису "Back"
        leading: _isSearchMode
          ? Tooltip(message: '', child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _closeSearch))
          : Tooltip(message: '', child: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))),
        flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.black.withValues(alpha: 0.5)))),
        title: _isSearchMode
          ? TextField(
              controller: _searchBarController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(hintText: t('Пошук у чаті...', 'Search in chat...'), hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)), border: InputBorder.none),
              onChanged: (q) { setState(() { _searchQuery = q; _updateSearchResults(); }); },
            )
          : GestureDetector(
              onTap: () { if (!isSelf && !isGroupChat) _showChatUserProfile(); },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  isSelf
                    ? CircleAvatar(radius: 16, backgroundColor: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.bookmark, color: Colors.white70, size: 16))
                    : SafeAvatar(avatarBase64: widget.partnerAvatar, fallbackName: widget.partnerName, radius: 16, isGroup: isGroupChat),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isSelf ? t("Нотатник", "Saved Messages") : widget.partnerName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          if (widget.partnerIsVerified && !isGroupChat && !isSelf) ...[
                            const SizedBox(width: 5),
                            const VerifiedBadge(size: 15),
                          ],
                        ],
                      ),
                      if (!isSelf) ...[
                        if (_isPartnerTyping) Row(mainAxisSize: MainAxisSize.min, children: [Text(t("друкує ", "typing "), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)), const TypingIndicator(color: Colors.white70, size: 3)])
                        else if (isGroupChat) Text(t("Груповий чат", "Group Chat"), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11))
                        else if (_isCheckingPresence) Text(t("оновлення...", "updating..."), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11))
                        else if (_isPartnerOnline) Text(t("в мережі", "online"), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11))
                        else Text(t("не в мережі", "offline"), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        actions: _isSearchMode
          ? [
              if (_searchMatchIndices.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text('${_currentSearchIdx + 1}/${_searchMatchIndices.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)))),
              IconButton(icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white), onPressed: _prevMatch),
              IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white), onPressed: _nextMatch),
            ]
          : [
              if (!isSelf) IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () { setState(() { _isSearchMode = true; }); }),
              if (!isSelf) IconButton(icon: Icon(_isAetherMode ? Icons.local_fire_department : Icons.local_fire_department_outlined, color: _isAetherMode ? const Color(0xFFB026FF) : Colors.white), onPressed: () => setState(() { _isAetherMode = !_isAetherMode; _replyingTo = null; })),
            ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(color: Colors.white.withValues(alpha: 0.1), height: 1)),
      ),
      body: LiquidBackground(
        child: Column(
          children: [
            Expanded(
              child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.only(left: 12, right: 12, top: 20, bottom: _isPartnerTyping ? 60 : 20),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final isMe = m['senderName'] == widget.userName;
                          final timeStr = _formatTime(m['timestamp']);
                          final isImage = m['type'] == 'image';
                          final isAudio = m['type'] == 'audio';
                          final hasReply = m['replyTo'] != null;
                          final isEdited = m['isEdited'] == 1;
                          final isMsgEphemeral = m['isEphemeral'] == true;
                          final isListened = m['isListened'] == true;
                          final msgKey = '${m['timestamp']}_${m['senderName']}';
                          final msgReactions = Map<String, List<String>>.from(_reactions[msgKey] ?? {});
                          final isSearchMatch = _isSearchMode && _searchMatchIndices.isNotEmpty && _searchMatchIndices[_currentSearchIdx] == i;

                          Widget timeAndStatusWidget = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isEdited) Text(t("змінено ", "edited "), style: TextStyle(color: isMsgEphemeral ? const Color(0xFFE5B3FF) : Colors.white.withValues(alpha: 0.5), fontSize: 10, fontStyle: FontStyle.italic)),
                              Text(timeStr, style: TextStyle(color: isMsgEphemeral ? const Color(0xFFE5B3FF) : Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                              if (isMe && !isMsgEphemeral) ...[
                                const SizedBox(width: 4),
                                Icon(m['status'] == 'read' ? Icons.done_all : Icons.check, size: 14, color: m['status'] == 'read' ? const Color(0xFF00C7FF) : Colors.white.withValues(alpha: 0.5)),
                              ],
                              if (isMsgEphemeral) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.local_fire_department, color: Color(0xFFE5B3FF), size: 12)),
                            ],
                          );

                          Widget bubble = TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.elasticOut,
                            builder: (ctx, v, child) => Transform.scale(scale: 0.5 + (v * 0.5), alignment: isMe ? Alignment.bottomRight : Alignment.bottomLeft, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(isMe ? 20 : 6), bottomRight: Radius.circular(isMe ? 6 : 20)),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 2),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                  padding: EdgeInsets.only(left: isImage || isAudio ? 4 : 14, right: isImage || isAudio ? 4 : 14, top: isImage ? 4 : 10, bottom: isImage ? 4 : 10),
                                  decoration: BoxDecoration(
                                    color: isSearchMatch
                                      ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                                      : (isMsgEphemeral ? const Color(0xFFB026FF).withValues(alpha: 0.2) : (isMe ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05))),
                                    border: Border.all(color: isSearchMatch ? const Color(0xFFFFD700) : (isMsgEphemeral ? const Color(0xFFB026FF) : (isMe ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)))),
                                    borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(isMe ? 20 : 6), bottomRight: Radius.circular(isMe ? 6 : 20)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isGroupChat && !isMe) Padding(padding: const EdgeInsets.only(bottom: 2, left: 2), child: Text(m['senderName'] ?? 'Unknown', style: TextStyle(fontSize: 12, color: isMsgEphemeral ? const Color(0xFFE5B3FF) : Colors.white, fontWeight: FontWeight.w600))),
                                      if (hasReply) Container(
                                        margin: const EdgeInsets.only(bottom: 6), width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(color: isMe ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(m['replyTo']['senderName']?.toString() ?? 'Unknown', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                                          const SizedBox(height: 2),
                                          Text(m['replyTo']['text']?.toString() ?? t('Повідомлення', 'Message'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
                                        ]),
                                      ),
                                      if (isAudio)
                                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                          AudioMessagePlayer(
                                            base64Audio: m['text'] ?? '',
                                            isMe: isMe,
                                            isEphemeral: isMsgEphemeral,
                                            showUnreadDot: !isMe && !isListened,
                                            onPlay: () async {
                                              if (!isMe && !isListened) {
                                                setState(() { m['isListened'] = true; });
                                                final prefs = await SharedPreferences.getInstance();
                                                await prefs.setBool('listened_${m['timestamp']}', true);
                                              }
                                            },
                                          ),
                                          const SizedBox(height: 2),
                                          timeAndStatusWidget,
                                        ])
                                      else if (isImage && m['text'] != null && m['text'].toString().length > 100)
                                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                          ClipRRect(borderRadius: BorderRadius.circular(16), child: _buildImage(m['imageBytes'] ?? m['text'])),
                                          const SizedBox(height: 4),
                                          timeAndStatusWidget,
                                        ])
                                      else
                                        Wrap(
                                          alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.end,
                                          children: [
                                            _isSearchMode && _searchQuery.isNotEmpty
                                              ? HighlightedText(text: "${m['text'] ?? ''}   ", query: _searchQuery, baseStyle: TextStyle(color: isMsgEphemeral ? const Color(0xFFE5B3FF) : Colors.white, fontSize: 15))
                                              : Text("${m['text'] ?? ''}   ", style: TextStyle(color: isMsgEphemeral ? const Color(0xFFE5B3FF) : Colors.white, fontSize: 15)),
                                            timeAndStatusWidget,
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );

                          return SwipeToReplyWrapper(
                            messageKey: ValueKey('${m['timestamp']}${m['senderName']}'),
                            onSwipe: () { setState(() { _replyingTo = m; _editingMessage = null; _hasText = _c.text.trim().isNotEmpty; }); _chatFocusNode.requestFocus(); },
                            child: Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onLongPress: () => _showMessageOptions(m, isMe),
                                    child: HoldToRevealWrapper(
                                      isEphemeral: isMsgEphemeral,
                                      onRevealStarted: () { Timer(const Duration(seconds: 5), () { if (mounted) socket.emit('delete_message', {'timestamp': m['timestamp'], 'senderName': m['senderName']}); }); },
                                      child: bubble,
                                    ),
                                  ),
                                  if (msgReactions.isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(top: 3, bottom: 4, left: isMe ? 0 : 8, right: isMe ? 8 : 0),
                                      child: ReactionsBar(reactions: msgReactions, myName: widget.userName, onToggle: (emoji) => _toggleReaction(m, emoji)),
                                    )
                                  else
                                    const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: _isPartnerTyping ? 56.0 : 0.0,
                          curve: Curves.easeOut,
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12, bottom: 8, top: 4),
                              child: GlassContainer(
                                color: Colors.white.withValues(alpha: 0.05),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                borderRadius: 20,
                                child: const TypingIndicator(color: Colors.white, size: 6),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
            ),
            SafeArea(
              child: Column(children: [
                if (_replyingTo != null && !_isAetherMode) _buildReplyBar(),
                if (_editingMessage != null) _buildEditingBar(),
                _buildInputBar(),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
          child: Row(children: [
            const Icon(Icons.reply, color: Colors.white, size: 20), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t("Відповідь", "Reply to")} ${_replyingTo!['senderName'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
              const SizedBox(height: 2),
              Text(_replyingTo!['type'] == 'image' ? t('Фото', 'Image') : (_replyingTo!['type'] == 'audio' ? t('Голосове повідомлення', 'Voice message') : (_replyingTo!['text']?.toString() ?? t('Повідомлення', 'Message'))), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
            ])),
            IconButton(icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withValues(alpha: 0.5)), onPressed: () => setState(() => _replyingTo = null)),
          ]),
        ),
      ),
    );
  }

  Widget _buildEditingBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
          child: Row(children: [
            const Icon(Icons.edit, color: Colors.white, size: 18), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Редагування повідомлення', 'Edit message'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
              const SizedBox(height: 2),
              Text(_editingMessage!['text']?.toString() ?? t('Повідомлення', 'Message'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
            ])),
            IconButton(icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withValues(alpha: 0.5)), onPressed: () { _c.clear(); setState(() { _editingMessage = null; _hasText = false; }); }),
          ]),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final isEditingMode = _editingMessage != null;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border(top: BorderSide(color: _isAetherMode ? const Color(0xFFB026FF).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1), width: 1))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (!isEditingMode && !_isRecordingAudio) Padding(padding: const EdgeInsets.only(bottom: 0), child: GestureDetector(onTap: _pickAndSendImage, child: Icon(Icons.add, color: _isAetherMode ? const Color(0xFFB026FF) : Colors.white, size: 26))),
            if (!_isRecordingAudio) const SizedBox(width: 8),
            Expanded(
              child: _isRecordingAudio
                ? Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: const Color(0xFFFF3B30).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.3))),
                    child: Row(children: [
                      const Icon(Icons.fiber_manual_record, color: Color(0xFFFF3B30), size: 16),
                      const SizedBox(width: 8),
                      Text('${(_recordDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordDuration % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(child: CustomPaint(size: const Size(double.infinity, 30), painter: WaveformPainter(amplitudes: _recordAmplitudes, progress: 1.0, activeColor: const Color(0xFFFF3B30), inactiveColor: const Color(0xFFFF3B30)))),
                      const SizedBox(width: 8),
                      Text(t("Свайп вліво скасувати", "Swipe left to cancel"), style: const TextStyle(color: Colors.white30, fontSize: 10)),
                    ]),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: _isAetherMode ? const Color(0xFF1A0B2E) : Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isAetherMode ? const Color(0xFFB026FF) : Colors.white.withValues(alpha: 0.1))),
                    child: TextField(
                      controller: _c,
                      focusNode: _chatFocusNode,
                      minLines: 1, maxLines: 4,
                      onChanged: _onTextChanged,
                      style: TextStyle(color: _isAetherMode ? const Color(0xFFE5B3FF) : Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: isEditingMode ? t("Змінити...", "Edit...") : (_isAetherMode ? t("Секретне повідомлення...", "Secret message...") : t("Повідомлення...", "Message...")),
                        hintStyle: TextStyle(color: _isAetherMode ? const Color(0xFFB026FF).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.4), fontSize: 15),
                        border: InputBorder.none, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      ),
                    ),
                  ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: (_hasText || isEditingMode)
                ? GestureDetector(
                    onTap: _send,
                    onLongPress: (!isEditingMode && !_isAetherMode) ? _showScheduleDialog : null,
                    child: Container(
                      height: 40, width: 40,
                      decoration: BoxDecoration(color: _isAetherMode ? const Color(0xFFB026FF) : Colors.white, borderRadius: BorderRadius.circular(50)),
                      child: Icon(isEditingMode ? Icons.check : Icons.arrow_upward, color: _isAetherMode ? Colors.white : Colors.black, size: 20),
                    ),
                  )
                : GestureDetector(
                    onLongPress: _startRecording,
                    onLongPressUp: _stopRecording,
                    onLongPressMoveUpdate: (details) {
                      if (details.offsetFromOrigin.dx < -50) { _recordTimer?.cancel(); _amplitudeSub?.cancel(); _audioRecorder.stop(); setState(() => _isRecordingAudio = false); }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 40, width: 40,
                      decoration: BoxDecoration(
                        color: _isRecordingAudio ? const Color(0xFFFF3B30) : Colors.white.withValues(alpha: 0.1),
                        border: Border.all(color: _isRecordingAudio ? const Color(0xFFFF3B30) : Colors.transparent),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Icon(_isRecordingAudio ? Icons.mic : Icons.mic_none, color: _isRecordingAudio ? Colors.white : (_isAetherMode ? const Color(0xFFB026FF) : Colors.white), size: 22),
                    ),
                  ),
            ),
          ]),
        ),
      ),
    );
  }
}