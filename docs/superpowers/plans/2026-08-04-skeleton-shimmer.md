# Skeleton/Shimmer Loading States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `CircularProgressIndicator` loading states in the home grid and seller profile screens with shimmer skeletons that mirror the real widget structure, with a fade transition into real content.

**Architecture:** A shared `AppShimmer`/`ShimmerBox` primitive (theme-aware colors) backs a `ProductCardSkeleton` that mirrors `_GridProductCard`. `HomeGridSkeleton` arranges it in the same grid delegate as the real grid. `SellerProfileSkeleton` mirrors `_buildContent` block-by-block. Both screens swap loading/content via `AnimatedSwitcher`.

**Tech Stack:** Flutter, `shimmer` package, existing `AppColorsContext`/`AppColors`/`AppTypography`/`AppAnimations` from `lib/app_theme.dart`.

## Global Constraints

- Use `shimmer: ^3.0.0` in `pubspec.yaml`.
- Shimmer colors MUST come from `context.colors.surfaceMuted` (base) and `context.colors.border` (highlight) — no hardcoded `Colors.grey[...]`.
- `ProductCardSkeleton` grid dimensions MUST match the real grid exactly: home grid `crossAxisCount:2, crossAxisSpacing:12, mainAxisSpacing:12, childAspectRatio:0.64`; seller profile grid `childAspectRatio:0.66` (same crossAxisCount/spacing).
- `ProductCardSkeleton` internal layout MUST match `_GridProductCard` in `lib/widgets/product_card.dart`: `Padding(10)`, `DecoratedBox(borderRadius:14)`, image `AspectRatio(4/3.4, borderRadius:10)`, `SizedBox(height:8)`, price line, `SizedBox(height:4)`, title block (2 lines), `SizedBox(height:2)`, description line, `Spacer()`, `SizedBox(height:6)`, bottom row (text + pill badge).
- `ProductDetailScreen` is out of scope — do not touch it.
- Transition uses `AnimatedSwitcher(duration: AppAnimations.medium)`.

---

### Task 1: Add `shimmer` dependency and shared shimmer primitives

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/widgets/app_shimmer.dart`
- Test: `test/app_shimmer_test.dart`

**Interfaces:**
- Produces: `AppShimmer` (widget, `{Key? key, required Widget child}`), `ShimmerBox` (widget, `{Key? key, double? width, double? height, double borderRadius = 6}`).

- [ ] **Step 1: Add the dependency**

Add to `pubspec.yaml` under `dependencies:` (alphabetical position not required, existing file is not strictly sorted):

```yaml
  shimmer: ^3.0.0
```

Run: `cd /home/daniel/mercaditoUM && flutter pub get`
Expected: resolves successfully, `pubspec.lock` updated with a `shimmer` entry.

- [ ] **Step 2: Write the failing test**

Create `test/app_shimmer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/app_shimmer.dart';
import 'package:shimmer/shimmer.dart';

void main() {
  testWidgets('AppShimmer wraps its child in a Shimmer using theme colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppShimmer(child: ShimmerBox(width: 40, height: 40)),
        ),
      ),
    );

    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.byType(ShimmerBox), findsOneWidget);
  });

  testWidgets('ShimmerBox applies the requested border radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShimmerBox(width: 20, height: 20, borderRadius: 12),
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(12));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd /home/daniel/mercaditoUM && flutter test test/app_shimmer_test.dart`
Expected: FAIL — `lib/widgets/app_shimmer.dart` does not exist yet (import error).

- [ ] **Step 4: Implement `AppShimmer` and `ShimmerBox`**

Create `lib/widgets/app_shimmer.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../app_theme.dart';

/// Envoltura de shimmer con los colores de tema de la app (no grises
/// hardcodeados), para que el efecto se sienta integrado en claro y oscuro.
class AppShimmer extends StatelessWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.colors.surfaceMuted,
      highlightColor: context.colors.border,
      child: child,
    );
  }
}

