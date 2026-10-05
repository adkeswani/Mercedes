import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/library/data/library_collapse_preference_stub.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_organizer.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';

void main() {
  final now = DateTime.utc(2026);
  final folder = LibraryFolder(
    id: 'strength',
    ownerId: 'coach',
    name: 'Strength',
    itemType: LibraryItemType.workout,
    createdAt: now,
    createdBy: 'coach',
    updatedAt: now,
    updatedBy: 'coach',
  );

  test('collapse preference keys include user, type, scope, and folder', () {
    expect(
      libraryCollapsePreferenceKey(
        userId: 'coach',
        itemType: LibraryItemType.program,
        scopeId: 'client-athlete',
        folderId: 'base',
      ),
      'coach.program.client-athlete.base',
    );
    expect(
      libraryCollapsePreferenceKey(
        userId: 'other',
        itemType: LibraryItemType.program,
        scopeId: 'shared',
        folderId: null,
      ),
      'other.program.shared.unfiled',
    );
  });

  testWidgets('groups, filters, collapses, and restores collapse state',
      (tester) async {
    final preference = MemoryLibraryCollapsePreference();
    final items = [
      const _Item(
        id: 'foldered',
        name: 'Power Session',
        tags: ['Power'],
        folderId: 'strength',
      ),
      const _Item(id: 'unfiled', name: 'Mobility', tags: ['Recovery']),
    ];

    Widget app() => ProviderScope(
          overrides: [
            libraryCollapsePreferenceProvider.overrideWithValue(preference),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LibraryOrganizer<_Item>(
                userId: 'coach',
                itemType: LibraryItemType.workout,
                items: items,
                folders: [folder],
                nameOf: (item) => item.name,
                tagsOf: (item) => item.tags,
                folderIdOf: (item) => item.folderId,
                clientAthleteIdOf: (item) => item.clientAthleteId,
                tileBuilder: (_, item, organizationButton) => ListTile(
                  title: Text(item.name),
                  trailing: organizationButton,
                ),
                updateOrganization: (
                  _, {
                  required tags,
                  required folderId,
                  required clientAthleteId,
                }) async {},
                createFolder: (_) async {},
                renameFolder: (_, __) async {},
                deleteFolder: (_) async {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(app());
    expect(find.text('Strength (1)'), findsOneWidget);
    expect(find.text('Unfiled (1)'), findsOneWidget);
    expect(find.text('Power Session'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse Strength'));
    await tester.pump();
    expect(find.text('Power Session'), findsNothing);

    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('Power Session'), findsNothing);

    await tester.tap(find.byTooltip('Expand Strength'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Power'));
    await tester.pump();
    expect(find.text('Power Session'), findsOneWidget);
    expect(find.text('Mobility'), findsNothing);
  });

  testWidgets('edits tags, folder, and active client scope', (tester) async {
    List<String>? savedTags;
    String? savedFolder;
    String? savedClient;
    const item = _Item(id: 'one', name: 'Client Plan');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryCollapsePreferenceProvider.overrideWithValue(
            MemoryLibraryCollapsePreference(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LibraryOrganizer<_Item>(
              userId: 'coach',
              itemType: LibraryItemType.program,
              items: const [item],
              folders: [folder],
              activeClientNames: const {'athlete': 'Alex Athlete'},
              supportsClientScope: true,
              nameOf: (value) => value.name,
              tagsOf: (value) => value.tags,
              folderIdOf: (value) => value.folderId,
              clientAthleteIdOf: (value) => value.clientAthleteId,
              tileBuilder: (_, value, organizationButton) => ListTile(
                title: Text(value.name),
                trailing: organizationButton,
              ),
              updateOrganization: (
                _, {
                required tags,
                required folderId,
                required clientAthleteId,
              }) async {
                savedTags = tags;
                savedFolder = folderId;
                savedClient = clientAthleteId;
              },
              createFolder: (_) async {},
              renameFolder: (_, __) async {},
              deleteFolder: (_) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Organize Client Plan'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Tags'),
      ' Strength, strength, Power ',
    );

    final dropdowns = find.byType(DropdownButtonFormField<String?>);
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Strength').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex Athlete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedTags, ['Strength', 'Power']);
    expect(savedFolder, 'strength');
    expect(savedClient, 'athlete');
  });

  testWidgets('drags an item onto a folder header to move it there',
      (tester) async {
    final otherFolder = LibraryFolder(
      id: 'cardio',
      ownerId: 'coach',
      name: 'Cardio',
      itemType: LibraryItemType.workout,
      createdAt: now,
      createdBy: 'coach',
      updatedAt: now,
      updatedBy: 'coach',
    );
    String? movedFolderId;
    var moveCount = 0;
    const item = _Item(id: 'unfiled', name: 'Mobility', tags: ['Recovery']);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryCollapsePreferenceProvider.overrideWithValue(
            MemoryLibraryCollapsePreference(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LibraryOrganizer<_Item>(
              userId: 'coach',
              itemType: LibraryItemType.workout,
              items: const [item],
              folders: [folder, otherFolder],
              nameOf: (value) => value.name,
              tagsOf: (value) => value.tags,
              folderIdOf: (value) => value.folderId,
              clientAthleteIdOf: (value) => value.clientAthleteId,
              tileBuilder: (_, value, organizationButton) => ListTile(
                title: Text(value.name),
                trailing: organizationButton,
              ),
              updateOrganization: (
                _, {
                required tags,
                required folderId,
                required clientAthleteId,
              }) async {
                moveCount++;
                movedFolderId = folderId;
              },
              createFolder: (_) async {},
              renameFolder: (_, __) async {},
              deleteFolder: (_) async {},
            ),
          ),
        ),
      ),
    );

    await _longPressDrag(
      tester,
      from: tester.getCenter(find.text('Mobility')),
      to: tester.getCenter(find.text('Cardio (0)')),
    );

    expect(moveCount, 1);
    expect(movedFolderId, 'cardio');
  });

  testWidgets(
      'on web, an immediate drag (no long-press pause) moves an item to a folder',
      (tester) async {
    String? dragged;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DragTarget<String>(
                onAcceptWithDetails: (details) => dragged = details.data,
                builder: (context, candidate, rejected) => const SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: Text('target'),
                ),
              ),
              buildLibraryDraggableTile<String>(
                isWeb: true,
                data: 'item',
                feedback: const Material(child: Text('dragging')),
                childWhenDragging: const Opacity(opacity: 0.4, child: Text('Mobility')),
                child: const Text('Mobility'),
              ),
            ],
          ),
        ),
      ),
    );

    // Confirms the immediate (non-long-press) Draggable is used on web.
    expect(find.byType(Draggable<String>), findsOneWidget);
    expect(find.byType(LongPressDraggable<String>), findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Mobility')));
    await gesture.moveTo(tester.getCenter(find.text('target')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dragged, 'item');
  });

  testWidgets('renders client items once under the client partition',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LibraryOrganizer<_Item>(
              userId: 'coach',
              itemType: LibraryItemType.workout,
              items: const [
                _Item(
                  id: 'client',
                  name: 'Alex Session',
                  clientAthleteId: 'athlete',
                ),
              ],
              folders: const [],
              activeClientNames: const {'athlete': 'Alex Athlete'},
              supportsClientScope: true,
              nameOf: (item) => item.name,
              tagsOf: (item) => item.tags,
              folderIdOf: (item) => item.folderId,
              clientAthleteIdOf: (item) => item.clientAthleteId,
              tileBuilder: (_, item, organizationButton) => ListTile(
                title: Text(item.name),
                trailing: organizationButton,
              ),
              updateOrganization: (
                _, {
                required tags,
                required folderId,
                required clientAthleteId,
              }) async {},
              createFolder: (_) async {},
              renameFolder: (_, __) async {},
              deleteFolder: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Shared library'), findsOneWidget);
    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('Alex Athlete (1)'), findsOneWidget);
    expect(find.text('Alex Session'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse Alex Athlete'));
    await tester.pump();
    expect(find.text('Alex Session'), findsNothing);
    expect(find.byTooltip('Expand Alex Athlete'), findsOneWidget);
  });

  testWidgets('renders compact and color-distinct library labels',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              LibraryTagLabel(tag: 'Strength'),
              LibraryMetadataLabel(label: 'v1'),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(LibraryTagLabel)).height,
      lessThanOrEqualTo(24),
    );
    expect(
      tester.getSize(find.byType(LibraryMetadataLabel)).height,
      lessThanOrEqualTo(24),
    );

    BoxDecoration decorationOf(Finder parent) {
      return tester
          .widget<DecoratedBox>(
            find.descendant(of: parent, matching: find.byType(DecoratedBox)),
          )
          .decoration as BoxDecoration;
    }

    expect(
      decorationOf(find.byType(LibraryTagLabel)).color,
      isNot(decorationOf(find.byType(LibraryMetadataLabel)).color),
    );
  });
}

class _Item {
  const _Item({
    required this.id,
    required this.name,
    this.tags = const [],
    this.folderId,
    this.clientAthleteId,
  });

  final String id;
  final String name;
  final List<String> tags;
  final String? folderId;
  final String? clientAthleteId;
}

Future<void> _longPressDrag(
  WidgetTester tester, {
  required Offset from,
  required Offset to,
}) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 500));
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
