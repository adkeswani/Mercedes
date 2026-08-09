import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:stage4/core/enums.dart';
import 'package:stage4/features/profile/domain/feedback.dart' as domain;

typedef SubmitFeedback = Future<void> Function(
  FeedbackType type,
  String body,
);

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({
    required this.onSubmit,
    super.key,
  });

  final SubmitFeedback onSubmit;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _formKey = GlobalKey<FormState>();
  final _bodyController = TextEditingController();
  FeedbackType _type = FeedbackType.general;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.onSubmit(_type, _bodyController.text.trim());
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.message ?? 'Unable to send feedback.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send feedback'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<FeedbackType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Category'),
                items: FeedbackType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_typeLabel(type)),
                      ),
                    )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (type) {
                        if (type != null) {
                          setState(() => _type = type);
                        }
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                maxLength: domain.Feedback.maxBodyLength,
                decoration: const InputDecoration(
                  labelText: 'What would you like us to know?',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your feedback';
                  }
                  return null;
                },
                enabled: !_isSubmitting,
              ),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ],
    );
  }

  String _typeLabel(FeedbackType type) {
    return switch (type) {
      FeedbackType.bug => 'Bug report',
      FeedbackType.feature => 'Feature request',
      FeedbackType.general => 'General feedback',
    };
  }
}