/// Bloque base de un skeleton: un rectángulo (o círculo) del color de
/// superficie muted, listo para envolverse en un [AppShimmer] junto con
/// otros bloques hermanos.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 6,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(borderRadius)
            : null,
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /home/daniel/mercaditoUM && flutter test test/app_shimmer_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd /home/daniel/mercaditoUM
git add pubspec.yaml pubspec.lock lib/widgets/app_shimmer.dart test/app_shimmer_test.dart
git commit -m "feat: add shimmer dependency and theme-aware shimmer primitives"
```

---

### Task 2: `ProductCardSkeleton` matching `_GridProductCard`

**Files:**
- Create: `lib/widgets/product_card_skeleton.dart`
- Test: `test/product_card_skeleton_test.dart`

**Interfaces:**
- Consumes: `AppShimmer`, `ShimmerBox` from `lib/widgets/app_shimmer.dart` (Task 1).
- Produces: `ProductCardSkeleton` (widget, `{Key? key}`, no parameters — it is a static skeleton, not tied to a product).

- [ ] **Step 1: Write the failing test**

Create `test/product_card_skeleton_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/app_shimmer.dart';
import 'package:mercadito_um/widgets/product_card_skeleton.dart';

void main() {
  testWidgets('ProductCardSkeleton renders inside a shimmer wrapper', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProductCardSkeleton()),
      ),
    );

    expect(find.byType(ProductCardSkeleton), findsOneWidget);
    expect(find.byType(AppShimmer), findsOneWidget);
    // Bloques: imagen, precio, 2 líneas de título, descripción, fila
    // inferior (texto + badge) = al menos 6 ShimmerBox.
    expect(find.byType(ShimmerBox), findsAtLeastNWidgets(6));
  });

  testWidgets('ProductCardSkeleton image block uses a 4/3.4 aspect ratio', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProductCardSkeleton()),
      ),
    );

    final aspectRatio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(aspectRatio.aspectRatio, closeTo(4 / 3.4, 0.001));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/daniel/mercaditoUM && flutter test test/product_card_skeleton_test.dart`
Expected: FAIL — `lib/widgets/product_card_skeleton.dart` does not exist.

- [ ] **Step 3: Implement `ProductCardSkeleton`**

Create `lib/widgets/product_card_skeleton.dart`. This mirrors `_GridProductCard` in
`lib/widgets/product_card.dart` exactly: same outer `DecoratedBox`/padding as
`ProductCard._buildCard`, same inner spacing as `_GridProductCard.build`.

```dart
import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'app_shimmer.dart';

/// Skeleton de una tarjeta de producto para el grid del home, con las
/// mismas dimensiones que [ProductCard] (ver `_GridProductCard`): mismo
/// padding, mismo aspect ratio de imagen, mismas alturas de bloques de
/// texto. Sin parámetros — es un placeholder estático, no representa un
/// producto real.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AppShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3.4,
                  child: ShimmerBox(borderRadius: 10),
                ),
                const SizedBox(height: 8),
                const ShimmerBox(width: 60, height: 14),
                const SizedBox(height: 4),
                const ShimmerBox(height: 13, borderRadius: 4),
                const SizedBox(height: 3),
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.3,
                  child: const ShimmerBox(height: 13, borderRadius: 4),
                ),
                const SizedBox(height: 2),
                const ShimmerBox(width: 90, height: 11, borderRadius: 4),
                const Spacer(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: const ShimmerBox(height: 11, borderRadius: 4),
                    ),
                    const SizedBox(width: 8),
                    const ShimmerBox(width: 46, height: 18, borderRadius: 999),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/daniel/mercaditoUM && flutter test test/product_card_skeleton_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/daniel/mercaditoUM
