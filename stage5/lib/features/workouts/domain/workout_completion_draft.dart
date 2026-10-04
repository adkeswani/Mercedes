import 'package:cloud_firestore/cloud_firestore.dart';

const workoutCompletionDraftSchemaVersion = 1;

class WorkoutCompletionDraft {
  const WorkoutCompletionDraft({
    required this.instanceId,
    required this.athleteId,
    required this.rpe,
    required this.durationMinutes,
    required this.revision,
    required this.clientId,
    required this.updatedAt,
    required this.sourceRoute,
    this.athleteNotes,
    this.currentStep = 0,
    this.slotInputs = const {},
    this.serverUpdatedAt,
  });

  final String instanceId;
  final String athleteId;
  final int rpe;
  final int durationMinutes;
  final String? athleteNotes;
  final int currentStep;
  final Map<String, Map<String, dynamic>> slotInputs;
  final int revision;
  final String clientId;
  final DateTime updatedAt;
  final DateTime? serverUpdatedAt;
  final String sourceRoute;

  WorkoutCompletionDraft copyWith({
    int? rpe,
    int? durationMinutes,
    String? athleteNotes,
    bool clearAthleteNotes = false,
    int? currentStep,
    Map<String, Map<String, dynamic>>? slotInputs,
    int? revision,
    DateTime? updatedAt,
    DateTime? serverUpdatedAt,
  }) {
    return WorkoutCompletionDraft(
      instanceId: instanceId,
      athleteId: athleteId,
      rpe: rpe ?? this.rpe,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      athleteNotes:
          clearAthleteNotes ? null : athleteNotes ?? this.athleteNotes,
      currentStep: currentStep ?? this.currentStep,
      slotInputs: slotInputs ?? this.slotInputs,
      revision: revision ?? this.revision,
      clientId: clientId,
      updatedAt: updatedAt ?? this.updatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      sourceRoute: sourceRoute,
    );
  }

  Map<String, dynamic> toMap({bool includeServerTimestamp = false}) {
    return {
      'schemaVersion': workoutCompletionDraftSchemaVersion,
      'instanceId': instanceId,
      'athleteId': athleteId,
      'rpe': rpe,
      'durationMinutes': durationMinutes,
      'athleteNotes': athleteNotes,
      'currentStep': currentStep,
      'slotInputs': slotInputs,
      'revision': revision,
      'clientId': clientId,
      'updatedAt': Timestamp.fromDate(updatedAt.toUtc()),
      'serverUpdatedAt': includeServerTimestamp
          ? FieldValue.serverTimestamp()
          : serverUpdatedAt == null
              ? null
              : Timestamp.fromDate(serverUpdatedAt!.toUtc()),
      'sourceRoute': sourceRoute,
    };
  }

  Map<String, dynamic> toLocalMap() {
    return {
      ...toMap(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'serverUpdatedAt': serverUpdatedAt?.toUtc().toIso8601String(),
    };
  }

  static WorkoutCompletionDraft fromMap(Map<String, dynamic> data) {
    if (data['schemaVersion'] != workoutCompletionDraftSchemaVersion) {
      throw const FormatException('Unsupported workout draft schema');
    }
    final slotInputsRaw = data['slotInputs'];
    if (slotInputsRaw is! Map) {
      throw const FormatException('Workout draft slotInputs must be a map');
    }
    final slotInputs = <String, Map<String, dynamic>>{};
    for (final entry in slotInputsRaw.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Workout draft slot input is invalid');
      }
      slotInputs[entry.key as String] = Map<String, dynamic>.from(
        entry.value as Map,
      );
    }
    final draft = WorkoutCompletionDraft(
      instanceId: _requiredString(data, 'instanceId'),
      athleteId: _requiredString(data, 'athleteId'),
      rpe: _requiredInt(data, 'rpe'),
      durationMinutes: _requiredInt(data, 'durationMinutes'),
      athleteNotes: data['athleteNotes'] as String?,
      currentStep: _requiredInt(data, 'currentStep'),
      slotInputs: slotInputs,
      revision: _requiredInt(data, 'revision'),
      clientId: _requiredString(data, 'clientId'),
      updatedAt: _requiredDate(data, 'updatedAt'),
      serverUpdatedAt: _optionalDate(data['serverUpdatedAt']),
      sourceRoute: _requiredString(data, 'sourceRoute'),
    );
    draft.validate();
    return draft;
  }

