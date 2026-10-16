import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/stable_workspace_canvas.dart';
import 'package:fasty/notes/workspace_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalNote note(String id) {
    return LocalNote(
      id: id,
      title: 'Target',
      content: 'Graph navigation target',
      createdAt: DateTime.utc(2026, 9, 9),
      updatedAt: DateTime.utc(2026, 9, 9),
      syncStatus: 'synced',
      isDeleted: false,
    );
  }

  WorkspaceDefinition workspace({double scale = 1.4}) {
    final now = DateTime.utc(2026, 9, 9);

    return WorkspaceDefinition(
      id: 'workspace',
      name: 'Workspace',
      colorValue: 0xFF625BEB,
      cameraX: 25,
      cameraY: -35,
      scale: scale,
      createdAt: now,
      updatedAt: now,
    );
  }

  WorkspacePlacement placement(String noteId) {
    return WorkspacePlacement(
      workspaceId: 'workspace',
      noteId: noteId,
      x: 900,
      y: 650,
      width: 240,
      height: 180,
      zIndex: 0,
    );
  }

  testWidgets(
    'focusNote centers the target while preserving the current zoom',
    (tester) async {
      final key = GlobalKey<StableWorkspaceCanvasState>();
      double? cameraX;
      double? cameraY;
      double? reportedScale;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 400,
                child: StableWorkspaceCanvas(
                  key: key,
                  workspace: workspace(),
                  notes: [note('target')],
                  placements: [placement('target')],
                  links: const [],
                  onEdit: (_) {},
                  onDelete: (_) {},
                  onScaleChanged: (_) {},
                  onLayoutChanged: (_) {},
                  onViewChanged: (x, y, scale) {
                    cameraX = x;
                    cameraY = y;
                    reportedScale = scale;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      key.currentState!.focusNote('target');
      await tester.pump();

      expect(key.currentState!.scale, closeTo(1.4, 0.000001));
      expect(reportedScale, closeTo(1.4, 0.000001));
      expect(cameraX, closeTo(-1128, 0.000001));
      expect(cameraY, closeTo(-836, 0.000001));
    },
  );

  testWidgets('focusNote ignores an unknown note id', (tester) async {
    final key = GlobalKey<StableWorkspaceCanvasState>();
    var viewChangeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 400,
              child: StableWorkspaceCanvas(
                key: key,
                workspace: workspace(),
                notes: [note('target')],
                placements: [placement('target')],
                links: const [],
                onEdit: (_) {},
                onDelete: (_) {},
                onScaleChanged: (_) {},
                onLayoutChanged: (_) {},
                onViewChanged: (_, _, _) {
                  viewChangeCount++;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    key.currentState!.focusNote('missing');
    await tester.pump();

    expect(viewChangeCount, 0);
    expect(key.currentState!.scale, closeTo(1.4, 0.000001));
  });
}