git add lib/widgets/product_card_skeleton.dart test/product_card_skeleton_test.dart
git commit -m "feat: add ProductCardSkeleton matching real card dimensions"
```

---

### Task 3: `HomeGridSkeleton` and integration into `home_screen.dart`

**Files:**
- Create: `lib/widgets/home_grid_skeleton.dart`
- Modify: `lib/screens/home_screen.dart:197-201`
- Test: `test/home_grid_skeleton_test.dart`

**Interfaces:**
- Consumes: `ProductCardSkeleton` (Task 2).
- Produces: `HomeGridSkeleton` (widget, `{Key? key}`, no parameters).

- [ ] **Step 1: Write the failing test**

Create `test/home_grid_skeleton_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/home_grid_skeleton.dart';
import 'package:mercadito_um/widgets/product_card_skeleton.dart';

void main() {
  testWidgets('HomeGridSkeleton shows 6 ProductCardSkeleton in a 2-column grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeGridSkeleton())),
    );

    expect(find.byType(ProductCardSkeleton), findsNWidgets(6));

    final delegate =
        (tester.widget<GridView>(find.byType(GridView)).gridDelegate)
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.crossAxisSpacing, 12);
    expect(delegate.mainAxisSpacing, 12);
    expect(delegate.childAspectRatio, 0.64);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/daniel/mercaditoUM && flutter test test/home_grid_skeleton_test.dart`
Expected: FAIL — `lib/widgets/home_grid_skeleton.dart` does not exist.

- [ ] **Step 3: Implement `HomeGridSkeleton`**

Create `lib/widgets/home_grid_skeleton.dart`:

```dart
import 'package:flutter/material.dart';

import 'product_card_skeleton.dart';

/// Skeleton del grid de productos del home. Usa el mismo
/// [SliverGridDelegateWithFixedCrossAxisCount] que el grid real en
/// `home_screen.dart` (crossAxisCount:2, spacing:12/12, aspectRatio:0.64).
class HomeGridSkeleton extends StatelessWidget {
  const HomeGridSkeleton({super.key});

  static const _itemCount = 6;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _itemCount,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.64,
        ),
        itemBuilder: (context, index) => const ProductCardSkeleton(),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/daniel/mercaditoUM && flutter test test/home_grid_skeleton_test.dart`
Expected: PASS.

- [ ] **Step 5: Integrate into `home_screen.dart` with fade transition**

In `lib/screens/home_screen.dart`, add the import near the other widget imports (after the existing `import '../widgets/product_card.dart';` line):

```dart
import '../widgets/home_grid_skeleton.dart';
```

Replace the loading branch (current lines 199-201):

```dart
    if (_loading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
```

with:

```dart
    if (_loading) {
      return const HomeGridSkeleton();
    }
```

Then find the `return` statement that renders the loaded body (the `CustomScrollView`/main content built after the `_error` check further down in `build`) and wrap the whole `build` method's non-loading, non-error return value so switching between skeleton and content fades. Concretely, replace the method's overall structure so `build` becomes:

```dart
  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const HomeGridSkeleton(key: ValueKey('home-skeleton'));
    } else if (_error != null) {
      body = SafeArea(
        key: const ValueKey('home-error'),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: AppColors.danger,
                ),
                // ... keep the rest of the existing error column unchanged
              ],
            ),
          ),
        ),
      );
    } else {
      body = KeyedSubtree(
        key: const ValueKey('home-content'),
        child: /* existing loaded-content widget tree, unchanged */,
      );
    }

    return AnimatedSwitcher(
      duration: AppAnimations.medium,
      child: body,
    );
  }
```

Do this by editing in place: introduce the `Widget body;` variable, assign the
existing three branches' return expressions to `body` instead of returning
them directly (wrapping the error branch's `SafeArea` and the loaded-content
branch's outermost widget with the `key:` shown above), delete the early
`return` statements, and add the final `return AnimatedSwitcher(...)` at the
end of `build`. Do not alter the content of the error/loaded branches beyond
adding the `key`.

- [ ] **Step 6: Verify manually**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/home_screen.dart lib/widgets/home_grid_skeleton.dart`
Expected: no new errors.

