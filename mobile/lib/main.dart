import 'package:flutter/material.dart';
import 'constants/colors.dart';
import 'models/user_profile.dart';
import 'screens/auth_screen.dart';
import 'screens/welcome_intro_screen.dart';
import 'screens/onboarding_wizard_screen.dart';
import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NuvinApp());
}

class NuvinApp extends StatefulWidget {
  const NuvinApp({super.key});

  @override
  State<NuvinApp> createState() => _NuvinAppState();
}

class _NuvinAppState extends State<NuvinApp> {
  bool _hasSeenIntro = false;
  UserProfile? _currentProfile;
  bool _needsOnboarding = false;
  AuthMode _authInitialMode = AuthMode.signIn;

  @override
  Widget build(BuildContext context) {
    Widget activeScreen;

    if (!_hasSeenIntro && _currentProfile == null) {
      activeScreen = WelcomeIntroScreen(
        onGetStarted: () {
          setState(() {
            _hasSeenIntro = true;
            _authInitialMode = AuthMode.signUp;
          });
        },
        onSkipToLogin: () {
          setState(() {
            _hasSeenIntro = true;
            _authInitialMode = AuthMode.signIn;
          });
        },
      );
    } else if (_currentProfile == null) {
      activeScreen = AuthScreen(
        initialMode: _authInitialMode,
        onAuthenticated: (profile, isNewUser) {
          setState(() {
            _currentProfile = profile;
            _needsOnboarding = isNewUser;
          });
        },
      );
    } else if (_needsOnboarding) {
      activeScreen = OnboardingWizardScreen(
        initialProfile: _currentProfile!,
        onComplete: (updatedProfile) {
          setState(() {
            _currentProfile = updatedProfile;
            _needsOnboarding = false;
          });
        },
        onSkip: () {
          setState(() {
            _needsOnboarding = false;
          });
        },
      );
    } else {
      activeScreen = MainScreen(
        profile: _currentProfile!,
        onSignOut: () {
          setState(() {
            _currentProfile = null;
            _needsOnboarding = false;
            _hasSeenIntro = false;
          });
        },
      );
    }

    return MaterialApp(
      title: 'Nuvin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: NuvinColors.background,
        colorScheme: const ColorScheme.dark(
          primary: NuvinColors.primary,
          secondary: NuvinColors.accent,
          surface: NuvinColors.card,
          error: NuvinColors.destructive,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: activeScreen,
    );
  }
}
