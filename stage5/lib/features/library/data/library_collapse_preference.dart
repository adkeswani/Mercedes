import 'package:stage5/features/library/data/library_collapse_preference_contract.dart';
import 'package:stage5/features/library/data/library_collapse_preference_stub.dart'
    if (dart.library.html) 'package:stage5/features/library/data/library_collapse_preference_web.dart'
    as implementation;

export 'package:stage5/features/library/data/library_collapse_preference_contract.dart';

LibraryCollapsePreference createLibraryCollapsePreference() {
  return implementation.createLibraryCollapsePreference();
}