Run the app (`flutter run`) with a throttled/slow network or a temporary
`await Future.delayed(const Duration(seconds: 2));` inserted at the top of
`_loadData()` in `home_screen.dart`, confirm the skeleton renders with 2
columns matching the real grid, then fades into real content. Remove the
temporary delay afterward.

- [ ] **Step 7: Run full test suite and commit**

Run: `cd /home/daniel/mercaditoUM && flutter test`
Expected: all tests PASS.

```bash
cd /home/daniel/mercaditoUM
git add lib/widgets/home_grid_skeleton.dart lib/screens/home_screen.dart test/home_grid_skeleton_test.dart
git commit -m "feat: show home grid skeleton while loading, with fade transition"
```

---

### Task 4: `SellerProfileSkeleton` and integration into `seller_profile_screen.dart`

**Files:**
- Create: `lib/widgets/seller_profile_skeleton.dart`
- Modify: `lib/screens/seller_profile_screen.dart`
- Test: `test/seller_profile_skeleton_test.dart`

**Interfaces:**
- Consumes: `AppShimmer`, `ShimmerBox` (Task 1), `ProductCardSkeleton` (Task 2).
- Produces: `SellerProfileSkeleton` (widget, `{Key? key}`, no parameters).

- [ ] **Step 1: Write the failing test**

Create `test/seller_profile_skeleton_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/product_card_skeleton.dart';
import 'package:mercadito_um/widgets/seller_profile_skeleton.dart';

void main() {
  testWidgets(
    'SellerProfileSkeleton shows avatar, text lines, button, '
    'schedule block, payment icons, and a 4-item product grid',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SellerProfileSkeleton())),
      );

      // Avatar circular.
      final circleFinder = find.byWidgetPredicate(
        (w) => w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(circleFinder, findsWidgets);

      // Grid de publicaciones: 4 skeletons de producto.
      expect(find.byType(ProductCardSkeleton), findsNWidgets(4));

      final delegate =
          (tester.widget<GridView>(find.byType(GridView)).gridDelegate)
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
      expect(delegate.childAspectRatio, 0.66);
    },
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/daniel/mercaditoUM && flutter test test/seller_profile_skeleton_test.dart`
Expected: FAIL — `lib/widgets/seller_profile_skeleton.dart` does not exist.

- [ ] **Step 3: Implement `SellerProfileSkeleton`**

