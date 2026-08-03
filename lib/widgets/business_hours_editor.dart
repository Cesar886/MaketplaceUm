import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

/// Selector de horario de operación por día ('0'=Lunes .. '6'=Domingo, mismo
/// orden que los chips de "días disponibles" de publicar producto). Al activar
/// un día, si ya hay otro día configurado copia su horario (para el caso común
/// de "lunes a jueves igual"); solo hace falta ajustar los días que difieren.
class BusinessHoursEditor extends StatefulWidget {
  const BusinessHoursEditor({
    super.key,
    required this.initialHours,
    required this.onChanged,
  });

  final Map<int, BusinessHoursRange> initialHours;
  final ValueChanged<Map<int, BusinessHoursRange>> onChanged;

  @override
  State<BusinessHoursEditor> createState() => _BusinessHoursEditorState();
}

class _BusinessHoursEditorState extends State<BusinessHoursEditor> {
  static const _dayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  late final Map<int, BusinessHoursRange> _hours = Map.of(widget.initialHours);

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _toggleDay(int day, bool active) async {
    if (!active) {
      setState(() => _hours.remove(day));
      widget.onChanged(Map.of(_hours));
      return;
    }

    // Copiar el horario de otro día ya configurado, si existe.
    final reference = _hours.values.isNotEmpty ? _hours.values.first : null;
    setState(() {
      _hours[day] = reference ??
          const BusinessHoursRange(open: '09:00', close: '18:00');
    });
    widget.onChanged(Map.of(_hours));
  }

  Future<void> _editDayHours(int day) async {
    final current = _hours[day];
    if (current == null) return;

    final openResult = await showTimePicker(
      context: context,
      initialTime: _parseTime(current.open),
      helpText: 'Hora de apertura — ${_dayNames[day]}',
    );
    if (openResult == null || !mounted) return;

    final closeResult = await showTimePicker(
      context: context,
      initialTime: _parseTime(current.close),
      helpText: 'Hora de cierre — ${_dayNames[day]}',
    );
    if (closeResult == null || !mounted) return;

    final open = _formatTime(openResult);
    final close = _formatTime(closeResult);
    final openMinutes = openResult.hour * 60 + openResult.minute;
    final closeMinutes = closeResult.hour * 60 + closeResult.minute;
    if (closeMinutes <= openMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La hora de cierre debe ser posterior a la apertura'),
        ),
      );
      return;
    }

    setState(() => _hours[day] = BusinessHoursRange(open: open, close: close));
    widget.onChanged(Map.of(_hours));
  }

  @override
  Widget build(BuildContext context) {
    final sortedActiveDays = _hours.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 16,
              color: context.colors.muted,
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Horario de atención (opcional)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(7, (day) {
            final selected = _hours.containsKey(day);
            return FilterChip(
              label: Text(
                _dayNames[day].substring(0, 3),
                style: const TextStyle(fontSize: 12),
              ),
              selected: selected,
              showCheckmark: false,
              selectedColor: AppColors.primary.withValues(alpha: 0.12),
              labelStyle: TextStyle(
                color: selected ? AppColors.primary : context.colors.ink,
              ),
              side: BorderSide(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : context.colors.border,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onSelected: (value) => _toggleDay(day, value),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }),
        ),
        if (sortedActiveDays.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...sortedActiveDays.map((day) {
            final range = _hours[day]!;
            return InkWell(
              onTap: () => _editDayHours(day),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        _dayNames[day],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${range.open} – ${range.close}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.muted,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: context.colors.muted,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
