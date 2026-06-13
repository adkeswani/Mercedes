import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage3/features/exercises/data/exercise_note_repository.dart';
import 'package:stage3/features/exercises/domain/exercise_note.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late ExerciseNoteRepository repo;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repo = ExerciseNoteRepository(
      userId: 'athlete1',
      firestore: fakeFirestore,
    );
  });

  group('ExerciseNote', () {
    test('constructor creates note with required fields', () {
      final note = ExerciseNote(
        id: 'ex1',
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench Press',
        note: 'Keep elbows tucked',
        updatedAt: DateTime(2026, 6, 1),
      );

      expect(note.exerciseTemplateId, 'ex1');
      expect(note.exerciseName, 'Bench Press');
      expect(note.note, 'Keep elbows tucked');
    });

    test('validate throws on empty exerciseTemplateId', () {
      final note = ExerciseNote(
        id: '',
        exerciseTemplateId: '',
        exerciseName: 'Bench',
        note: 'some note',
        updatedAt: DateTime.now(),
      );
      expect(() => note.validate(), throwsArgumentError);
    });

    test('validate throws on empty exerciseName', () {
      final note = ExerciseNote(
        id: 'ex1',
        exerciseTemplateId: 'ex1',
        exerciseName: '',
        note: 'some note',
        updatedAt: DateTime.now(),
      );
      expect(() => note.validate(), throwsArgumentError);
    });

    test('validate throws on empty note', () {
      final note = ExerciseNote(
        id: 'ex1',
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench',
        note: '',
        updatedAt: DateTime.now(),
      );
      expect(() => note.validate(), throwsArgumentError);
    });

    test('validate succeeds for valid note', () {
      final note = ExerciseNote(
        id: 'ex1',
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench Press',
        note: 'Keep elbows tucked',
        updatedAt: DateTime.now(),
      );
      expect(() => note.validate(), returnsNormally);
    });
  });

  group('ExerciseNoteRepository', () {
    test('saveNote creates doc in user subcollection', () async {
      await repo.saveNote(
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench Press',
        note: 'Keep elbows tucked',
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc('athlete1')
          .collection('exerciseNotes')
          .doc('ex1')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['exerciseTemplateId'], 'ex1');
      expect(doc.data()!['exerciseName'], 'Bench Press');
      expect(doc.data()!['note'], 'Keep elbows tucked');
    });

    test('saveNote overwrites existing note', () async {
      await repo.saveNote(
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench Press',
        note: 'Original note',
      );
      await repo.saveNote(
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench Press',
        note: 'Updated note',
      );

      final note = await repo.getNote('ex1');
      expect(note, isNotNull);
      expect(note!.note, 'Updated note');
    });

    test('getNote returns null for nonexistent note', () async {
      final note = await repo.getNote('nonexistent');
      expect(note, isNull);
    });

    test('getNote returns note with correct fields', () async {
      await repo.saveNote(
        exerciseTemplateId: 'ex1',
        exerciseName: 'Squat',
        note: 'Break at hips first',
      );

      final note = await repo.getNote('ex1');
      expect(note, isNotNull);
      expect(note!.id, 'ex1');
      expect(note.exerciseTemplateId, 'ex1');
      expect(note.exerciseName, 'Squat');
      expect(note.note, 'Break at hips first');
    });

    test('deleteNote removes the doc', () async {
      await repo.saveNote(
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench',
        note: 'To be deleted',
      );

      await repo.deleteNote('ex1');

      final note = await repo.getNote('ex1');
      expect(note, isNull);
    });

    test('watchNotes streams all notes as a map', () async {
      await repo.saveNote(
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench Press',
        note: 'Note 1',
      );
      await repo.saveNote(
        exerciseTemplateId: 'ex2',
        exerciseName: 'Squat',
        note: 'Note 2',
      );

      final notes = await repo.watchNotes().first;
      expect(notes.length, 2);
      expect(notes['ex1']!.note, 'Note 1');
      expect(notes['ex2']!.note, 'Note 2');
    });

    test('watchNotes updates when note is added', () async {
      final stream = repo.watchNotes();

      // First emit: empty
      final first = await stream.first;
      expect(first.isEmpty, isTrue);

      // Add a note
      await repo.saveNote(
        exerciseTemplateId: 'ex1',
        exerciseName: 'Deadlift',
        note: 'Brace core',
      );

      final second = await stream.first;
      expect(second.length, 1);
      expect(second['ex1']!.exerciseName, 'Deadlift');
    });

    test('notes are private per user', () async {
      // Save as athlete1
      await repo.saveNote(
        exerciseTemplateId: 'ex1',
        exerciseName: 'Bench',
        note: 'Athlete 1 note',
      );

      // Create repo for a different user
      final otherRepo = ExerciseNoteRepository(
        userId: 'athlete2',
        firestore: fakeFirestore,
      );

      // Other user should not see athlete1's note
      final note = await otherRepo.getNote('ex1');
      expect(note, isNull);

      // Other user's stream should be empty
      final notes = await otherRepo.watchNotes().first;
      expect(notes.isEmpty, isTrue);
    });
  });
}
