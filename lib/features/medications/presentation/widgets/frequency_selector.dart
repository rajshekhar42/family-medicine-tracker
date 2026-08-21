import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';

class MaxValueTextInputFormatter extends TextInputFormatter {
  final int max;

  MaxValueTextInputFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final int? value = int.tryParse(newValue.text);
    if (value == null || value > max) {
      return oldValue;
    }
    return newValue;
  }
}

class FrequencySelector extends StatefulWidget {
  final String initialFrequencyOption;
  final int initialCustomCount;
  final Function(String selectedOption, int count) onFrequencyChanged;

  const FrequencySelector({
    super.key,
    required this.initialFrequencyOption,
    required this.initialCustomCount,
    required this.onFrequencyChanged,
  });

  @override
  State<FrequencySelector> createState() => _FrequencySelectorState();
}

class _FrequencySelectorState extends State<FrequencySelector> {
  late String _selectedOption;
  late int _customCount;
  final _countController = TextEditingController();
  final _countFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.initialFrequencyOption;
    _customCount = _sanitizeCount(_selectedOption, widget.initialCustomCount);
    _countController.text = _customCount.toString();
    _countFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_countFocusNode.hasFocus) {
      _normalizeCountInput();
    }
  }

  void _normalizeCountInput() {
    final parsed = int.tryParse(_countController.text.trim()) ?? _getMinCount(_selectedOption);
    final sanitized = _sanitizeCount(_selectedOption, parsed);
    setState(() {
      _customCount = sanitized;
      _countController.text = sanitized.toString();
    });
    _triggerChange();
  }

  @override
  void dispose() {
    _countFocusNode.removeListener(_onFocusChange);
    _countFocusNode.dispose();
    _countController.dispose();
    super.dispose();
  }

  bool _isCustom(String opt) {
    return opt != 'Once a Day' && opt != '2 times, Daily' && opt != '3 times, Daily';
  }

  bool _isCustomCountOption(String opt) {
    return opt.startsWith('X times');
  }

  int _getMinCount(String option) {
    if (option == 'X times, Daily') return 4;
    return 1;
  }

  int _getMaxCount(String option) {
    if (option == 'X times, Daily') return 24;
    return 99;
  }

  int _sanitizeCount(String option, int count) {
    final min = _getMinCount(option);
    final max = _getMaxCount(option);
    return count.clamp(min, max);
  }

  int _getDefaultCount(String option) {
    switch (option) {
      case 'Once a Day':
      case 'Once a Week':
      case 'Once a Month':
        return 1;
      case '2 times, Daily':
        return 2;
      case '3 times, Daily':
        return 3;
      default:
        return _sanitizeCount(option, _customCount);
    }
  }

  void _triggerChange() {
    final count = _isCustomCountOption(_selectedOption)
        ? _sanitizeCount(_selectedOption, _customCount)
        : _getDefaultCount(_selectedOption);
    widget.onFrequencyChanged(_selectedOption, count);
  }

  void _selectPreset(String option, int count) {
    setState(() {
      _selectedOption = option;
      _customCount = count;
      _countController.text = count.toString();
    });
    widget.onFrequencyChanged(option, count);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.6)
        : AppColors.cardFill.withValues(alpha: 0.7);

    final isCustomSelected = _isCustom(_selectedOption);

    final presets = [
      {'label': 'Once a Day', 'count': 1, 'option': 'Once a Day'},
      {'label': '2 times, Daily', 'count': 2, 'option': '2 times, Daily'},
      {'label': '3 times, Daily', 'count': 3, 'option': '3 times, Daily'},
      {'label': 'Custom', 'count': _customCount, 'option': 'Custom'},
    ];

    final customOptions = const [
      'X times, Daily',
      'Once a Week',
      'X times a Week',
      'Once a Month',
      'X times a Month',
    ];

    final maxAllowed = _getMaxCount(_selectedOption);
    final minAllowed = _getMinCount(_selectedOption);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How often?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: presets.map((p) {
            final isThisCustom = p['option'] == 'Custom';
            final isSelected = isThisCustom
                ? isCustomSelected
                : _selectedOption == p['option'];

            return InkWell(
              onTap: () {
                if (isThisCustom) {
                  if (!isCustomSelected) {
                    final initialCount = _sanitizeCount('X times, Daily', _customCount >= 4 ? _customCount : 4);
                    _selectPreset('X times, Daily', initialCount);
                  }
                } else {
                  _selectPreset(p['option'] as String, p['count'] as int);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.secondary : cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? colorScheme.secondary : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  p['label'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : colorScheme.onSurface,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        // Dropdown shown when Custom is selected
        if (isCustomSelected) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: customOptions.contains(_selectedOption)
                ? _selectedOption
                : 'X times, Daily',
            items: customOptions.map((opt) {
              return DropdownMenuItem(
                value: opt,
                child: Text(opt),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedOption = val;
                  _customCount = _sanitizeCount(val, _customCount);
                  _countController.text = _customCount.toString();
                });
                _triggerChange();
              }
            },
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.repeat, color: colorScheme.secondary),
              filled: true,
              fillColor: cardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colorScheme.secondary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          // Counter text field if 'X times' is selected
          if (_isCustomCountOption(_selectedOption)) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Number of times (X): ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    width: 80,
                    child: TextFormField(
                      controller: _countController,
                      focusNode: _countFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                        MaxValueTextInputFormatter(maxAllowed),
                      ],
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        hintText: _selectedOption == 'X times, Daily' ? '4 - 24' : '> 0',
                        counterText: '',
                        filled: true,
                        fillColor: cardBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: colorScheme.secondary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (val) {
                        if (val.trim().isEmpty) return;
                        final parsed = int.tryParse(val);
                        if (parsed != null) {
                          if (parsed >= minAllowed && parsed <= maxAllowed) {
                            setState(() {
                              _customCount = parsed;
                            });
                            _triggerChange();
                          }
                        }
                      },
                      onEditingComplete: () {
                        _normalizeCountInput();
                        _countFocusNode.unfocus();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
