import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/crashlytics_service.dart';
import '../../../../core/services/performance_service.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../domain/entities/medicine.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/med_type_config.dart';
import '../providers/medications_provider.dart';
import '../widgets/type_selector.dart';
import '../widgets/frequency_selector.dart';
import '../widgets/time_slot_picker.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../settings/presentation/services/reminder_scheduler.dart';
import '../../../caretaker_medication/presentation/providers/caretaker_medications_provider.dart';

class AddMedicationScreen extends ConsumerStatefulWidget {
  final Medicine? editingMedicine;

  const AddMedicationScreen({super.key, this.editingMedicine});

  @override
  ConsumerState<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends ConsumerState<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageValueController = TextEditingController();
  final _quantityValueController = TextEditingController();

  // Wizard Step tracking
  int _currentStep = 0;

  // State fields
  String _selectedType = 'tablet';
  String? _selectedDosageUnit;
  String? _selectedQuantityUnit;
  String _frequencyOption = 'Once a Day';
  int _frequencyCount = 1;
  List<String> _selectedTimes = ['08:00'];
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _isContinuous = true;
  bool _isActive = true;

  bool _isEditing = false;
  bool _isLoadingSchedules = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.editingMedicine != null;
    
    if (_isEditing) {
      final med = widget.editingMedicine!;
      _nameController.text = med.name;
      _selectedType = med.type;
      
      if (med.dosageValue != null) {
        _dosageValueController.text = med.dosageValue.toString();
      }
      _selectedDosageUnit = med.dosageUnit;

      if (med.quantityValue != null) {
        _quantityValueController.text = med.quantityValue.toString();
      }
      _selectedQuantityUnit = med.quantityUnit;

      _frequencyOption = med.frequency;
      _startDate = DateTime.fromMillisecondsSinceEpoch(med.startDate, isUtc: true);
      
      if (med.endDate != null) {
        _endDate = DateTime.fromMillisecondsSinceEpoch(med.endDate!, isUtc: true);
        _isContinuous = false;
      } else {
        _isContinuous = true;
      }
      
      _isActive = med.active;

      _loadEditingSchedules();
    }
  }

  Future<void> _loadEditingSchedules() async {
    setState(() => _isLoadingSchedules = true);
    
    final repo = ref.read(medicationRepositoryProvider);
    final result = await repo.getSchedulesForMedicine(medicineId: widget.editingMedicine!.id);
    
    result.fold(
      (failure) {},
      (schedules) {
        setState(() {
          _selectedTimes = schedules.map((s) => s.time).toList();
          _frequencyCount = _selectedTimes.length;
          _isLoadingSchedules = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageValueController.dispose();
    _quantityValueController.dispose();
    super.dispose();
  }

  void _updateFrequencyCount(int count) {
    setState(() {
      _frequencyCount = count;
      
      // Sync size of _selectedTimes to match the new count
      if (_selectedTimes.length < count) {
        final currentLen = _selectedTimes.length;
        for (int i = currentLen; i < count; i++) {
          if (i == 1) {
            _selectedTimes.add('14:00');
          } else if (i == 2) {
            _selectedTimes.add('20:00');
          } else {
            _selectedTimes.add('08:00');
          }
        }
      } else if (_selectedTimes.length > count) {
        _selectedTimes = _selectedTimes.sublist(0, count);
      }
    });
  }

  void _onSave() async {
    if (_formKey.currentState!.validate()) {
      final activeProfile = ref.read(activeProfileProvider);
      if (activeProfile == null) return;

      final name = _nameController.text.trim();
      final dosageVal = double.tryParse(_dosageValueController.text);
      final quantityVal = double.tryParse(_quantityValueController.text);

      final medicineId = _isEditing ? widget.editingMedicine!.id : const Uuid().v4();

      final startMidnight = DateTime.utc(_startDate.year, _startDate.month, _startDate.day);
      final endMidnight = _endDate != null ? DateTime.utc(_endDate!.year, _endDate!.month, _endDate!.day) : null;

      final medicine = Medicine(
        id: medicineId,
        profileId: activeProfile.id,
        name: name,
        type: _selectedType,
        dosageValue: dosageVal,
        dosageUnit: _selectedDosageUnit,
        quantityValue: quantityVal,
        quantityUnit: _selectedQuantityUnit,
        frequency: _frequencyOption,
        startDate: startMidnight.millisecondsSinceEpoch,
        endDate: _isContinuous ? null : endMidnight?.millisecondsSinceEpoch,
        notes: null,
        active: _isActive,
      );

      final List<Schedule> schedules = List.generate(_frequencyCount, (index) {
        final timeStr = index < _selectedTimes.length ? _selectedTimes[index] : '08:00';
        return Schedule(
          id: const Uuid().v4(),
          profileId: activeProfile.id,
          medicineId: medicineId,
          time: timeStr,
        );
      });

      ref.read(medicationFormStateProvider.notifier).state = const AsyncValue.loading();
      
      final Either<dynamic, void> result;
      final isCaretakerForParent = activeProfile != null && !activeProfile.isOwner && activeProfile.appCode != null;
      if (isCaretakerForParent) {
        if (_isEditing) {
          final caretakerUpdateUseCase = ref.read(caretakerUpdateMedicationUseCaseProvider);
          result = await caretakerUpdateUseCase(medicine: medicine, schedules: schedules);
        } else {
          final caretakerAddUseCase = ref.read(caretakerAddMedicationUseCaseProvider);
          result = await caretakerAddUseCase(medicine: medicine, schedules: schedules);
        }
      } else {
        if (_isEditing) {
          final updateUseCase = ref.read(updateMedicationUseCaseProvider);
          result = await updateUseCase(medicine: medicine, schedules: schedules);
        } else {
          final addUseCase = ref.read(addMedicationUseCaseProvider);
          result = await addUseCase(medicine: medicine, schedules: schedules);
        }
      }

      result.fold(
        (failure) {
          ref.read(crashlyticsServiceProvider).recordError(
            failure,
            StackTrace.current,
            reason: _isEditing ? 'Failed to update medication' : 'Failed to add medication',
          );
          ref.read(medicationFormStateProvider.notifier).state = AsyncValue.error(failure, StackTrace.current);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.message), backgroundColor: AppColors.red),
          );
        },
        (_) async {
          final analytics = ref.read(analyticsServiceProvider);
          if (_isEditing) {
            await analytics.logMedicationUpdated(medicine.id, medicine.type, schedules.length);
          } else {
            await analytics.logMedicationAdded(medicine.id, medicine.type, schedules.length);
          }

          ref.read(medicationFormStateProvider.notifier).state = const AsyncValue.data(null);
          // Refresh dashboard list
          ref.invalidate(homeDosesProvider);
          ref.read(medicinesListProvider.notifier).refresh();
          await ref.read(reminderSchedulerProvider).rescheduleAll();
          if (mounted) {
            context.pop();
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final medTypeConfigState = ref.watch(medTypeConfigProvider);
    final formState = ref.watch(medicationFormStateProvider);
    final isSaving = formState.isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Medication' : 'Add Medication'),
        backgroundColor: AppColors.transparent,
        centerTitle: true,
      ),
      body: medTypeConfigState.when(
        data: (config) {
          final typeConfig = config.getTypeConfig(_selectedType);
          
          // Autofill standard units
          if (typeConfig != null) {
            if (_selectedDosageUnit == null && typeConfig.dosageUnits.isNotEmpty) {
              _selectedDosageUnit = typeConfig.dosageUnits.first;
            }
            if (_selectedQuantityUnit == null && typeConfig.quantityUnits.isNotEmpty) {
              _selectedQuantityUnit = typeConfig.quantityUnits.first;
            }
          }

          return SafeArea(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  StepIndicator(currentStep: _currentStep),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildStepContent(config, typeConfig),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading configuration: $err')),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Row(
            children: [
              if (_currentStep > 0) ...[
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: isSaving
                          ? null
                          : () {
                              setState(() => _currentStep--);
                            },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.accent, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Back',
                        style: TextStyle(color: AppColors.accent, fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () {
                            if (_currentStep < 2) {
                              if (_formKey.currentState!.validate()) {
                                setState(() => _currentStep++);
                              }
                            } else {
                              _onSave();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: isSaving
                        ? const CircularProgressIndicator(color: AppColors.white)
                        : Text(
                            _currentStep < 2
                                ? 'Next'
                                : (_isEditing ? 'Save Changes' : 'Add Medication'),
                            style: const TextStyle(color: AppColors.white, fontSize: 16),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStepContent(MedTypeConfig config, MedTypeUnit? typeConfig) {
    if (_currentStep == 0) {
      return [
        // Medicine Name Input
        const Text('Medication Name', style: AppTextStyles.labelLarge),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          validator: (value) => value == null || value.trim().isEmpty ? 'Enter medication name' : null,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [
            LengthLimitingTextInputFormatter(50),
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s\-\+]')),
          ],
          decoration: const InputDecoration(hintText: 'Enter name (e.g. Paracetamol)'),
        ),
        const SizedBox(height: 24),

        // Visual Grid of Types
        const Text('Medication Type', style: AppTextStyles.labelLarge),
        const SizedBox(height: 12),
        TypeSelector(
          config: config,
          selectedTypeId: _selectedType,
          onTypeSelected: (id) {
            setState(() {
              _selectedType = id;
              _selectedDosageUnit = null;
              _selectedQuantityUnit = null;
            });
          },
        ),
        const SizedBox(height: 24),

        // Dosage & Quantity Inputs (Visually grouped in a card)
        if ((typeConfig?.dosageEnabled ?? true) || (typeConfig?.quantityEnabled ?? true))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Dosage Row
                  if (typeConfig?.dosageEnabled ?? true) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Dosage', style: AppTextStyles.labelLarge),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: _dosageValueController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                            ],
                            decoration: const InputDecoration(hintText: 'Value'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedDosageUnit,
                            items: (typeConfig?.dosageUnits ?? ['mg']).map((unit) {
                              return DropdownMenuItem(value: unit, child: Text(unit));
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedDosageUnit = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (typeConfig?.quantityEnabled ?? true)
                      const SizedBox(height: 20),
                  ],
                  // Quantity Row
                  if (typeConfig?.quantityEnabled ?? true) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Quantity', style: AppTextStyles.labelLarge),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: _quantityValueController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                            ],
                            decoration: const InputDecoration(hintText: 'Value'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedQuantityUnit,
                            items: (typeConfig?.quantityUnits ?? ['tab']).map((unit) {
                              return DropdownMenuItem(value: unit, child: Text(unit));
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedQuantityUnit = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
      ];
    } else if (_currentStep == 1) {
      return [
        // Frequency Dropdown Selector
        FrequencySelector(
          initialFrequencyOption: _frequencyOption,
          initialCustomCount: _frequencyCount,
          onFrequencyChanged: (option, count) {
            setState(() {
              _frequencyOption = option;
            });
            _updateFrequencyCount(count);
          },
        ),
        const SizedBox(height: 24),

        // Time Slot picker
        if (_isLoadingSchedules)
          const Center(child: CircularProgressIndicator())
        else
          TimeSlotPicker(
            slotCount: _frequencyCount,
            selectedTimes: _selectedTimes,
            onTimesChanged: (times) {
              setState(() {
                _selectedTimes = times;
              });
            },
          ),
        const SizedBox(height: 24),
      ];
    } else {
      return [
        // Duration Picker: Start & End Date
        const Text('Duration', style: AppTextStyles.labelLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Start Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Start Date', style: AppTextStyles.bodyMedium),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime(2026),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setState(() => _startDate = picked);
                        }
                      },
                      child: Text(DateFormat('dd-MMM-yyyy').format(_startDate)),
                    ),
                  ],
                ),
                const Divider(height: 16),
                // Continuous Toggle
                CheckboxListTile(
                  title: const Text('Continuous (No End Date)', style: AppTextStyles.bodyMedium),
                  value: _isContinuous,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _isContinuous = val);
                    }
                  },
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: EdgeInsets.zero,
                ),
                // End Date Picker if not continuous
                if (!_isContinuous) ...[
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('End Date', style: AppTextStyles.bodyMedium),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate ?? _startDate.add(const Duration(days: 7)),
                            firstDate: _startDate,
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _endDate = picked);
                          }
                        },
                        child: Text(_endDate != null
                            ? DateFormat('dd-MMM-yyyy').format(_endDate!)
                            : 'Select Date'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Active Toggle if in editing mode
        if (_isEditing) ...[
          SwitchListTile(
            title: const Text('Active Status', style: AppTextStyles.labelLarge),
            subtitle: const Text('Inactive medicines do not appear on dashboard schedule list.'),
            value: _isActive,
            activeColor: AppColors.accent,
            onChanged: (val) {
              setState(() => _isActive = val);
            },
          ),
          const SizedBox(height: 32),
        ],
      ];
    }
  }
}

class StepIndicator extends StatelessWidget {
  final int currentStep;

  const StepIndicator({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          final isActive = index <= currentStep;
          final isCurrent = index == currentStep;
          return Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent
                      ? AppColors.accent
                      : isActive
                          ? AppColors.accent.withOpacity(0.6)
                          : AppColors.cardFill,
                  border: Border.all(
                    color: isCurrent
                        ? AppColors.accent
                        : isActive
                            ? AppColors.accent.withOpacity(0.6)
                            : AppColors.textSecondary.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: isActive ? AppColors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (index < 2)
                Container(
                  width: 60,
                  height: 3,
                  color: index < currentStep
                      ? AppColors.accent
                      : AppColors.textSecondary.withOpacity(0.2),
                ),
            ],
          );
        }),
      ),
    );
  }
}
