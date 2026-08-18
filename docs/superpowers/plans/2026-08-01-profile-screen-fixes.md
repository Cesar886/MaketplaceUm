# Perfil: arreglos y edición — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the seller-scoping bug in "Mis publicaciones", add profile editing (name/phone/photo), and replace the 3 mock profile options ("Confianza y seguridad", "Planes para destacar", "Ayuda") with real screens.

**Architecture:** Reuse existing backend patterns (`updateSellerField` helper, the generic seller-logo upload endpoint) and existing frontend patterns (the `image_picker` flow already used in business registration, the seller-avatar `Image.network` pattern already used in `home_screen.dart`). No new state-management library, no new backend tables.

**Tech Stack:** Flutter/Dart (Provider for state), Node/Express backend with `better-sqlite3` (via `backend/src/database.js`), `image_picker` for photo selection.

## Global Constraints

- No automated test suite exists for backend routes or for Flutter providers/screens in this repo (`backend/package.json`'s `test` script is a stub; `test/widget_test.dart` is one broad smoke test unrelated to this feature). Do **not** invent a test framework for this feature — verify each task with `flutter analyze`, manual `curl`, and (for task 12) a full release build, matching how the previous profile fix in this codebase was verified.
- Follow existing code style: no doc comments unless explaining non-obvious behavior, Spanish for user-facing strings and existing comments, `AppColors`/`AppShadows` from `lib/app_theme.dart` for styling.
- Every new screen lives under `lib/screens/profile/` (new directory) — one file per screen.

---

### Task 1: Fix `MyListingsScreen` seller-scoping

**Files:**
- Modify: `lib/screens/my_listings_screen.dart`

**Interfaces:**
- Consumes: `ApiService.getProducts({String? seller})` (already exists, returns `Future<List<Product>>`), `AuthProvider.backendSellerId` (already exists, `String?` getter).
- Produces: nothing new consumed by later tasks.

- [ ] **Step 1: Add imports and switch the data source**

In `lib/screens/my_listings_screen.dart`, add the import:

```dart
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
```

Replace the `_loadListings` method:

```dart
  Future<void> _loadListings() async {
    final sellerId = context.read<AuthProvider>().backendSellerId;
    if (sellerId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final listings = await ApiService.getProducts(seller: sellerId);
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/my_listings_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/screens/my_listings_screen.dart
git commit -m "fix(frontend): scope 'Mis publicaciones' to the logged-in seller"
```

---

### Task 2: Backend — `PATCH /api/sellers/:id`

**Files:**
- Modify: `backend/src/routes/sellers.js`

**Interfaces:**
- Consumes: `updateSellerField(sellerId, field, value)` from `backend/src/data.js` (already exists), `requireAuth` middleware from `backend/src/auth.js` (already exists, sets `req.user = { id: sellerId }`).
- Produces: `PATCH /api/sellers/:id` — request body `{ name?: string, phone?: string }`, response `200` with the updated `Seller` JSON object (same shape as `GET /api/sellers/:id`), `403` if the token's owner doesn't match `:id`, `404` if the seller doesn't exist.

- [ ] **Step 1: Add the route**

In `backend/src/routes/sellers.js`, change the top imports:

```js
const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const multer = require('multer');
const { sellers, saveData, updateSellerField } = require('../data');
const { requireAuth } = require('../auth');
```

Add this route inside `function register(app) { ... }`, right after the `GET /api/sellers/:id` route:

```js
  // PATCH /api/sellers/:id — editar nombre/teléfono del propio perfil
  app.patch('/api/sellers/:id', requireAuth, (req, res) => {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });

    const { name, phone } = req.body;
    if (typeof name === 'string' && name.trim()) {
      updateSellerField(seller.id, 'name', name.trim());
      const initials = name.trim().split(/\s+/).map(w => w[0]).slice(0, 2).join('').toUpperCase();
      updateSellerField(seller.id, 'avatarInitials', initials);
    }
    if (typeof phone === 'string') {
      updateSellerField(seller.id, 'phone', phone.trim());
    }

    res.json(sellers.find(s => s.id === req.params.id));
  });
```

- [ ] **Step 2: Verify manually with curl**

Start the backend:
Run: `cd /home/daniel/mercaditoUM/backend && node src/index.js &`
Expected: logs indicating the server is listening (note the port, e.g. `3000`).

Register a throwaway test seller and capture the token + id:

```bash
RESP=$(curl -s -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Plan User","email":"test-plan-user@example.com","phone":"8180000000","userType":"particular"}')
echo "$RESP"
TOKEN=$(echo "$RESP" | node -pe 'JSON.parse(require("fs").readFileSync(0)).token')
SELLER_ID=$(echo "$RESP" | node -pe 'JSON.parse(require("fs").readFileSync(0)).seller.id')
```

Test the happy path:

```bash
curl -s -X PATCH "http://localhost:3000/api/sellers/$SELLER_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Plan User Updated","phone":"8181111111"}'
```
Expected: `200` with JSON showing `"name":"Test Plan User Updated"`, `"phone":"8181111111"`, and `"avatarInitials":"TU"`.

Test the 403 (wrong owner):

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X PATCH "http://localhost:3000/api/sellers/someone-else-id" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Hacked"}'
```
Expected: `403`

Stop the server: `kill %1` (or find the `node src/index.js` PID with `pgrep -f "node src/index.js"` and `kill` it).

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add backend/src/routes/sellers.js
git commit -m "feat(backend): add PATCH /api/sellers/:id to edit name and phone"
```

---

### Task 3: Frontend — `ApiService.updateSellerProfile`

**Files:**
- Modify: `lib/services/api_service.dart`

**Interfaces:**
- Consumes: `_authHeaders` (existing private getter in this file), `_uri(path)` (existing private helper), `Seller.fromJson` (existing).
- Produces: `static Future<Seller> updateSellerProfile({required String sellerId, String? name, String? phone})`.

- [ ] **Step 1: Add the method**

In `lib/services/api_service.dart`, add right after the existing `getSeller` method (around line 391, before `uploadBusinessLogo`):

```dart
  static Future<Seller> updateSellerProfile({
    required String sellerId,
    String? name,
    String? phone,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (phone != null) body['phone'] = phone;
    final res = await _client.patch(
      _uri('/sellers/$sellerId'),
      headers: _authHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw Exception('Error al actualizar perfil');
    return Seller.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/services/api_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/services/api_service.dart
git commit -m "feat(frontend): add ApiService.updateSellerProfile"
```

---

### Task 4: Frontend — `DBHelper.updateUserFields`

**Files:**
- Modify: `lib/services/db_helper.dart`

**Interfaces:**
- Consumes: `database` getter (existing), `users` table schema (existing, has `name` and `phone` columns).
- Produces: `Future<void> updateUserFields(int userId, {String? name, String? phone})`.

- [ ] **Step 1: Add the method**

In `lib/services/db_helper.dart`, add right after `getUserById` (before `getPendingVerifications`):

```dart
  Future<void> updateUserFields(int userId, {String? name, String? phone}) async {
    final db = await database;
    final fields = <String, Object?>{};
    if (name != null) fields['name'] = name;
    if (phone != null) fields['phone'] = phone;
    if (fields.isEmpty) return;
    await db.update('users', fields, where: 'id = ?', whereArgs: [userId]);
  }
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/services/db_helper.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/services/db_helper.dart
git commit -m "feat(frontend): add DBHelper.updateUserFields"
```

---

### Task 5: Frontend — `AuthProvider.updateProfile`

**Files:**
- Modify: `lib/providers/auth_provider.dart`

**Interfaces:**
- Consumes: `ApiService.uploadBusinessLogo({required String sellerId, required String imagePath})` (existing, returns `Future<Seller>`), `ApiService.updateSellerProfile({required String sellerId, String? name, String? phone})` (Task 3), `_db.updateUserFields(int userId, {String? name, String? phone})` (Task 4), `_backendSellerId`, `_currentUser`, `userId` getter (all existing on this class).
- Produces: `Future<void> updateProfile({String? name, String? phone, String? logoPath})`. Throws on network failure (caller must catch).

- [ ] **Step 1: Add the method**

In `lib/providers/auth_provider.dart`, add it right after `_syncBackend` (around line 118), still inside the `AuthProvider` class:

```dart
  /// Actualiza nombre, teléfono y/o foto de perfil, sincronizando
  /// backend y base de datos local. Lanza si falla la llamada de red;
  /// el caller debe capturar y mostrar el error.
  Future<void> updateProfile({String? name, String? phone, String? logoPath}) async {
    if (logoPath != null && _backendSellerId != null) {
      await ApiService.uploadBusinessLogo(
        sellerId: _backendSellerId!,
        imagePath: logoPath,
      );
    }
    if ((name != null || phone != null) && _backendSellerId != null) {
      await ApiService.updateSellerProfile(
        sellerId: _backendSellerId!,
        name: name,
        phone: phone,
      );
    }
    if (name != null || phone != null) {
      await _db.updateUserFields(userId, name: name, phone: phone);
      if (name != null) _currentUser!['name'] = name;
      if (phone != null) _currentUser!['phone'] = phone;
    }
    notifyListeners();
  }
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/providers/auth_provider.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/providers/auth_provider.dart
git commit -m "feat(frontend): add AuthProvider.updateProfile"
```

---

### Task 6: Frontend — `EditProfileScreen`

**Files:**
- Create: `lib/screens/profile/edit_profile_screen.dart`

**Interfaces:**
- Consumes: `AuthProvider.currentUser` (`Map<String, dynamic>?`, existing), `AuthProvider.updateProfile(...)` (Task 5), `ApiService.baseUrl` (existing `String` getter), `Seller.logoUrl` (existing, `String?`, passed in via constructor).
- Produces: `class EditProfileScreen extends StatefulWidget` with constructor `EditProfileScreen({super.key, required this.currentLogoUrl})`. On success pops with `Navigator.pop(context, true)`.

- [ ] **Step 1: Create the screen**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.currentLogoUrl});

  final String? currentLogoUrl;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  XFile? _pickedPhoto;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser!;
    _nameController = TextEditingController(text: user['name'] as String? ?? '');
    _phoneController = TextEditingController(text: user['phone'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked != null) setState(() => _pickedPhoto = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().updateProfile(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            logoPath: _pickedPhoto?.path,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el perfil. Intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Center(
                child: InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(48),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    child: ClipOval(child: _avatarContent()),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text('Cambiar foto'),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'El nombre es obligatorio' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarContent() {
    if (_pickedPhoto != null) {
      return Image.file(
        File(_pickedPhoto!.path),
        width: 96,
        height: 96,
        fit: BoxFit.cover,
      );
    }
    if (widget.currentLogoUrl != null && widget.currentLogoUrl!.isNotEmpty) {
      return Image.network(
        '${ApiService.baseUrl}${widget.currentLogoUrl}',
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.person_rounded, size: 40, color: AppColors.primaryDark),
      );
    }
    return const Icon(Icons.person_rounded, size: 40, color: AppColors.primaryDark);
  }
}
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/profile/edit_profile_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/screens/profile/edit_profile_screen.dart
git commit -m "feat(frontend): add EditProfileScreen for name/phone/photo editing"
```

---

### Task 7: Wire avatar display + edit entry point into `profile_screen.dart`

**Files:**
- Modify: `lib/screens/profile_screen.dart`

**Interfaces:**
- Consumes: `EditProfileScreen` (Task 6), `Seller` (existing model, already returned by `ApiService.getSeller` inside `_loadListings`).
- Produces: `_seller` field of type `Seller?` on `_ProfileScreenState`, readable by Task 11 if needed (not required by later tasks, but keep the field name consistent).

- [ ] **Step 1: Store the fetched `Seller` and show the real avatar**

In `lib/screens/profile_screen.dart`, add a field next to the existing ones:

```dart
  Seller? _seller;
```

In `_loadListings`, store the seller (the method already fetches it — see the code from the previous session):

```dart
      final seller = results[1] as Seller;
      setState(() {
        _listings = results[0] as List<Product>;
        _sellerRating = seller.rating;
        _sellerReviews = seller.reviews;
        _seller = seller;
      });
```

Replace the `CircleAvatar` in the user card (the one showing `initials`) with an avatar that shows the real photo when available, plus an edit pencil button. Replace:

```dart
                      CircleAvatar(
                        radius: 38,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.12),
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 22,
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
```

with:

```dart
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.12),
                            child: ClipOval(
                              child: (_seller?.logoUrl != null &&
                                      _seller!.logoUrl!.isNotEmpty)
                                  ? Image.network(
                                      '${ApiService.baseUrl}${_seller!.logoUrl}',
                                      width: 76,
                                      height: 76,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Text(
                                        initials,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          color: AppColors.primaryDark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      initials,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        color: AppColors.primaryDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final updated = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute<bool>(
                                    builder: (_) => EditProfileScreen(
                                      currentLogoUrl: _seller?.logoUrl,
                                    ),
                                  ),
                                );
                                if (updated == true) _loadListings();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.surface, width: 2),
                                ),
                                child: const Icon(Icons.edit_rounded,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
```

Add the import at the top of the file:

```dart
import 'profile/edit_profile_screen.dart';
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/profile_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/screens/profile_screen.dart
git commit -m "feat(frontend): show real avatar photo and wire profile editing"
```

---

### Task 8: Frontend — `SafetyTipsScreen`

**Files:**
- Create: `lib/screens/profile/safety_tips_screen.dart`

**Interfaces:**
- Consumes: nothing (fully static content).
- Produces: `class SafetyTipsScreen extends StatelessWidget`, no constructor params.

- [ ] **Step 1: Create the screen**

```dart
import 'package:flutter/material.dart';

import '../../app_theme.dart';

class SafetyTipsScreen extends StatelessWidget {
  const SafetyTipsScreen({super.key});

  static const _tips = [
    (
      icon: Icons.verified_user_rounded,
      title: 'Revisa el perfil antes de reunirte',
      body: 'Consulta la calificación y las opiniones del vendedor o '
          'comprador antes de acordar una entrega.',
    ),
    (
      icon: Icons.location_on_rounded,
      title: 'Elige zonas públicas del campus',
      body: 'Acuerda la entrega en lugares concurridos y con buena '
          'iluminación dentro de la universidad, evita sitios aislados.',
    ),
    (
      icon: Icons.search_rounded,
      title: 'Revisa el producto antes de pagar',
      body: 'Verifica que el artículo esté en las condiciones descritas '
          'antes de completar el pago.',
    ),
    (
      icon: Icons.payments_rounded,
      title: 'Desconfía de pagos por adelantado fuera de la app',
      body: 'No transfieras dinero por adelantado a desconocidos ni fuera '
          'de los medios acordados en el chat.',
    ),
    (
      icon: Icons.flag_rounded,
      title: 'Reporta comportamiento sospechoso',
      body: 'Si algo no se siente bien, corta la conversación y repórtalo '
          'desde la opción de ayuda.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confianza y seguridad')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: _tips.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final tip = _tips[index];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(tip.icon, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tip.title,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          tip.body,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/profile/safety_tips_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/screens/profile/safety_tips_screen.dart
git commit -m "feat(frontend): add SafetyTipsScreen with real safety content"
```

---

### Task 9: Frontend — `HighlightPlansScreen`

**Files:**
- Create: `lib/screens/profile/highlight_plans_screen.dart`

**Interfaces:**
- Consumes: `ApiService.getHighlightPlans()` (existing, `Future<List<HighlightPlan>>`), `HighlightPlan` fields `id`, `title`, `price` (`String`), `description`, `days` (`int`) — all existing on the model.
- Produces: `class HighlightPlansScreen extends StatefulWidget`, no constructor params.

- [ ] **Step 1: Create the screen**

```dart
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../services/api_service.dart';

class HighlightPlansScreen extends StatefulWidget {
  const HighlightPlansScreen({super.key});

  @override
  State<HighlightPlansScreen> createState() => _HighlightPlansScreenState();
}

class _HighlightPlansScreenState extends State<HighlightPlansScreen> {
  List<HighlightPlan> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await ApiService.getHighlightPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planes para destacar')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _plans.isEmpty
                ? const Center(
                    child: Text(
                      'No hay planes disponibles por ahora.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(18),
                    itemCount: _plans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final plan = _plans[index];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.bolt_rounded,
                                  color: AppColors.gold),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(plan.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${plan.description} · ${plan.days} días',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              plan.price,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/profile/highlight_plans_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/screens/profile/highlight_plans_screen.dart
git commit -m "feat(frontend): add HighlightPlansScreen backed by real plan data"
```

---

### Task 10: Frontend — `HelpScreen`

**Files:**
- Create: `lib/screens/profile/help_screen.dart`

**Interfaces:**
- Consumes: nothing (fully static content).
- Produces: `class HelpScreen extends StatelessWidget`, no constructor params.

- [ ] **Step 1: Create the screen**

```dart
import 'package:flutter/material.dart';

import '../../app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = [
    (
      question: '¿Cómo publico un producto?',
      answer: 'Desde la pantalla principal toca el botón "+" y completa '
          'título, categoría, precio, descripción y fotos.',
    ),
    (
      question: '¿Cómo contacto a un vendedor?',
      answer: 'Entra al detalle del producto y toca "Contactar" para abrir '
          'el chat directamente con el vendedor.',
    ),
    (
      question: '¿Cómo funciona la verificación de cuenta?',
      answer: 'Desde tu perfil puedes iniciar la verificación con tu '
          'credencial universitaria o identificación. El equipo la revisa '
          'y te notifica cuando quede aprobada.',
    ),
    (
      question: '¿Cómo reporto un problema o usuario?',
      answer: 'Ve a "Confianza y seguridad" en tu perfil para conocer las '
          'recomendaciones, o escríbenos a soporte con el detalle del caso.',
    ),
    (
      question: '¿Cómo contacto a soporte?',
      answer: 'Escríbenos a soporte@mercaditoum.com y te responderemos en '
          'menos de 48 horas hábiles.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: _faqs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final faq = _faqs[index];
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: ExpansionTile(
                title: Text(
                  faq.question,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    faq.answer,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/profile/help_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/screens/profile/help_screen.dart
git commit -m "feat(frontend): add HelpScreen with real FAQ content"
```

---

### Task 11: Wire the 3 new screens into `profile_screen.dart`

**Files:**
- Modify: `lib/screens/profile_screen.dart`

**Interfaces:**
- Consumes: `SafetyTipsScreen` (Task 8), `HighlightPlansScreen` (Task 9), `HelpScreen` (Task 10) — all `StatelessWidget`/`StatefulWidget` with no required constructor params.
- Produces: nothing consumed by later tasks (this is the last content task).

- [ ] **Step 1: Add imports**

In `lib/screens/profile_screen.dart`, add these imports near the other `profile/`-adjacent imports:

```dart
import 'profile/help_screen.dart';
import 'profile/highlight_plans_screen.dart';
import 'profile/safety_tips_screen.dart';
```

- [ ] **Step 2: Add `onTap` to the 3 mock options**

Replace:

```dart
            _ProfileOption(
              icon: Icons.shield_rounded,
              title: 'Confianza y seguridad',
              subtitle: 'Recomendaciones para comprar en campus',
            ),
            _ProfileOption(
              icon: Icons.payments_rounded,
              title: 'Planes para destacar',
              subtitle: 'Consulta opciones de visibilidad pagada',
            ),
            _ProfileOption(
              icon: Icons.help_rounded,
              title: 'Ayuda',
              subtitle: 'Preguntas frecuentes',
            ),
```

with:

```dart
            _ProfileOption(
              icon: Icons.shield_rounded,
              title: 'Confianza y seguridad',
              subtitle: 'Recomendaciones para comprar en campus',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const SafetyTipsScreen()),
              ),
            ),
            _ProfileOption(
              icon: Icons.payments_rounded,
              title: 'Planes para destacar',
              subtitle: 'Consulta opciones de visibilidad pagada',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const HighlightPlansScreen()),
              ),
            ),
            _ProfileOption(
              icon: Icons.help_rounded,
              title: 'Ayuda',
              subtitle: 'Preguntas frecuentes',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
              ),
            ),
```

- [ ] **Step 3: Verify with static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/profile_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/screens/profile_screen.dart
git commit -m "feat(frontend): wire safety tips, highlight plans and help screens into profile"
```

---

### Task 12: Full project verification

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Run full static analysis**

Run: `cd /home/daniel/mercaditoUM && flutter analyze`
Expected: `No issues found!` (or only pre-existing issues unrelated to files touched in this plan — compare against a baseline run on `main` before Task 1 if any appear).

- [ ] **Step 2: Confirm the release build still compiles and stays signed with the persistent keystore**

Run: `cd /home/daniel/mercaditoUM && flutter build apk --release --build-number=2`
Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk`

Run: `/home/daniel/Android/Sdk/build-tools/36.1.0/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk`
Expected: `Signer #1 certificate DN: CN=Marketplace UM, OU=Dev, O=MarketplaceUM, L=Unknown, ST=Unknown, C=MX` (the release keystore set up previously — confirms this change didn't accidentally fall back to debug signing).

- [ ] **Step 3: Manual smoke check (documented, not automated)**

No emulator/device is available in this environment. Note explicitly to the user that visual verification (avatar upload flow, the 3 new screens rendering correctly, editing name/phone end-to-end against a running backend) is still pending and should be done by the user on a device before distributing a new build.
