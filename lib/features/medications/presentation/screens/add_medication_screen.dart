import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
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

  AddMedicationScreen({super.key, this.editingMedicine});

  @override
  ConsumerState<AddMedicationScreen> createState() =>
      _AddMedicationScreenState();
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
      _startDate = DateTime.fromMillisecondsSinceEpoch(
        med.startDate,
        isUtc: true,
      );

      if (med.endDate != null) {
        _endDate = DateTime.fromMillisecondsSinceEpoch(
          med.endDate!,
          isUtc: true,
        );
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
    final result = await repo.getSchedulesForMedicine(
      medicineId: widget.editingMedicine!.id,
    );

    result.fold((failure) {}, (schedules) {
      setState(() {
        _selectedTimes = schedules.map((s) => s.time).toList();
        _frequencyCount = _selectedTimes.length;
        _isLoadingSchedules = false;
      });
    });
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

      final medicineId = _isEditing ? widget.editingMedicine!.id : Uuid().v4();

      final startMidnight = DateTime.utc(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      );
      final endMidnight = _endDate != null
          ? DateTime.utc(_endDate!.year, _endDate!.month, _endDate!.day)
          : null;

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
        final timeStr = index < _selectedTimes.length
            ? _selectedTimes[index]
            : '08:00';
        return Schedule(
          id: Uuid().v4(),
          profileId: activeProfile.id,
          medicineId: medicineId,
          time: timeStr,
        );
      });

      ref.read(medicationFormStateProvider.notifier).state =
          const AsyncValue.loading();

      final Either<dynamic, void> result;
      final isCaretakerForParent =
          activeProfile != null &&
          !activeProfile.isOwner &&
          activeProfile.appCode != null;
      if (isCaretakerForParent) {
        if (_isEditing) {
          final caretakerUpdateUseCase = ref.read(
            caretakerUpdateMedicationUseCaseProvider,
          );
          result = await caretakerUpdateUseCase(
            medicine: medicine,
            schedules: schedules,
          );
        } else {
          final caretakerAddUseCase = ref.read(
            caretakerAddMedicationUseCaseProvider,
          );
          result = await caretakerAddUseCase(
            medicine: medicine,
            schedules: schedules,
          );
        }
      } else {
        if (_isEditing) {
          final updateUseCase = ref.read(updateMedicationUseCaseProvider);
          result = await updateUseCase(
            medicine: medicine,
            schedules: schedules,
          );
        } else {
          final addUseCase = ref.read(addMedicationUseCaseProvider);
          result = await addUseCase(medicine: medicine, schedules: schedules);
        }
      }

      result.fold(
        (failure) {
          ref
              .read(crashlyticsServiceProvider)
              .recordError(
                failure,
                StackTrace.current,
                reason: _isEditing
                    ? 'Failed to update medication'
                    : 'Failed to add medication',
              );
          ref.read(medicationFormStateProvider.notifier).state =
              AsyncValue.error(failure, StackTrace.current);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        },
        (_) async {
          final analytics = ref.read(analyticsServiceProvider);
          if (_isEditing) {
            await analytics.logMedicationUpdated(
              medicine.id,
              medicine.type,
              schedules.length,
            );
          } else {
            await analytics.logMedicationAdded(
              medicine.id,
              medicine.type,
              schedules.length,
            );
          }

          ref.read(medicationFormStateProvider.notifier).state =
              const AsyncValue.data(null);
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
    final colorScheme = Theme.of(context).colorScheme;
    final medTypeConfigState = ref.watch(medTypeConfigProvider);
    final formState = ref.watch(medicationFormStateProvider);
    final isSaving = formState.isLoading;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Medication' : 'Add Medication'),
        backgroundColor: Colors.transparent,
        centerTitle: true,
      ),
      body: medTypeConfigState.when(
        data: (config) {
          final typeConfig = config.getTypeConfig(_selectedType);

          // Autofill standard units
          if (typeConfig != null) {
            if (_selectedDosageUnit == null &&
                typeConfig.dosageUnits.isNotEmpty) {
              _selectedDosageUnit = typeConfig.dosageUnits.first;
            }
            if (_selectedQuantityUnit == null &&
                typeConfig.quantityUnits.isNotEmpty) {
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 8.0,
                      ),
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
        loading: () => Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Error loading configuration: $err')),
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
                        side: BorderSide(
                          color: colorScheme.secondary,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(
                          color: colorScheme.secondary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
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
                      backgroundColor: colorScheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isSaving
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _currentStep < 2
                                ? 'Next'
                                : (_isEditing
                                      ? 'Save Changes'
                                      : 'Add Medication'),
                            style: TextStyle(color: Colors.white, fontSize: 16),
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

  List<Widget> _buildStepContent(
    MedTypeConfig config,
    MedTypeUnit? typeConfig,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final nameFieldBg = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.6)
        : AppColors.cardFill.withValues(alpha: 0.7);

    if (_currentStep == 0) {
      return [
        // Medicine Name Input
        Text('Medication Name', style: Theme.of(context).textTheme.labelLarge),
        SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter medication name'
              : null,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [
            LengthLimitingTextInputFormatter(50),
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s\-\+]')),
          ],
          decoration: InputDecoration(
            hintText: 'Enter name (e.g. Paracetamol)',
          ),
        ),
        SizedBox(height: 24),

        // Visual Grid of Types
        Text('Medication Type', style: Theme.of(context).textTheme.labelLarge),
        SizedBox(height: 12),
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
        SizedBox(height: 24),

        // Dosage & Quantity Inputs (Visually grouped in a card)
        if ((typeConfig?.dosageEnabled ?? true) ||
            (typeConfig?.quantityEnabled ?? true))
          Container(
            decoration: BoxDecoration(
              color: nameFieldBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Dosage Row
                  if (typeConfig?.dosageEnabled ?? true) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Dosage',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: _dosageValueController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: InputDecoration(hintText: 'Value'),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedDosageUnit,
                            items: (typeConfig?.dosageUnits ?? ['mg']).map((
                              unit,
                            ) {
                              return DropdownMenuItem(
                                value: unit,
                                child: Text(unit),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedDosageUnit = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (typeConfig?.quantityEnabled ?? true)
                      SizedBox(height: 20),
                  ],
                  // Quantity Row
                  if (typeConfig?.quantityEnabled ?? true) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Quantity',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: _quantityValueController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: InputDecoration(hintText: 'Value'),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedQuantityUnit,
                            items: (typeConfig?.quantityUnits ?? ['tab']).map((
                              unit,
                            ) {
                              return DropdownMenuItem(
                                value: unit,
                                child: Text(unit),
                              );
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
        SizedBox(height: 24),
      ];
    } else if (_currentStep == 1) {
      return [
        // Top Summary Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: nameFieldBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _nameController.text.trim().isEmpty
                    ? 'Medication'
                    : _nameController.text.trim(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                '  ·  ',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                typeConfig?.displayName ??
                    (_selectedType.isNotEmpty
                        ? _selectedType[0].toUpperCase() + _selectedType.substring(1)
                        : ''),
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Frequency Grid Selector (2x2 Grid)
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
        // Top Summary Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: nameFieldBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_nameController.text.trim().isEmpty ? 'Medication' : _nameController.text.trim()}  ·  ${typeConfig?.displayName ?? (_selectedType.isNotEmpty ? _selectedType[0].toUpperCase() + _selectedType.substring(1) : '')}  ·  $_frequencyOption',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Duration Section
        Text(
          'Duration',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: nameFieldBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              // Start Date
              InkWell(
                onTap: () async {
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Start Date',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          DateFormat('dd/MM/yyyy').format(_startDate),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.secondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: colorScheme.secondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Continuous Toggle
              InkWell(
                onTap: () => setState(() => _isContinuous = !_isContinuous),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Continuous (No End Date)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Checkbox(
                      value: _isContinuous,
                      activeColor: colorScheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _isContinuous = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
              // End Date Picker if not continuous
              if (!_isContinuous) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _endDate ?? _startDate.add(const Duration(days: 7)),
                      firstDate: _startDate,
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() => _endDate = picked);
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'End Date',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _endDate != null
                                ? DateFormat('dd/MM/yyyy').format(_endDate!)
                                : 'Select Date',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.secondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: colorScheme.secondary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Review Section
        Text(
          'Review',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: nameFieldBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildReviewRow(
                'Medication',
                _nameController.text.trim().isEmpty
                    ? '—'
                    : _nameController.text.trim(),
              ),
              _buildReviewDivider(isDark),
              _buildReviewRow(
                'Type',
                typeConfig?.displayName ??
                    (_selectedType.isNotEmpty
                        ? _selectedType[0].toUpperCase() +
                            _selectedType.substring(1)
                        : '—'),
              ),
              if ((typeConfig?.dosageEnabled ?? true) &&
                  _dosageValueController.text.trim().isNotEmpty) ...[
                _buildReviewDivider(isDark),
                _buildReviewRow(
                  'Dosage',
                  '${_dosageValueController.text.trim()} ${_selectedDosageUnit ?? 'mg'}',
                ),
              ],
              if ((typeConfig?.quantityEnabled ?? true) &&
                  _quantityValueController.text.trim().isNotEmpty) ...[
                _buildReviewDivider(isDark),
                _buildReviewRow(
                  'Quantity',
                  '${_quantityValueController.text.trim()} ${_selectedQuantityUnit ?? 'tab'}',
                ),
              ],
              _buildReviewDivider(isDark),
              _buildReviewRow('Frequency', _frequencyOption),
              _buildReviewDivider(isDark),
              _buildReviewRow(
                'Schedule',
                _selectedTimes
                    .map((t) => DateTimeUtils.formatTimeString(t))
                    .join(', '),
              ),
              _buildReviewDivider(isDark),
              _buildReviewRow(
                'Start Date',
                DateFormat('dd-MMM-yyyy').format(_startDate),
              ),
              _buildReviewDivider(isDark),
              _buildReviewRow(
                'Ends',
                _isContinuous
                    ? 'Continuous'
                    : (_endDate != null
                        ? DateFormat('dd-MMM-yyyy').format(_endDate!)
                        : '—'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Active Toggle if in editing mode
        if (_isEditing) ...[
          SwitchListTile(
            title: Text(
              'Active Status',
              style: theme.textTheme.labelLarge,
            ),
            subtitle: Text(
              'Inactive medicines do not appear on dashboard schedule list.',
            ),
            value: _isActive,
            activeColor: colorScheme.secondary,
            onChanged: (val) {
              setState(() => _isActive = val);
            },
          ),
          const SizedBox(height: 32),
        ],
      ];
    }
  }

  Widget _buildReviewRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewDivider(bool isDark) {
    return Divider(
      height: 16,
      thickness: 0.8,
      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
    );
  }
}

class StepIndicator extends StatelessWidget {
  final int currentStep;

  const StepIndicator({super.key, required this.currentStep});

  Widget _buildStepCircle(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = index <= currentStep;
    final isCurrent = index == currentStep;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent
            ? colorScheme.secondary
            : isActive
                ? colorScheme.secondary.withValues(alpha: 0.6)
                : colorScheme.surface,
        border: Border.all(
          color: isCurrent
              ? colorScheme.secondary
              : isActive
                  ? colorScheme.secondary.withValues(alpha: 0.6)
                  : colorScheme.onSurface.withValues(alpha: 0.2),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          color: isActive
              ? Colors.white
              : colorScheme.onSurface.withValues(alpha: 0.5),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildConnectingLine(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPassed = index < currentStep;

    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isPassed
              ? colorScheme.secondary
              : colorScheme.onSurface.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        children: [
          _buildStepCircle(context, 0),
          _buildConnectingLine(context, 0),
          _buildStepCircle(context, 1),
          _buildConnectingLine(context, 1),
          _buildStepCircle(context, 2),
        ],
      ),
    );
  }
}
