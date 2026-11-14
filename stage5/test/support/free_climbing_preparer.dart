import 'package:cloud_firestore/cloud_firestore.dart';

// Storage adapter for widget/repository tests; authorization and server-side
// validation are exercised separately against the real backend and rules.
Future<void> prepareFreeClimbsForTest(
  FirebaseFirestore firestore,
  Map<String, dynamic> request,
) async {
  final instance = firestore
      .collection('workoutInstances')
      .doc(request['instanceId'] as String);
  for (final entry in (request['actuals'] as Map).entries) {
    final actual = Map<String, dynamic>.from(entry.value as Map);
    final rows =
        (actual.remove('freeRows') as List).cast<Map<String, dynamic>>();
    actual.remove('rowIds');
    final ref = instance.collection('slotResults').doc(entry.key as String);
    final summary = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final key =
          '${row['gradingSystem']}/${row['grade']}/${row['sent']}/${row['attempts']}';
      final group = summary.putIfAbsent(
          key,
          () => {
                'gradingSystem': row['gradingSystem'],
                'grade': row['grade'],
                'sent': row['sent'],
                'attempts': row['attempts'],
                'count': 0,
              });
      group['count'] = (group['count'] as int) + 1;
    }
    final old = await ref.collection('climbs').get();
    for (final row in old.docs) {
      await row.reference.delete();
    }
    await ref.set({
      ...actual,
      'rowsStorageFormat': 'climbDocumentsV1',
      'rowCount': rows.length,
      'gradeSummary': summary.values.toList(),
      'draftRevision': request['revision'],
      'draftClientId': request['clientId'],
      'completionToken': request['completionToken'],
    });
    for (var i = 0; i < rows.length; i++) {
      await ref
          .collection('climbs')
          .doc(rows[i]['rowId'] as String)
          .set({...rows[i], 'order': i});
    }
  }
}
