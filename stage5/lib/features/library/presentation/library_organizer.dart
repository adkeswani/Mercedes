import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';

typedef LibraryTileBuilder<T> = Widget Function(
    BuildContext context, T item, Widget organizationButton);

typedef LibraryOrganizationUpdater<T> = Future<void> Function(
  T item, {
  required List<String> tags,
  required String? folderId,
  required String? clientAthleteId,
});

class LibraryTagLabel extends StatelessWidget {
  const LibraryTagLabel({required this.tag, super.key});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          tag,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class LibraryLoadError extends StatelessWidget {
  const LibraryLoadError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class LibraryOrganizer<T> extends ConsumerStatefulWidget {
  const LibraryOrganizer({
    required this.userId,
    required this.itemType,
    required this.items,
    required this.folders,
    required this.nameOf,
    required this.tagsOf,
    required this.folderIdOf,
    required this.clientAthleteIdOf,
    required this.tileBuilder,
    required this.updateOrganization,
    required this.createFolder,
    required this.renameFolder,
    required this.deleteFolder,
    this.activeClientNames = const {},
    this.supportsClientScope = false,
    this.emptyMessage = 'No library items yet.',
    super.key,
  });

  final String userId;
  final LibraryItemType itemType;
  final List<T> items;
  final List<LibraryFolder> folders;
  final String Function(T item) nameOf;
  final List<String> Function(T item) tagsOf;
  final String? Function(T item) folderIdOf;
  final String? Function(T item) clientAthleteIdOf;
  final LibraryTileBuilder<T> tileBuilder;
  final LibraryOrganizationUpdater<T> updateOrganization;
  final Future<void> Function(String name) createFolder;
  final Future<void> Function(LibraryFolder folder, String name) renameFolder;
  final Future<void> Function(LibraryFolder folder) deleteFolder;
  final Map<String, String> activeClientNames;
  final bool supportsClientScope;
  final String emptyMessage;

  @override
  ConsumerState<LibraryOrganizer<T>> createState() =>
      _LibraryOrganizerState<T>();
}

class _LibraryOrganizerState<T> extends ConsumerState<LibraryOrganizer<T>> {
  final _searchController = TextEditingController();
  final Set<String> _selectedTags = {};
  final Map<String, bool> _collapsed = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isCollapsed(String scopeId, String? folderId) {
    final key = libraryCollapsePreferenceKey(
      userId: widget.userId,
      itemType: widget.itemType,
      scopeId: scopeId,
      folderId: folderId,
    );
    return _collapsed.putIfAbsent(
      key,
      () => ref.read(libraryCollapsePreferenceProvider).read(key) ?? false,
    );
  }

  void _toggleCollapsed(String scopeId, String? folderId) {
    final key = libraryCollapsePreferenceKey(
      userId: widget.userId,
      itemType: widget.itemType,
      scopeId: scopeId,
      folderId: folderId,
    );
    final value = !_isCollapsed(scopeId, folderId);
    setState(() => _collapsed[key] = value);
    ref.read(libraryCollapsePreferenceProvider).write(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visible = widget.items.where((item) {
      final matchesQuery = query.isEmpty ||
          widget.nameOf(item).toLowerCase().contains(query) ||
          widget.tagsOf(item).any((tag) => tag.toLowerCase().contains(query));
      final normalizedTags =
          widget.tagsOf(item).map((tag) => tag.toLowerCase()).toSet();
      final matchesTags = _selectedTags.every(
        (tag) => normalizedTags.contains(tag),
      );
      return matchesQuery && matchesTags;
    }).toList();
    final tags = widget.items
        .expand(widget.tagsOf)
        .fold(<String, String>{}, (values, tag) {
          values.putIfAbsent(tag.toLowerCase(), () => tag);
          return values;
        })
        .entries
        .toList()
      ..sort(
        (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
      );
    final shared = visible
        .where((item) => widget.clientAthleteIdOf(item) == null)
        .toList();
    final clientIds = visible
        .map(widget.clientAthleteIdOf)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort((a, b) {
        final aName = widget.activeClientNames[a] ?? a;
        final bName = widget.activeClientNames[b] ?? b;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search name or tags',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Create folder',
              onPressed: _createFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ],
        ),
      ),
      if (tags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in tags)
                FilterChip(
                  label: Text(
                    entry.value,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  padding: EdgeInsets.zero,
                  visualDensity: const VisualDensity(
                    horizontal: -2,
                    vertical: -3,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  showCheckmark: false,
                  selected: _selectedTags.contains(entry.key),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTags.add(entry.key);
                      } else {
                        _selectedTags.remove(entry.key);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
    ];

    if (widget.supportsClientScope) {
      children.add(_scopeTitle(context, 'Shared library'));
    }
    children.addAll(_buildFolderGroups('shared', shared, includeEmpty: true));

    if (widget.supportsClientScope && clientIds.isNotEmpty) {
      children.add(_scopeTitle(context, 'Clients'));
      for (final clientId in clientIds) {
        final name = widget.activeClientNames[clientId] ?? clientId;
        final clientItems = visible
            .where((item) => widget.clientAthleteIdOf(item) == clientId)
            .toList();
        final scopeId = 'client-$clientId';
        final collapsed = _isCollapsed(scopeId, '__client_scope__');
        children.add(
          Semantics(
            header: true,
            button: true,
            label: '${collapsed ? 'Expand' : 'Collapse'} $name, '
                '${clientItems.length} items',
            onTap: () => _toggleCollapsed(scopeId, '__client_scope__'),
            explicitChildNodes: true,
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 24, right: 8),
              leading: const Icon(Icons.person_outline),
              title: Text('$name (${clientItems.length})'),
              trailing: Semantics(
                container: true,
                button: true,
                label: '${collapsed ? 'Expand' : 'Collapse'} $name',
                excludeSemantics: true,
                child: IconButton(
                  tooltip: '${collapsed ? 'Expand' : 'Collapse'} $name',
                  onPressed: () =>
                      _toggleCollapsed(scopeId, '__client_scope__'),
                  icon: Icon(
                    collapsed ? Icons.expand_more : Icons.expand_less,
                  ),
                ),
              ),
              onTap: () => _toggleCollapsed(scopeId, '__client_scope__'),
            ),
          ),
        );
        if (!collapsed) {
          children.addAll(_buildFolderGroups(scopeId, clientItems));
        }
      }
    }

    if (visible.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              widget.items.isEmpty
                  ? widget.emptyMessage
                  : 'No library items match these filters.',
            ),
          ),
        ),
      );
    }
    return ListView(children: children);
  }

  Widget _scopeTitle(BuildContext context, String text, {int level = 1}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, level == 1 ? 20 : 16, 16, 4),
      child: Text(
        text,
        style: level == 1
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.titleSmall,
      ),
    );
  }

  List<Widget> _buildFolderGroups(
    String scopeId,
    List<T> items, {
    bool includeEmpty = false,
  }) {
    final validFolderIds = widget.folders.map((folder) => folder.id).toSet();
    final groups = <String?, List<T>>{};
    for (final item in items) {
      final folderId = widget.folderIdOf(item);
      final key = validFolderIds.contains(folderId) ? folderId : null;
      groups.putIfAbsent(key, () => []).add(item);
    }
    return [
      for (final folder in widget.folders)
        if (includeEmpty || (groups[folder.id]?.isNotEmpty ?? false))
          ..._buildGroup(scopeId, folder, groups[folder.id] ?? const []),
      ..._buildGroup(scopeId, null, groups[null] ?? const []),
    ];
  }

  List<Widget> _buildGroup(
    String scopeId,
    LibraryFolder? folder,
    List<T> items,
  ) {
    final folderId = folder?.id;
    final collapsed = _isCollapsed(scopeId, folderId);
    final label = folder?.name ?? 'Unfiled';
    return [
      Semantics(
        header: true,
        button: true,
        label: '${collapsed ? 'Expand' : 'Collapse'} $label, '
            '${items.length} items',
        onTap: () => _toggleCollapsed(scopeId, folderId),
        explicitChildNodes: true,
        child: ListTile(
          dense: true,
          leading: Icon(folder == null ? Icons.inbox_outlined : Icons.folder),
          title: Text('$label (${items.length})'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (folder != null)
                PopupMenuButton<String>(
                  tooltip: '$label folder actions',
                  onSelected: (action) {
                    if (action == 'rename') {
                      _renameFolder(folder);
                    } else if (action == 'delete') {
                      _deleteFolder(folder);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              Semantics(
                container: true,
                button: true,
                label: '${collapsed ? 'Expand' : 'Collapse'} $label',
                excludeSemantics: true,
                child: IconButton(
                  tooltip: '${collapsed ? 'Expand' : 'Collapse'} $label',
                  onPressed: () => _toggleCollapsed(scopeId, folderId),
                  icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
                ),
              ),
            ],
          ),
          onTap: () => _toggleCollapsed(scopeId, folderId),
        ),
      ),
      if (!collapsed)
        for (final item in items)
          widget.tileBuilder(
            context,
            item,
            IconButton(
              tooltip: 'Organize ${widget.nameOf(item)}',
              onPressed: () => _editOrganization(item),
              icon: const Icon(Icons.label_outline),
            ),
          ),
    ];
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _createFolder() async {
    final name = await _textDialog(
      title: 'Create folder',
      label: 'Folder name',
    );
    if (name == null || name.trim().isEmpty) return;
    await _runMutation(() => widget.createFolder(name.trim()));
  }

  Future<void> _renameFolder(LibraryFolder folder) async {
    final name = await _textDialog(
      title: 'Rename folder',
      label: 'Folder name',
      initialValue: folder.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await _runMutation(() => widget.renameFolder(folder, name.trim()));
  }

  Future<void> _deleteFolder(LibraryFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete folder?'),
        content: const Text(
          'Items in this folder will be moved to Unfiled. No library items '
          'will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete folder'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runMutation(() => widget.deleteFolder(folder));
  }

  Future<void> _editOrganization(T item) async {
    final tagsController = TextEditingController(
      text: widget.tagsOf(item).join(', '),
    );
    var folderId = widget.folderIdOf(item);
    var clientId = widget.clientAthleteIdOf(item);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Organize ${widget.nameOf(item)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    helperText: 'Separate tags with commas',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: widget.folders.any((folder) => folder.id == folderId)
                      ? folderId
                      : null,
                  decoration: const InputDecoration(labelText: 'Folder'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Unfiled')),
                    for (final folder in widget.folders)
                      DropdownMenuItem(
                        value: folder.id,
                        child: Text(folder.name),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => folderId = value),
                ),
                if (widget.supportsClientScope) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: widget.activeClientNames.containsKey(clientId)
                        ? clientId
                        : null,
                    decoration: const InputDecoration(labelText: 'Library'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Shared library'),
                      ),
                      for (final entry in widget.activeClientNames.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => clientId = value),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) {
      tagsController.dispose();
      return;
    }
    final rawTags = tagsController.text.split(',');
    tagsController.dispose();
    await _runMutation(
      () => widget.updateOrganization(
        item,
        tags: normalizeLibraryTags(
          rawTags.where((tag) => tag.trim().isNotEmpty),
        ),
        folderId: folderId,
        clientAthleteId: clientId,
      ),
    );
  }

  Future<void> _runMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update library: $error')),
      );
    }
  }
}