  void validate() {
    if (instanceId.isEmpty || athleteId.isEmpty || clientId.isEmpty) {
      throw const FormatException('Workout draft identity is incomplete');
    }
    if (rpe < 1 || rpe > 10) {
      throw const FormatException('Workout draft RPE must be 1 through 10');
    }
    if (durationMinutes < 0 || durationMinutes > 1440) {
      throw const FormatException('Workout draft duration is invalid');
    }
    if (athleteNotes != null && athleteNotes!.length > 4000) {
      throw const FormatException('Workout draft notes are too long');
    }
    if (currentStep < 0 || revision < 1) {
      throw const FormatException('Workout draft revision is invalid');
    }
    if (!sourceRoute.startsWith('/athlete/workouts/')) {
      throw const FormatException('Workout draft source route is invalid');
    }
  }
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Workout draft $key is invalid');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) {
    throw FormatException('Workout draft $key is invalid');
  }
  return value;
}

DateTime _requiredDate(Map<String, dynamic> data, String key) {
  final value = _optionalDate(data[key]);
  if (value == null) {
    throw FormatException('Workout draft $key is invalid');
  }
  return value;
}

DateTime? _optionalDate(Object? value) {
  return switch (value) {
    final Timestamp timestamp => timestamp.toDate().toUtc(),
    final DateTime date => date.toUtc(),
    final String text => DateTime.tryParse(text)?.toUtc(),
    _ => null,
  };
}

enum WorkoutDraftRestoreKind { none, local, server, conflict, invalidLocal }

class WorkoutDraftRestoreResult {
  const WorkoutDraftRestoreResult({
    required this.kind,
    this.draft,
    this.message,
    this.deviceOnly = false,
  });

  final WorkoutDraftRestoreKind kind;
  final WorkoutCompletionDraft? draft;
  final String? message;
  final bool deviceOnly;
}

WorkoutDraftRestoreResult reconcileWorkoutDrafts({
  required WorkoutCompletionDraft? local,
  required WorkoutCompletionDraft? server,
}) {
  if (local == null && server == null) {
    return const WorkoutDraftRestoreResult(kind: WorkoutDraftRestoreKind.none);
  }
  if (server == null) {
    return WorkoutDraftRestoreResult(
      kind: WorkoutDraftRestoreKind.local,
      draft: local,
      message: 'Restored progress saved on this device.',
    );
  }
  if (local == null) {
    return WorkoutDraftRestoreResult(
      kind: WorkoutDraftRestoreKind.server,
      draft: server,
      message: 'Restored saved workout progress.',
    );
  }

  final comparison = compareWorkoutDrafts(local, server);
  final selected = comparison > 0 ? local : server;
  final differs = local.revision != server.revision ||
      local.clientId != server.clientId ||
      local.rpe != server.rpe ||
      local.durationMinutes != server.durationMinutes ||
      local.athleteNotes != server.athleteNotes;
  return WorkoutDraftRestoreResult(
    kind: differs
        ? WorkoutDraftRestoreKind.conflict
        : WorkoutDraftRestoreKind.server,
    draft: selected,
    message: differs
        ? 'Recovered the newest draft; another device or tab also saved progress.'
        : 'Restored saved workout progress.',
  );
}

int compareWorkoutDrafts(
  WorkoutCompletionDraft first,
  WorkoutCompletionDraft second,
) {
  final revision = first.revision.compareTo(second.revision);
  if (revision != 0) {
    return revision;
  }
  final firstTime = first.serverUpdatedAt ?? first.updatedAt;
  final secondTime = second.serverUpdatedAt ?? second.updatedAt;
  final timestamp = firstTime.compareTo(secondTime);
  if (timestamp != 0) {
    return timestamp;
  }
  return first.clientId.compareTo(second.clientId);
}