Create `lib/widgets/seller_profile_skeleton.dart`. This mirrors
`_SellerProfileScreenState._buildContent` in `lib/screens/seller_profile_screen.dart`:
same `ListView` padding, same centered avatar block, same button height (52,
matching the app's `ElevatedButtonThemeData.minimumSize` in `app_theme.dart`),
a rectangular block standing in for `SellerScheduleAndLocationRow`, a row of
small circles standing in for `PaymentMethodsChips`, and the same product grid
delegate as the real one (`childAspectRatio: 0.66`).

```dart
import 'package:flutter/material.dart';

import 'app_shimmer.dart';
import 'product_card_skeleton.dart';

/// Skeleton del perfil de vendedor: identidad (avatar + nombre + carrera +
/// rating), botón de WhatsApp, bloque de horario/ubicación, íconos de
/// métodos de pago, y grid de publicaciones — mismo orden y proporciones
/// que `_SellerProfileScreenState._buildContent`.
class SellerProfileSkeleton extends StatelessWidget {
  const SellerProfileSkeleton({super.key});

  static const _productCount = 4;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        padding: const EdgeInsets.all(18),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Center(
            child: Column(
              children: [
                const ShimmerBox(width: 80, height: 80, shape: BoxShape.circle),
                const SizedBox(height: 12),
                const ShimmerBox(width: 140, height: 19, borderRadius: 4),
                const SizedBox(height: 8),
                const ShimmerBox(width: 100, height: 14, borderRadius: 4),
                const SizedBox(height: 10),
                const ShimmerBox(width: 120, height: 16, borderRadius: 4),
                const SizedBox(height: 16),
                const ShimmerBox(
                  width: double.infinity,
                  height: 52,
                  borderRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const ShimmerBox(width: double.infinity, height: 96, borderRadius: 16),
          const SizedBox(height: 20),
          const ShimmerBox(width: 180, height: 16, borderRadius: 4),
          const SizedBox(height: 10),
          Row(
            children: List.generate(
              4,
              (i) => Padding(
                padding: EdgeInsets.only(right: i == 3 ? 0 : 18),
                child: const ShimmerBox(width: 20, height: 20, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const ShimmerBox(width: 130, height: 16, borderRadius: 4),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _productCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (context, index) => const ProductCardSkeleton(),
          ),
        ],
      ),
    );
  }
}
```

Note: `ProductCardSkeleton` already wraps itself in its own `AppShimmer`
(Task 2); nesting it inside this screen's outer `AppShimmer` is harmless —
`Shimmer.fromColors` nesting does not break rendering, each subtree just
re-applies its own gradient sweep.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/daniel/mercaditoUM && flutter test test/seller_profile_skeleton_test.dart`
Expected: PASS.

- [ ] **Step 5: Integrate into `seller_profile_screen.dart` with fade transition**

In `lib/screens/seller_profile_screen.dart`, add the import:

```dart
import '../widgets/seller_profile_skeleton.dart';
```

Replace the `build` method's body switch (currently a ternary chain assigned
to `Scaffold.body`):

```dart
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(onRefresh: _load, child: _buildContent(context)),
```

with:

```dart
      body: AnimatedSwitcher(
        duration: AppAnimations.medium,
        child: _loading
            ? const SellerProfileSkeleton(key: ValueKey('seller-skeleton'))
            : _error != null
            ? Center(
                key: const ValueKey('seller-error'),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : RefreshIndicator(
                key: const ValueKey('seller-content'),
                onRefresh: _load,
                child: _buildContent(context),
              ),
      ),
```

`AppAnimations` is already available via the existing `import '../app_theme.dart';`
in this file.

- [ ] **Step 6: Verify manually**

Run: `cd /home/daniel/mercaditoUM && flutter analyze lib/screens/seller_profile_screen.dart lib/widgets/seller_profile_skeleton.dart`
Expected: no new errors.

Run the app, navigate to a seller profile with a temporary
`await Future.delayed(const Duration(seconds: 2));` inserted at the top of
`_load()` in `seller_profile_screen.dart`, confirm the skeleton renders with
the identity block, schedule block, payment icons, and product grid in the
right order, then fades into real content. Remove the temporary delay
afterward.

- [ ] **Step 7: Run full test suite and commit**

Run: `cd /home/daniel/mercaditoUM && flutter test`
Expected: all tests PASS.

```bash
cd /home/daniel/mercaditoUM
git add lib/widgets/seller_profile_skeleton.dart lib/screens/seller_profile_screen.dart test/seller_profile_skeleton_test.dart
git commit -m "feat: show seller profile skeleton while loading, with fade transition"
```

---

### Task 5: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run static analysis on the whole project**

Run: `cd /home/daniel/mercaditoUM && flutter analyze`
Expected: no new errors/warnings introduced by this feature (pre-existing warnings, if any, are out of scope).

- [ ] **Step 2: Run the full test suite**

Run: `cd /home/daniel/mercaditoUM && flutter test`
Expected: all tests PASS, including `test/app_shimmer_test.dart`,
`test/product_card_skeleton_test.dart`, `test/home_grid_skeleton_test.dart`,
`test/seller_profile_skeleton_test.dart`, and the pre-existing
`test/widget_test.dart` / `test/map_pixel_capture_test.dart`.

- [ ] **Step 3: Confirm scope boundary**

Run: `git diff --stat main` (or the relevant base branch) and confirm
`lib/screens/product_detail_screen.dart` does not appear in the diff — it was
explicitly out of scope per the design spec.
