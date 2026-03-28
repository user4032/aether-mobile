import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/globals.dart';

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
  final int durationSeconds; // НОВИЙ ПАРАМЕТР

  const HoldToRevealWrapper({
    super.key, 
    required this.child, 
    required this.isEphemeral, 
    this.onRevealStarted,
    this.durationSeconds = 5, // За замовчуванням 5 сек
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
    // Використовуємо переданий час для таймера
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
          
          if (!_hasBeenRevealedOnce)
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
            
          if (_hasBeenRevealedOnce)
            Positioned(
              top: -6, right: -6,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _timerController,
                  builder: (context, child) {
                    final timeLeft = widget.durationSeconds - (_timerController.value * widget.durationSeconds).ceil();
                    if (timeLeft <= 0) return const SizedBox.shrink(); 
                    
                    return Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: Colors.black, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFFFF3B30).withValues(alpha: 0.6), blurRadius: 6)]
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(value: 1.0 - _timerController.value, color: const Color(0xFFFF3B30), backgroundColor: Colors.white.withValues(alpha: 0.1), strokeWidth: 2.5),
                          Text('$timeLeft', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    );
                  }
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

class GlassInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  const GlassInput({super.key, required this.controller, required this.hintText, this.obscureText = false, this.inputFormatters, this.focusNode, this.keyboardType, this.suffixIcon});
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
                suffixIcon: widget.suffixIcon,
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
    final avatarContent = widget.isGroup
        ? Container(
            key: const ValueKey<String>('group_avatar'),
            color: Colors.white.withValues(alpha: 0.08),
            child: Icon(Icons.group, color: Colors.white70, size: widget.radius * 0.9),
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

  Widget _buildFallback() => Container(
    key: ValueKey<String>('fallback_${widget.fallbackName}'),
    color: Colors.white.withValues(alpha: 0.1),
    alignment: Alignment.center,
    child: Text(
      widget.fallbackName.isNotEmpty ? widget.fallbackName[0].toUpperCase() : '?',
      style: TextStyle(color: Colors.white, fontSize: widget.radius * 0.7, fontWeight: FontWeight.w600),
    ),
  );
}

class AetherLoader extends StatefulWidget {
  final double size;
  final Color color;
  const AetherLoader({super.key, this.size = 40, this.color = Colors.white});

  @override
  State<AetherLoader> createState() => _AetherLoaderState();
}

class _AetherLoaderState extends State<AetherLoader> with TickerProviderStateMixin {
  late final AnimationController _motionController;
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _rotationController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() {
    _motionController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_motionController, _rotationController]),
        builder: (context, _) {
          final p = _motionController.value;
          final quarterTurn = ((_rotationController.value * 4).floor() % 4) * (pi / 2);
          final unit = widget.size / 40.0;

          double leftX;
          double rightX;
          double dotY;

          if (p < 0.33) {
            final t = p / 0.33;
            leftX = lerpDouble(12, 2, t)!;
            rightX = lerpDouble(20, 30, t)!;
            dotY = lerpDouble(5, 15, t)!;
          } else if (p < 0.66) {
            leftX = 2;
            rightX = 30;
            final t = (p - 0.33) / 0.33;
            dotY = lerpDouble(15, 30, t)!;
          } else {
            final t = (p - 0.66) / 0.34;
            leftX = lerpDouble(2, 12, t)!;
            rightX = lerpDouble(30, 20, t)!;
            dotY = 30;
          }

          return Transform.rotate(
            angle: quarterTurn,
            child: Stack(
              children: [
                Positioned(
                  left: leftX * unit,
                  top: 16 * unit,
                  child: _bar(16 * unit, 8 * unit),
                ),
                Positioned(
                  left: rightX * unit,
                  top: 16 * unit,
                  child: _bar(16 * unit, 8 * unit),
                ),
                Positioned(
                  left: 15 * unit,
                  top: dotY * unit,
                  child: Container(
                    width: 10 * unit,
                    height: 10 * unit,
                    decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bar(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(height * 0.5),
      ),
    );
  }
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

    _sharedAudioPlayer.onPlayerStateChanged.listen((state) {
      _sharedPlayerState.value = state;
    });
    _sharedAudioPlayer.onDurationChanged.listen((d) {
      _sharedDuration.value = d;
    });
    _sharedAudioPlayer.onPositionChanged.listen((p) {
      _sharedPosition.value = p;
    });
    _sharedAudioPlayer.onPlayerComplete.listen((_) {
      _activeAudioInstance.value = null;
      _sharedPosition.value = Duration.zero;
    });
  }

  void _syncFromShared() {
    if (!mounted) return;
    final isActive = _activeAudioInstance.value == _instanceId;
    final nextIsPlaying = isActive && _sharedPlayerState.value == PlayerState.playing;
    final nextDuration = isActive ? _sharedDuration.value : _duration;
    final nextPosition = isActive ? _sharedPosition.value : (_isPlaying ? Duration.zero : _position);
    if (_isPlaying != nextIsPlaying || _duration != nextDuration || _position != nextPosition) {
      setState(() {
        _isPlaying = nextIsPlaying;
        _duration = nextDuration;
        _position = nextPosition;
      });
    }
  }

  int _computeStableSeed(String data) {
    int hash = 0x811C9DC5;
    for (final b in utf8.encode(data)) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
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
      _position = Duration.zero;
      _duration = Duration.zero;
      _isPlaying = false;
      _waveHeights = _buildWaveHeights(widget.base64Audio);
      if (_activeAudioInstance.value == _instanceId) {
        _activeAudioInstance.value = null;
      }
      _prepareAudio();
    }
  }

  Future<void> _prepareAudio() async {
    try {
      if (_filePath != null) {
        try {
          final prev = File(_filePath!);
          if (await prev.exists()) {
            await prev.delete();
          }
        } catch (_) {}
      }
      final bytes = base64Decode(widget.base64Audio);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/audio_${_computeStableSeed(widget.base64Audio)}.m4a');
      await file.writeAsBytes(bytes);
      if (mounted) {
        _filePath = file.path;
      }
    } catch (e) { debugPrint("Audio load error: $e"); }
  }

  @override
  void dispose() {
    if (_activeAudioInstance.value == _instanceId) {
      _activeAudioInstance.value = null;
    }
    _activeAudioInstance.removeListener(_syncFromShared);
    _sharedPlayerState.removeListener(_syncFromShared);
    _sharedDuration.removeListener(_syncFromShared);
    _sharedPosition.removeListener(_syncFromShared);
    if (_filePath != null) { try { final f = File(_filePath!); if (f.existsSync()) f.deleteSync(); } catch (e) { debugPrint('Error deleting file'); } }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTheme = widget.themeColor != null && ThemeData.estimateBrightnessForColor(widget.themeColor!) == Brightness.dark
      ? Colors.white
      : Colors.black;
    final color = widget.isEphemeral
      ? const Color(0xFFE5B3FF)
      : (widget.isMe ? Colors.black : (widget.themeColor != null ? onTheme : Colors.white));
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