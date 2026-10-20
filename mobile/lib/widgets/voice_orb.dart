import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/colors.dart';

enum OrbState {
  idle,
  listening,
  thinking,
  speaking,
}

class VoiceOrb extends StatefulWidget {
  final OrbState state;
  final VoidCallback onTap;
  final bool isElder;
  final double size;

  const VoiceOrb({
    super.key,
    required this.state,
    required this.onTap,
    this.isElder = false,
    this.size = 190.0,
  });

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _spinController;
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _updateStateAnimations();
  }

  @override
  void didUpdateWidget(VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateStateAnimations();
    }
  }

  void _updateStateAnimations() {
    if (widget.state == OrbState.speaking) {
      _pulseController.duration = const Duration(milliseconds: 500);
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      _pulseController.duration = const Duration(milliseconds: 1600);
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    }

    if (widget.state == OrbState.thinking) {
      if (!_spinController.isAnimating) _spinController.repeat();
    } else {
      _spinController.stop();
      _spinController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  String _getOrbLabel() {
    if (widget.isElder) {
      switch (widget.state) {
        case OrbState.idle:
          return 'Suniye, main yahin hoon';
        case OrbState.listening:
          return 'Sun rahi hoon…';
        case OrbState.thinking:
          return 'Soch rahi hoon…';
        case OrbState.speaking:
          return 'Aap se baat kar rahi hoon';
      }
    } else {
      switch (widget.state) {
        case OrbState.idle:
          return 'I’m here when you’re ready';
        case OrbState.listening:
          return 'Listening…';
        case OrbState.thinking:
          return 'Thinking…';
        case OrbState.speaking:
          return 'Speaking…';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: widget.size * 1.5,
            height: widget.size * 1.5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer Ripple
                AnimatedBuilder(
                  animation: _rippleController,
                  builder: (context, child) {
                    final rippleScale = 0.8 + (_rippleController.value * 0.6);
                    final rippleOpacity = (1.0 - _rippleController.value) * 0.35;
                    return Transform.scale(
                      scale: rippleScale,
                      child: Container(
                        width: widget.size * 1.25,
                        height: widget.size * 1.25,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: NuvinColors.primary.withOpacity(rippleOpacity),
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Outer ambient decorative ring
                Container(
                  width: widget.size * 1.35,
                  height: widget.size * 1.35,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF1B3150).withOpacity(0.4),
                      width: 1.0,
                    ),
                  ),
                ),

                // Inner ring
                Container(
                  width: widget.size * 1.15,
                  height: widget.size * 1.15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF234468).withOpacity(0.55),
                      width: 1.2,
                    ),
                  ),
                ),

                // Core Glowing Orb Face
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 0.96 + (_pulseController.value * 0.08);
                    final glowSpread = 10.0 + (_pulseController.value * 16.0);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: NuvinColors.primary.withOpacity(0.38),
                              blurRadius: glowSpread * 2,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: NuvinColors.orbCyanLight.withOpacity(0.2),
                              blurRadius: glowSpread,
                              spreadRadius: 1,
                            ),
                          ],
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              NuvinColors.orbCyanLight,
                              NuvinColors.orbCyanMid,
                              NuvinColors.orbTealDark,
                              NuvinColors.orbNavyDeep,
                            ],
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Top highlight glass reflection
                            Positioned(
                              top: widget.size * 0.15,
                              child: Container(
                                width: widget.size * 0.6,
                                height: widget.size * 0.28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.elliptical(widget.size * 0.6, widget.size * 0.28),
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withOpacity(0.35),
                                      Colors.white.withOpacity(0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Orbiting dots during "thinking"
                            if (widget.state == OrbState.thinking)
                              AnimatedBuilder(
                                animation: _spinController,
                                builder: (context, child) {
                                  final angle = _spinController.value * 2 * math.pi;
                                  final r = widget.size * 0.42;
                                  return Stack(
                                    children: [
                                      Positioned(
                                        left: (widget.size / 2) + (r * math.cos(angle)) - 4,
                                        top: (widget.size / 2) + (r * math.sin(angle)) - 4,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: NuvinColors.accent,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: NuvinColors.accent,
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                            // Center Icon
                            Icon(
                              widget.state == OrbState.speaking
                                  ? Icons.volume_up_rounded
                                  : Icons.mic_rounded,
                              size: 34,
                              color: const Color(0xFF09233C),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _getOrbLabel(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: widget.isElder ? 20 : 16,
            fontWeight: FontWeight.w600,
            color: NuvinColors.text,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap the orb to preview voice states',
          style: TextStyle(
            fontSize: 12,
            color: NuvinColors.mutedForeground,
          ),
        ),
      ],
    );
  }
}
