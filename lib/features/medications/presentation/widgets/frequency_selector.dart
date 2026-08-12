import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.initialFrequencyOption;
    _customCount = widget.initialCustomCount;
    _countController.text = _customCount.toString();
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  bool _isCustomOption(String option) {
    return option.startsWith('X times');
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
        return _customCount;
    }
  }

  void _triggerChange() {
    final count = _isCustomOption(_selectedOption) ? _customCount : _getDefaultCount(_selectedOption);
    widget.onFrequencyChanged(_selectedOption, count);
  }

  @override
  Widget build(BuildContext context) {
    final showCustomInput = _isCustomOption(_selectedOption);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Frequency',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedOption,
          items: AppConstants.frequencyOptions.map((opt) {
            return DropdownMenuItem(
              value: opt,
              child: Text(opt),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedOption = val;
              });
              _triggerChange();
            }
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.repeat, color: AppColors.accent),
          ),
        ),
        
        // Counter text field if 'X times' is selected
        if (showCustomInput) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Number of times (X): ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _countController,
                    keyboardType: TextInputType.number,
                    maxLength: 2,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      counterText: '',
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val) ?? 1;
                      setState(() {
                        _customCount = parsed > 0 ? parsed : 1;
                      });
                      _triggerChange();
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
