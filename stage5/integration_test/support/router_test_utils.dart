import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter mountedAppRouter(WidgetTester tester) => GoRouter.of(
      tester.element(find.byType(Navigator).first),
    );
