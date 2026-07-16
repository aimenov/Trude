import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/storage/identity_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../home/parlor_widgets.dart';

class NicknameScreen extends ConsumerStatefulWidget {
  const NicknameScreen({super.key});

  @override
  ConsumerState<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends ConsumerState<NicknameScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  bool _busy = false;

  // One-shot entrance: the marquee settles in from above, the panel fades up.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: ref.read(identityProvider)?.nickname ?? '');
  }

  @override
  void dispose() {
    _enter.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final len = _controller.text.trim().length;
    return len >= 2 && len <= 16;
  }

  Future<void> _play() async {
    final nickname = _controller.text.trim();
    if (!_valid) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.nicknameInvalid)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).loginAs(nickname);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Strings.loginFailed(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FadeTransition(
                    opacity: fade,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Marquee(enter: fade),
                        const SizedBox(height: 6),
                        const Center(child: BrassFlourish(width: 230)),
                        const SizedBox(height: 24),
                        // Tagline doubles as the field label (italic serif).
                        Text(
                          Strings.nicknameTitle,
                          textAlign: TextAlign.center,
                          style: TrudeType.cardIndex.copyWith(
                            fontStyle: FontStyle.italic,
                            fontSize: 17,
                            color: TrudeColors.textMuted,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ParlorPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _controller,
                                maxLength: 16,
                                autofocus: true,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: TrudeColors.textPrimary,
                                    letterSpacing: 0.5),
                                decoration: InputDecoration(
                                    hintText: Strings.nicknameHint),
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _play(),
                              ),
                              const SizedBox(height: 8),
                              BrassButton(
                                onPressed: _busy || !_valid ? null : _play,
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : Text(Strings.play),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The grand serif marquee: a fanned hand of card backs glowing behind the
/// letterspaced "TRUDE" wordmark.
class _Marquee extends StatelessWidget {
  const _Marquee({required this.enter});

  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Warm candle-pool behind the fan.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 0.9,
                  colors: [
                    TrudeColors.brassBright.withValues(alpha: 0.10),
                    TrudeColors.brassBright.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.12),
                end: Offset.zero,
              ).animate(enter),
              child: const FannedCardBacks(cardWidth: 62),
            ),
          ),
          Text(
            Strings.appTitle.toUpperCase(),
            textAlign: TextAlign.center,
            style: TrudeType.display.copyWith(
              fontSize: 58,
              letterSpacing: 10,
              height: 1.0,
              shadows: [
                Shadow(
                  color: TrudeColors.midnight.withValues(alpha: 0.9),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
                Shadow(
                  color: TrudeColors.midnight.withValues(alpha: 0.7),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
