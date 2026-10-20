import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../models/user_profile.dart';
import '../widgets/nuvin_mark.dart';

enum AuthMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  final Function(UserProfile profile, bool isNewUser) onAuthenticated;
  final AuthMode initialMode;

  const AuthScreen({
    super.key,
    required this.onAuthenticated,
    this.initialMode = AuthMode.signIn,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthMode _mode;

  // Pre-filled with realistic dummy account
  final TextEditingController _emailController = TextEditingController(text: 'asha.sharma@example.com');
  final TextEditingController _passwordController = TextEditingController(text: 'nuvin2026');

  String _errorMessage = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode nextMode) {
    setState(() {
      _mode = nextMode;
      _errorMessage = '';
    });
  }

  void _loginAsAsha() {
    final profile = UserProfile(
      id: 'asha_sharma',
      phoneE164: '+919876543210',
      displayName: 'Asha Sharma',
      email: 'asha.sharma@nuvin.ai',
      persona: 'elder',
      ageBand: '55-64',
      gender: 'female',
      companionName: 'Nuvin',
      companionGender: 'female',
      preferredTone: 'respectful',
      locale: 'hi-IN',
      wakeWordPhrase: 'Hey Nuvin',
      emergencyContacts: [
        EmergencyContact(
          id: 'ec-1',
          displayName: 'Aarav Sharma (Son)',
          relationship: 'Kin',
          phoneE164: '+919876543211',
        ),
        EmergencyContact(
          id: 'ec-2',
          displayName: 'Dr. Mehta (Cardiologist)',
          relationship: 'Doctor',
          phoneE164: '+919820012345',
        ),
      ],
    );
    widget.onAuthenticated(profile, false);
  }

  void _loginAsRohan() {
    final profile = UserProfile(
      id: 'rohan_mehta',
      phoneE164: '+919811122233',
      displayName: 'Rohan Mehta',
      email: 'rohan.mehta@nuvin.ai',
      persona: 'ear',
      ageBand: '25-34',
      gender: 'male',
      companionName: 'Saathi',
      companionGender: 'female',
      preferredTone: 'friendly',
      locale: 'en-IN',
      wakeWordPhrase: 'Hey Saathi',
      emergencyContacts: [
        EmergencyContact(
          id: 'ec-1',
          displayName: 'Priya (Partner)',
          relationship: 'Kin',
          phoneE164: '+919811122234',
        ),
      ],
    );
    widget.onAuthenticated(profile, false);
  }

  void _submitCredentials() async {
    setState(() => _errorMessage = '');
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Enter your email address and password to continue.');
      return;
    }

    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;
    setState(() => _busy = false);

    if (email.contains('rohan')) {
      _loginAsRohan();
    } else if (email.contains('asha')) {
      _loginAsAsha();
    } else {
      // Custom user matching screenshot
      final profile = UserProfile(
        id: 'member_${DateTime.now().millisecondsSinceEpoch}',
        phoneE164: '+919800000000',
        displayName: 'Nuvin member',
        email: email,
        persona: 'ear',
        ageBand: 'unspecified',
        gender: 'unspecified',
        companionName: 'Nuvin',
        companionGender: 'female',
        preferredTone: 'friendly',
        locale: 'en-IN',
        wakeWordPhrase: 'Hey Nuvin',
        emergencyContacts: const [],
      );
      widget.onAuthenticated(profile, _mode == AuthMode.signUp);
    }
  }

  void _continueWithGoogle() async {
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _busy = false);

    final profile = UserProfile(
      id: 'peeyush_member',
      phoneE164: '+919800000000',
      displayName: 'Nuvin member',
      email: 'peeyush.panthari@gmail.com',
      persona: 'ear',
      ageBand: 'unspecified',
      gender: 'unspecified',
      companionName: 'Nuvin',
      companionGender: 'female',
      preferredTone: 'friendly',
      locale: 'en-IN',
      wakeWordPhrase: 'Hey Nuvin',
      emergencyContacts: const [],
    );
    widget.onAuthenticated(profile, _mode == AuthMode.signUp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvinColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Brand Row
                  Row(
                    children: [
                      const NuvinMark(size: 42),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'nuvin',
                              style: TextStyle(
                                fontFamily: 'serif',
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                color: NuvinColors.text,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'A little more support, on your terms.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: NuvinColors.mutedForeground,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Main Card Container matching serene design
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
                    decoration: BoxDecoration(
                      color: NuvinColors.card,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: NuvinColors.border, width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Eyebrow
                        const Text(
                          'YOUR PRIVATE SPACE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: NuvinColors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Title with Serif font
                        Text(
                          _mode == AuthMode.signIn ? 'Welcome back' : 'Create your account',
                          style: const TextStyle(
                            fontFamily: 'serif',
                            fontSize: 30,
                            fontWeight: FontWeight.w400,
                            color: NuvinColors.text,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Subtitle
                        Text(
                          _mode == AuthMode.signIn
                              ? 'Sign in to continue with your companion.'
                              : 'Set up an account to return to Nuvin on this device.',
                          style: const TextStyle(
                            fontSize: 14,
                            color: NuvinColors.mutedForeground,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Quick 1-Tap Demo Account Buttons
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: NuvinColors.background.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: NuvinColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.auto_awesome, size: 14, color: NuvinColors.accent),
                                  SizedBox(width: 6),
                                  Text(
                                    'QUICK PREVIEW ACCOUNTS:',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: NuvinColors.accent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _demoAccountPill(
                                      name: 'Asha (62)',
                                      role: 'Elder Mode',
                                      icon: Icons.person_outline_rounded,
                                      color: NuvinColors.tealHighlight,
                                      onTap: _loginAsAsha,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _demoAccountPill(
                                      name: 'Rohan (29)',
                                      role: 'Ear Mode',
                                      icon: Icons.headphones_outlined,
                                      color: NuvinColors.accent,
                                      onTap: _loginAsRohan,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Segmented Control (Sign in vs Create account)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: NuvinColors.background,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: NuvinColors.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _segmentButton(
                                  label: 'Sign in',
                                  selected: _mode == AuthMode.signIn,
                                  onTap: () => _switchMode(AuthMode.signIn),
                                ),
                              ),
                              Expanded(
                                child: _segmentButton(
                                  label: 'Create account',
                                  selected: _mode == AuthMode.signUp,
                                  onTap: () => _switchMode(AuthMode.signUp),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Continue with Google Button
                        InkWell(
                          onTap: _continueWithGoogle,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: NuvinColors.background,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: NuvinColors.border, width: 1.0),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'G',
                                    style: TextStyle(
                                      color: Color(0xFF1A1A1A),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: NuvinColors.text,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Divider (or with email)
                        Row(
                          children: const [
                            Expanded(child: Divider(color: NuvinColors.border, thickness: 1)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'or with email',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: NuvinColors.mutedForeground,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: NuvinColors.border, thickness: 1)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Email Field
                        const Text(
                          'Email address',
                          style: TextStyle(
                            color: NuvinColors.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        _formInput(
                          controller: _emailController,
                          hint: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 14),

                        // Password Field
                        const Text(
                          'Password',
                          style: TextStyle(
                            color: NuvinColors.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        _formInput(
                          controller: _passwordController,
                          hint: 'Enter your password',
                          obscureText: true,
                          onSubmitted: (_) => _submitCredentials(),
                        ),

                        // Error text
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage,
                            style: const TextStyle(
                              color: NuvinColors.destructive,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Submit Button (Matching Intro warm cream pill button)
                        InkWell(
                          onTap: _busy ? null : _submitCredentials,
                          borderRadius: BorderRadius.circular(28),
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              color: NuvinColors.primary,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _busy
                                ? const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: NuvinColors.primaryForeground,
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _mode == AuthMode.signIn ? 'Sign in' : 'Create account',
                                        style: const TextStyle(
                                          color: NuvinColors.primaryForeground,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: NuvinColors.primaryForeground,
                                        size: 19,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Footer Note
                        const Text(
                          'Your memories and personal setup stay on this\ndevice.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: NuvinColors.mutedForeground,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
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
    );
  }

  Widget _demoAccountPill({
    required String name,
    required String role,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    role,
                    style: const TextStyle(
                      color: Color(0xFFAAB7C9),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? NuvinColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? NuvinColors.primaryForeground : NuvinColors.mutedForeground,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _formInput({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onSubmitted,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: NuvinColors.input,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvinColors.border, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(color: NuvinColors.text, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: NuvinColors.mutedForeground.withOpacity(0.55), fontSize: 14),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}
