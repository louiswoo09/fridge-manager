import 'dart:async';

import 'package:flutter/material.dart';

// ───────── 날짜 계산 도우미 ─────────

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 월 더하기 (1월 31일 + 1개월 → 2월 마지막 날)
DateTime _addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final year = d.year + (total / 12).floor();
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
}

bool _inRange(DateTime d) => d.year >= 2000 && d.year <= _today().year + 30;

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

String _formatDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} '
    '(${_weekdays[d.weekday - 1]})';

(String, Color) _dDay(DateTime d) {
  final days = _dateOnly(d).difference(_today()).inDays;
  if (days < 0) return ('${days.abs()}일 지남', Colors.grey);
  if (days == 0) return ('D-Day', Colors.red);
  if (days <= 3) return ('D-$days', Colors.red);
  if (days <= 7) return ('D-$days', Colors.orange);
  return ('D-$days', Colors.green);
}

// ───────── 입력 화면에 놓는 한 줄 ─────────

/// 소비기한 한 줄: 누르면 하단 시트가 열림
class ExpirationDateField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool showLabel;

  const ExpirationDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final (dDayText, dDayColor) = _dDay(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '소비기한',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final picked = await showExpirationDateSheet(
              context,
              initial: value,
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(_formatDate(value), style: const TextStyle(fontSize: 15)),
                const Spacer(),
                Text(
                  dDayText,
                  style: TextStyle(
                    color: dDayColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────── 하단 시트 ─────────

/// 완료를 누르면 고른 날짜, 그냥 닫으면 null
Future<DateTime?> showExpirationDateSheet(
  BuildContext context, {
  required DateTime initial,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ExpirationDateSheet(initial: initial),
  );
}

class _ExpirationDateSheet extends StatefulWidget {
  final DateTime initial;

  const _ExpirationDateSheet({required this.initial});

  @override
  State<_ExpirationDateSheet> createState() => _ExpirationDateSheetState();
}

class _ExpirationDateSheetState extends State<_ExpirationDateSheet> {
  late DateTime _date = _dateOnly(widget.initial);
  final TextEditingController _input = TextEditingController();
  String? _inputError;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _set(DateTime d) {
    if (!_inRange(d)) return;
    setState(() => _date = _dateOnly(d));
  }

  void _stepYear(int n) => _set(_addMonths(_date, n * 12));
  void _stepMonth(int n) => _set(_addMonths(_date, n));
  void _stepDay(int n) =>
      _set(DateTime(_date.year, _date.month, _date.day + n));

  /// 8자리 YYYYMMDD / 6자리 YYMMDD / 4자리 MMDD(올해, 지났으면 내년)
  DateTime? _parse(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final today = _today();
    int year, month, day;

    if (digits.length == 8) {
      year = int.parse(digits.substring(0, 4));
      month = int.parse(digits.substring(4, 6));
      day = int.parse(digits.substring(6, 8));
    } else if (digits.length == 6) {
      year = 2000 + int.parse(digits.substring(0, 2));
      month = int.parse(digits.substring(2, 4));
      day = int.parse(digits.substring(4, 6));
    } else if (digits.length == 4) {
      year = today.year;
      month = int.parse(digits.substring(0, 2));
      day = int.parse(digits.substring(2, 4));
    } else {
      return null;
    }

    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    var date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return null; // 2월 30일 등
    if (digits.length == 4 && date.isBefore(today)) {
      date = DateTime(year + 1, month, day);
    }
    return _inRange(date) ? date : null;
  }

  void _applyInput() {
    final date = _parse(_input.text);
    if (date == null) {
      setState(() => _inputError = '잘못된 날짜예요');
      return;
    }
    _input.clear();
    setState(() => _inputError = null);
    FocusScope.of(context).unfocus();
    _set(date);
  }

  void _onInputChanged(String v) {
    if (_inputError != null) setState(() => _inputError = null);
    if (v.replaceAll(RegExp(r'[^0-9]'), '').length == 8) _applyInput();
  }

  Future<void> _openCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(_today().year + 30, 12, 31),
    );
    if (picked != null) _set(picked);
  }

  Widget _unitStepper(String label, void Function(int) step) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RepeatIconButton(icon: Icons.remove, onStep: () => step(-1)),
                const SizedBox(width: 8),
                _RepeatIconButton(icon: Icons.add, onStep: () => step(1)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (dDayText, dDayColor) = _dDay(_date);

    return Padding(
      // 키보드 높이만큼 올리기
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                dDayText,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: dDayColor,
                ),
              ),
              Text(
                _formatDate(_date),
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _unitStepper('${_date.year}년', _stepYear),
                  const SizedBox(width: 8),
                  _unitStepper('${_date.month}월', _stepMonth),
                  const SizedBox(width: 8),
                  _unitStepper('${_date.day}일', _stepDay),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: '소비기한 8자리 숫자를 입력해주세요',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                        isDense: true,
                        border: const OutlineInputBorder(),
                        enabledBorder: _inputError == null
                            ? null
                            : OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                        focusedBorder: _inputError == null
                            ? null
                            : OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error,
                                  width: 2,
                                ),
                              ),
                      ),
                      onChanged: _onInputChanged,
                      onSubmitted: (_) => _applyInput(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => _set(_today()),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('오늘'),
                  ),
                ],
              ),
              if (_inputError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _inputError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _openCalendar,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: const Text('달력에서 고르기'),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 40,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _date),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(72, 40),
                      ),
                      child: const Text('완료'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────── 누르면 한 번, 길게 누르면 계속 ─────────

class _RepeatIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onStep;

  const _RepeatIconButton({required this.icon, required this.onStep});

  @override
  State<_RepeatIconButton> createState() => _RepeatIconButtonState();
}

class _RepeatIconButtonState extends State<_RepeatIconButton> {
  Timer? _timer;

  void _start() {
    widget.onStep();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: 90),
      (_) => widget.onStep(),
    );
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onStep,
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: Container(
        width: 36,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 0.8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(widget.icon, size: 18, color: Colors.grey.shade600),
      ),
    );
  }
}
