import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  String _selectedProfileType = 'Parent';

  /// Returns the system's timezone name (e.g. 'IST', 'America/New_York', 'UTC').
  String get _systemTimeZone => DateTime.now().timeZoneName;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onSave() async {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();

      // Save profile using riverpod notifier — timezone automatically set to system timezone
      await ref
          .read(ownerProfileProvider.notifier)
          .createOwnerProfile(
            name: name,
            timeZone: _systemTimeZone,
            profileType: _selectedProfileType,
          );

      // Verify saving status and navigate
      final state = ref.read(ownerProfileProvider);
      if (!state.hasError) {
        if (mounted) {
          context.go(AppConstants.routeHome);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error.toString()),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildProfileTypeOption({
    required String type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedProfileType == type;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedBorderColor = colorScheme.secondary;
    final unselectedBorderColor = isDark ? Colors.white12 : colorScheme.surface;
    final selectedBg = colorScheme.secondary.withValues(alpha: 0.12);
    final unselectedBg = isDark
        ? AppColors.darkCardFill
        : colorScheme.surface.withValues(alpha: 0.5);

    return Semantics(
      label: '$title, $subtitle',
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedProfileType = type;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? selectedBg : unselectedBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? selectedBorderColor : unselectedBorderColor,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.secondary
                      : colorScheme.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : colorScheme.secondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? colorScheme.secondary
                            : (isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary),
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Radio indicator
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.secondary
                        : (isDark
                              ? AppColors.darkTextSecondary.withValues(
                                  alpha: 0.5,
                                )
                              : AppColors.textSecondary.withValues(alpha: 0.5)),
                    width: isSelected ? 6.5 : 2.0,
                  ),
                  color: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ownerProfileState = ref.watch(ownerProfileProvider);
    final isLoading = ownerProfileState.isLoading;

    final cardBg = isDark
        ? AppColors.darkCardFill
        : colorScheme.surface.withValues(alpha: 0.7);
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 28.0,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 16),

                          // ── App Logo ──
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.asset(
                                'assets/icon/main_icon.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Title & Tagline ──
                          Text(
                            'FamilyMediCare',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Never miss a dose — yours or theirs',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: secondaryTextColor,
                              height: 1.3,
                            ),
                          ),

                          const SizedBox(height: 36),

                          // ── Section: Who are we tracking for? ──
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Who are we tracking for?',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Profile Type 1: Myself
                          _buildProfileTypeOption(
                            type: 'Parent',
                            title: 'Myself',
                            subtitle: 'Parent profile · Track my own medicines',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 12),

                          // Profile Type 2: My family
                          _buildProfileTypeOption(
                            type: 'Caretaker',
                            title: 'My family',
                            subtitle:
                                'Caretaker profile · Track medicines for parents, kids, partner',
                            icon: Icons.family_restroom_outlined,
                          ),

                          const SizedBox(height: 28),

                          // ── Section: What should we call you? ──
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'What should we call you?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: secondaryTextColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // ── Name Input Card ──
                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : colorScheme.surface,
                                width: 1.0,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'NAME',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                TextFormField(
                                  controller: _nameController,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Please enter your name';
                                    }
                                    if (value.trim().length > 20) {
                                      return 'Name cannot exceed 20 characters';
                                    }
                                    return null;
                                  },
                                  textCapitalization: TextCapitalization.words,
                                  maxLength: 20,
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(20),
                                  ],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'e.g. Ram',
                                    counterText: '',
                                    hintStyle: TextStyle(
                                      fontSize: 16,
                                      color: secondaryTextColor.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontWeight: FontWeight.w400,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Spacer(),
                          const SizedBox(height: 28),

                          // ── Create Profile Button ──
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: isLoading ? null : _onSave,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.secondary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      'Create profile & start',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
