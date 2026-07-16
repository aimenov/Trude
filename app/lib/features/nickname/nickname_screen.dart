import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/storage/identity_providers.dart';
import '../../core/strings.dart';

class NicknameScreen extends ConsumerStatefulWidget {
  const NicknameScreen({super.key});

  @override
  ConsumerState<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends ConsumerState<NicknameScreen> {
  late final TextEditingController _controller;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: ref.read(identityProvider)?.nickname ?? '');
  }

  @override
  void dispose() {
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
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(Strings.appTitle,
                    style: Theme.of(context).textTheme.displaySmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Text(Strings.nicknameTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  maxLength: 16,
                  autofocus: true,
                  decoration:
                      InputDecoration(hintText: Strings.nicknameHint),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _play(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || !_valid ? null : _play,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(Strings.play),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
