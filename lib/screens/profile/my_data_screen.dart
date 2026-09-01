import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../providers/auth_provider.dart';

/// Muestra la información de cuenta que tenemos guardada del usuario
/// (correo, nombre, teléfono, tipo de cuenta, verificación).
///
/// Reemplaza el botón "descargar mis datos", que todavía no tenía un
/// endpoint de exportación detrás: en vez de simularlo con un
/// próximamente, se lee lo que ya vive en [AuthProvider.currentUser] y se
/// muestra tal cual.
class MyDataScreen extends StatelessWidget {
  const MyDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      appBar: AppBar(title: Text('my_data.title'.tr())),
      body: SafeArea(
        child: user == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'my_data.no_session'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.muted),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                children: [
                  Text(
                    'my_data.header'.tr(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'my_data.description'.tr(),
                    style: TextStyle(color: context.colors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  _DataRow(
                    label: 'my_data.email'.tr(),
                    value: user['email'] as String? ?? '—',
                  ),
                  _DataRow(
                    label: 'my_data.name'.tr(),
                    value: user['name'] as String? ?? '—',
                  ),
                  _DataRow(
                    label: 'my_data.phone'.tr(),
                    value: user['phone'] as String? ?? '—',
                  ),
                  _DataRow(
                    label: 'my_data.account_type'.tr(),
                    value: _tipoCuenta(user['user_type'] as String?),
                  ),
                  _DataRow(
                    label: 'my_data.verification_status'.tr(),
                    value: _estadoVerificacion(
                      user['verification_status'] as String?,
                    ),
                  ),
                  _DataRow(
                    label: 'my_data.member_since'.tr(),
                    value: _fecha(user['created_at'] as String?),
                  ),
                ],
              ),
      ),
    );
  }

  String _tipoCuenta(String? tipo) => switch (tipo) {
    'estudiante' => 'my_data.type_estudiante'.tr(),
    'particular' => 'my_data.type_particular'.tr(),
    'negocio' => 'my_data.type_negocio'.tr(),
    _ => '—',
  };

  String _estadoVerificacion(String? estado) => switch (estado) {
    'no_iniciada' => 'my_data.status_no_iniciada'.tr(),
    'pendiente' => 'my_data.status_pendiente'.tr(),
    'aprobada' => 'my_data.status_aprobada'.tr(),
    'rechazada' => 'my_data.status_rechazada'.tr(),
    _ => '—',
  };

  String _fecha(String? isoFecha) {
    if (isoFecha == null) return '—';
    final fecha = DateTime.tryParse(isoFecha);
    if (fecha == null) return '—';
    return DateFormat.yMMMMd().format(fecha);
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
