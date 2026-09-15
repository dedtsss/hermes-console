import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/kanban.dart';
import '../theme/app_theme.dart';

typedef KanbanTaskAction = Future<void> Function();
typedef KanbanCommentAction = Future<void> Function(String body);
typedef KanbanAttachmentAction = Future<void> Function(
  KanbanAttachment attachment,
);
typedef KanbanRunAction = Future<void> Function(KanbanRun run);
typedef KanbanLinkedTaskAction = Future<void> Function(String taskId);

/// Contenido del detalle Kanban 0.20. La red y las confirmaciones permanecen
/// en [TasksScreen]; este widget solo representa el snapshot autoritativo y
/// evita que sus actualizaciones reconstruyan el tablero completo.
class KanbanTaskDetailSurface extends StatefulWidget {
  final KanbanTaskDetail detail;
  final bool readOnly;
  final KanbanCommentAction? onAddComment;
  final KanbanTaskAction? onUploadAttachment;
  final KanbanAttachmentAction? onDownloadAttachment;
  final KanbanAttachmentAction? onDeleteAttachment;
  final KanbanRunAction? onInspectRun;
  final KanbanRunAction? onTerminateRun;
  final KanbanTaskAction? onShowLog;
  final KanbanTaskAction? onReclaim;
  final KanbanTaskAction? onReassign;
  final KanbanTaskAction? onSpecify;
  final KanbanTaskAction? onDecompose;
  final KanbanTaskAction? onConfigureModel;
  final KanbanLinkedTaskAction? onOpenLinkedTask;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onMove;
  final VoidCallback? onEdit;

  const KanbanTaskDetailSurface({
    required this.detail,
    required this.readOnly,
    this.onAddComment,
    this.onUploadAttachment,
    this.onDownloadAttachment,
    this.onDeleteAttachment,
    this.onInspectRun,
    this.onTerminateRun,
    this.onShowLog,
    this.onReclaim,
    this.onReassign,
    this.onSpecify,
    this.onDecompose,
    this.onConfigureModel,
    this.onOpenLinkedTask,
    this.onArchive,
    this.onDelete,
    this.onMove,
    this.onEdit,
    super.key,
  });

  @override
  State<KanbanTaskDetailSurface> createState() =>
      _KanbanTaskDetailSurfaceState();
}

class _KanbanTaskDetailSurfaceState extends State<KanbanTaskDetailSurface> {
  final TextEditingController _commentController = TextEditingController();
  String? _busyAction;
  bool _showAllEvents = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant KanbanTaskDetailSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.task.id != widget.detail.task.id) {
      _showAllEvents = false;
    }
  }

  Future<void> _run(String action, KanbanTaskAction callback) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = action);
    try {
      await callback();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _submitComment() async {
    final callback = widget.onAddComment;
    final body = _commentController.text.trim();
    if (callback == null || body.isEmpty || _busyAction != null) return;
    setState(() => _busyAction = 'comment');
    try {
      await callback(body);
      _commentController.clear();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final s = Strings.of(context);
    final copy = _KanbanDetailCopy(s);
    final detail = widget.detail;
    final task = detail.task;
    return SingleChildScrollView(
      key: const ValueKey('kanban-task-detail-rich'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        key: ValueKey('kanban-task-detail-${task.id}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              task.title,
              style: TextStyle(
                fontSize: 17,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            task.id,
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MetaPill(
                icon: Icons.flag_outlined,
                label: task.status.replaceAll('_', ' '),
                color: colors.accent,
              ),
              if (task.assignee?.isNotEmpty == true)
                _MetaPill(
                  icon: Icons.person_outline,
                  label: task.assignee!,
                  color: colors.textSecondary,
                ),
              if (task.hasProgress)
                _MetaPill(
                  icon: Icons.donut_large_rounded,
                  label: '${task.progressDone}/${task.progressTotal}',
                  color: colors.textSecondary,
                ),
            ],
          ),
          if (task.blockReason?.isNotEmpty == true) ...[
            const SizedBox(height: 14),
            _Notice(
              colors: colors,
              icon: Icons.warning_amber_rounded,
              text: task.blockReason!,
              error: true,
            ),
          ] else if (detail.diagnostics.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Notice(
              colors: colors,
              icon: Icons.info_outline_rounded,
              text:
                  '${detail.diagnostics.first.title}: ${detail.diagnostics.first.detail}',
            ),
          ] else if (task.latestSummary?.isNotEmpty == true) ...[
            const SizedBox(height: 14),
            _Notice(
              colors: colors,
              icon: Icons.summarize_outlined,
              text: task.latestSummary!,
            ),
          ],
          if (widget.readOnly) ...[
            const SizedBox(height: 14),
            _Notice(
              key: const ValueKey('kanban-detail-read-only'),
              colors: colors,
              icon: Icons.lock_outline_rounded,
              text: copy.readOnly,
            ),
          ],
          if (task.body.isNotEmpty) ...[
            const SizedBox(height: 16),
            _DetailSection(
              key: const ValueKey('kanban-detail-objective'),
              colors: colors,
              title: copy.objective,
              summary: Text(
                task.body,
                key: const ValueKey('kanban-task-detail-body-summary'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              child: SelectableText(
                task.body,
                key: const ValueKey('kanban-task-detail-body'),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
          if (task.result?.isNotEmpty == true) ...[
            const SizedBox(height: 18),
            _DetailSection(
              key: const ValueKey('kanban-detail-result'),
              colors: colors,
              title: copy.result,
              child: SelectableText(
                task.result!,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
          if (task.latestSummary?.isNotEmpty == true &&
              task.latestSummary != task.result) ...[
            const SizedBox(height: 18),
            _DetailSection(
              colors: colors,
              title: copy.latestSummary,
              child: SelectableText(
                task.latestSummary!,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
          if (detail.diagnostics.isNotEmpty) ...[
            const SizedBox(height: 18),
            _DetailSection(
              key: const ValueKey('kanban-detail-diagnostics'),
              colors: colors,
              title: '${copy.diagnostics} · ${detail.diagnostics.length}',
              child: Column(
                children: [
                  for (final diagnostic in detail.diagnostics)
                    _DiagnosticTile(colors: colors, diagnostic: diagnostic),
                ],
              ),
            ),
          ],
          if (_hasDependencies(detail)) ...[
            const SizedBox(height: 18),
            _dependencies(colors, copy, detail),
          ],
          if (detail.childResults.isNotEmpty) ...[
            const SizedBox(height: 18),
            _childResults(colors, copy, detail.childResults),
          ],
          if (detail.supports(KanbanTaskDetailCapability.comments)) ...[
            const SizedBox(height: 18),
            _comments(colors, copy, detail.comments),
          ],
          if (detail.supports(KanbanTaskDetailCapability.attachments)) ...[
            const SizedBox(height: 18),
            _attachments(colors, copy, detail.attachments),
          ],
          if (detail.runs.isNotEmpty) ...[
            const SizedBox(height: 18),
            _runs(colors, copy, detail.runs),
          ],
          if (detail.events.isNotEmpty) ...[
            const SizedBox(height: 18),
            _events(colors, copy, detail.events),
          ],
          if (_hasOperationalActions(task)) ...[
            const SizedBox(height: 18),
            _operations(colors, copy, task),
          ],
          const SizedBox(height: 20),
          _taskActions(colors, s, task),
        ],
      ),
    );
  }

  bool _hasDependencies(KanbanTaskDetail detail) =>
      detail.links.parents.isNotEmpty ||
      detail.links.children.isNotEmpty ||
      detail.links.blockedBy.isNotEmpty ||
      detail.links.blocks.isNotEmpty;

  Widget _dependencies(
    HermesThemeColors colors,
    _KanbanDetailCopy copy,
    KanbanTaskDetail detail,
  ) {
    return _DetailSection(
      key: const ValueKey('kanban-detail-links'),
      colors: colors,
      title: copy.dependencies,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _linkRow(colors, copy.parents, detail.links.parents),
          _linkRow(colors, copy.children, detail.links.children),
          _linkRow(colors, copy.blockedBy, detail.links.blockedBy),
          _linkRow(colors, copy.blocks, detail.links.blocks),
        ],
      ),
    );
  }

  Widget _linkRow(HermesThemeColors colors, String label, List<String> ids) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Wrap(
        spacing: 7,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
          for (final id in ids)
            ActionChip(
              label: Text(id, overflow: TextOverflow.ellipsis),
              tooltip: id,
              onPressed: widget.onOpenLinkedTask == null
                  ? null
                  : () => _run('link-$id', () => widget.onOpenLinkedTask!(id)),
            ),
        ],
      ),
    );
  }

  Widget _childResults(
    HermesThemeColors colors,
    _KanbanDetailCopy copy,
    List<KanbanChildResult> children,
  ) {
    return _DetailSection(
      key: const ValueKey('kanban-detail-children'),
      colors: colors,
      title: '${copy.childResults} · ${children.length}',
      child: Column(
        children: [
          for (final child in children)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(child.title, maxLines: 2),
              subtitle: child.latestSummary?.isNotEmpty == true
                  ? Text(child.latestSummary!, maxLines: 3)
                  : null,
              trailing: Text(
                child.status.replaceAll('_', ' '),
                style: TextStyle(fontSize: 11, color: colors.accent),
              ),
              onTap: widget.onOpenLinkedTask == null
                  ? null
                  : () => _run(
                      'child-${child.id}',
                      () => widget.onOpenLinkedTask!(child.id),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _comments(
    HermesThemeColors colors,
    _KanbanDetailCopy copy,
    List<KanbanComment> comments,
  ) {
    final canWrite = !widget.readOnly && widget.onAddComment != null;
    return _DetailSection(
      key: const ValueKey('kanban-detail-comments'),
      colors: colors,
      title: '${copy.comments} · ${comments.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comments.isEmpty)
            Text(
              copy.noComments,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            )
          else
            for (final comment in comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.author.isEmpty ? copy.someone : comment.author,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      comment.body,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          if (canWrite) ...[
            const SizedBox(height: 5),
            TextField(
              key: const ValueKey('kanban-comment-field'),
              controller: _commentController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: widget.detail.task.status == 'running'
                    ? copy.messageWorker
                    : copy.addComment,
                suffixIcon: IconButton(
                  key: const ValueKey('kanban-comment-send'),
                  tooltip: copy.send,
                  onPressed: _busyAction == null ? _submitComment : null,
                  icon: _busyAction == 'comment'
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
              onSubmitted: (_) => _submitComment(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _attachments(
    HermesThemeColors colors,
    _KanbanDetailCopy copy,
    List<KanbanAttachment> attachments,
  ) {
    final canWrite = !widget.readOnly;
    return _DetailSection(
      key: const ValueKey('kanban-detail-attachments'),
      colors: colors,
      title: '${copy.attachments} · ${attachments.length}',
      action: canWrite && widget.onUploadAttachment != null
          ? IconButton(
              key: const ValueKey('kanban-attachment-upload'),
              tooltip: copy.uploadAttachment,
              onPressed: _busyAction == null
                  ? () => _run('upload', widget.onUploadAttachment!)
                  : null,
              icon: const Icon(Icons.attach_file_rounded, size: 19),
            )
          : null,
      child: attachments.isEmpty
          ? Text(
              copy.noAttachments,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            )
          : Column(
              children: [
                for (final attachment in attachments)
                  ListTile(
                    key: ValueKey('kanban-attachment-${attachment.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(
                      attachment.safeFilename,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_formatBytes(attachment.size)),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: copy.download,
                          onPressed:
                              widget.onDownloadAttachment == null ||
                                  _busyAction != null
                              ? null
                              : () => _run(
                                  'download-${attachment.id}',
                                  () =>
                                      widget.onDownloadAttachment!(attachment),
                                ),
                          icon: const Icon(Icons.download_rounded, size: 19),
                        ),
                        if (canWrite && widget.onDeleteAttachment != null)
                          IconButton(
                            tooltip: copy.deleteAttachment,
                            onPressed: _busyAction == null
                                ? () => _run(
                                    'delete-attachment-${attachment.id}',
                                    () =>
                                        widget.onDeleteAttachment!(attachment),
                                  )
                                : null,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                              color: colors.error,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _runs(
    HermesThemeColors colors,
    _KanbanDetailCopy copy,
    List<KanbanRun> runs,
  ) {
    return _DetailSection(
      key: const ValueKey('kanban-detail-runs'),
      colors: colors,
      title: '${copy.runs} · ${runs.length}',
      action: widget.onShowLog == null
          ? null
          : TextButton.icon(
              key: const ValueKey('kanban-task-log'),
              onPressed: _busyAction == null
                  ? () => _run('log', widget.onShowLog!)
                  : null,
              icon: const Icon(Icons.terminal_rounded, size: 16),
              label: Text(copy.log),
            ),
      child: Column(
        children: [
          for (final run in runs)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceVariant.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${copy.run} #${run.id} · ${run.status}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (run.summary?.isNotEmpty == true) ...[
                          const SizedBox(height: 3),
                          SelectableText(
                            run.summary!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: copy.inspect,
                    onPressed:
                        widget.onInspectRun == null || _busyAction != null
                        ? null
                        : () => _run(
                            'inspect-${run.id}',
                            () => widget.onInspectRun!(run),
                          ),
                    icon: const Icon(Icons.monitor_heart_outlined, size: 19),
                  ),
                  if (!widget.readOnly &&
                      run.endedAt == null &&
                      widget.onTerminateRun != null)
                    IconButton(
                      key: ValueKey('kanban-run-terminate-${run.id}'),
                      tooltip: copy.terminate,
                      onPressed: _busyAction == null
                          ? () => _run(
                              'terminate-${run.id}',
                              () => widget.onTerminateRun!(run),
                            )
                          : null,
                      icon: Icon(
                        Icons.stop_circle_outlined,
                        size: 20,
                        color: colors.error,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _events(
    HermesThemeColors colors,
    _KanbanDetailCopy copy,
    List<KanbanTaskEvent> events,
  ) {
    return _DetailSection(
      key: const ValueKey('kanban-detail-events'),
      colors: colors,
      title: '${copy.activity} · ${events.length}',
      child: Column(
        children: [
          for (final event
              in (_showAllEvents ? events.reversed : events.reversed.take(5)))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 6, color: colors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _eventText(event),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (events.length > 5)
            TextButton(
              key: const ValueKey('kanban-events-show-all'),
              onPressed: () => setState(() => _showAllEvents = !_showAllEvents),
              child: Text(_showAllEvents ? copy.showLess : copy.showAll),
            ),
        ],
      ),
    );
  }

  String _eventText(KanbanTaskEvent event) {
    final label = event.kind.replaceAll('_', ' ');
    final primitive = event.payload.entries
        .where(
          (entry) =>
              entry.value == null ||
              entry.value is String ||
              entry.value is num ||
              entry.value is bool,
        )
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' · ');
    return primitive.isEmpty ? label : '$label · $primitive';
  }

  bool _hasOperationalActions(KanbanTask task) {
    if (widget.onConfigureModel != null) return true;
    if (widget.readOnly) return false;
    return widget.onReassign != null ||
        (task.status == 'running' && widget.onReclaim != null) ||
        (task.status == 'triage' &&
            (widget.onSpecify != null || widget.onDecompose != null));
  }

  Widget _operations(
    HermesThemeColors colors,
    _KanbanDetailCopy copy,
    KanbanTask task,
  ) {
    final currentModel = task.modelOverride?.isNotEmpty == true
        ? '${task.providerOverride?.isNotEmpty == true ? '${task.providerOverride}: ' : ''}${task.modelOverride}'
        : copy.inheritModel;
    return _DetailSection(
      key: const ValueKey('kanban-detail-operations'),
      colors: colors,
      title: copy.operations,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onConfigureModel != null)
            ListTile(
              key: const ValueKey('kanban-model-override'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory_rounded),
              title: Text(copy.model),
              subtitle: Text(
                task.reasoningEffort?.isNotEmpty == true
                    ? '$currentModel · ${task.reasoningEffort}'
                    : currentModel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: !widget.readOnly && _busyAction == null,
              onTap: widget.readOnly
                  ? null
                  : () => _run('model', widget.onConfigureModel!),
            ),
          if (!widget.readOnly)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.onReassign != null)
                  OutlinedButton.icon(
                    key: const ValueKey('kanban-task-reassign'),
                    onPressed: _busyAction == null
                        ? () => _run('reassign', widget.onReassign!)
                        : null,
                    icon: const Icon(Icons.person_search_outlined, size: 17),
                    label: Text(copy.reassign),
                  ),
                if (task.status == 'running' && widget.onReclaim != null)
                  OutlinedButton.icon(
                    key: const ValueKey('kanban-task-reclaim'),
                    onPressed: _busyAction == null
                        ? () => _run('reclaim', widget.onReclaim!)
                        : null,
                    icon: const Icon(Icons.restart_alt_rounded, size: 17),
                    label: Text(copy.reclaim),
                  ),
                if (task.status == 'triage' && widget.onSpecify != null)
                  OutlinedButton.icon(
                    key: const ValueKey('kanban-task-specify'),
                    onPressed: _busyAction == null
                        ? () => _run('specify', widget.onSpecify!)
                        : null,
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                    label: Text(copy.specify),
                  ),
                if (task.status == 'triage' && widget.onDecompose != null)
                  OutlinedButton.icon(
                    key: const ValueKey('kanban-task-decompose'),
                    onPressed: _busyAction == null
                        ? () => _run('decompose', widget.onDecompose!)
                        : null,
                    icon: const Icon(Icons.account_tree_outlined, size: 17),
                    label: Text(copy.decompose),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _taskActions(HermesThemeColors colors, Strings s, KanbanTask task) {
    if (widget.readOnly) return const SizedBox.shrink();
    final primaryActions = <Widget>[
      if (task.status != 'archived' && widget.onArchive != null)
        OutlinedButton.icon(
          key: const ValueKey('kanban-task-archive'),
          onPressed: widget.onArchive,
          icon: const Icon(Icons.archive_outlined, size: 16),
          label: Text(s.kanbanArchive),
        ),
      if (widget.onDelete != null)
        OutlinedButton.icon(
          key: const ValueKey('kanban-task-delete-permanent'),
          style: OutlinedButton.styleFrom(foregroundColor: colors.error),
          onPressed: widget.onDelete,
          icon: const Icon(Icons.delete_forever_outlined, size: 16),
          label: Text(s.kanbanDeletePermanent),
        ),
    ];
    final secondaryActions = <Widget>[
      if (widget.onMove != null)
        OutlinedButton.icon(
          onPressed: widget.onMove,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: Text(s.kanbanMove),
        ),
      if (widget.onEdit != null)
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: colors.accent),
          onPressed: widget.onEdit,
          icon: Icon(Icons.edit_outlined, size: 16, color: colors.onAccent),
          label: Text(s.kanbanEdit, style: TextStyle(color: colors.onAccent)),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (primaryActions.isNotEmpty) _responsiveActionGroup(primaryActions),
        if (secondaryActions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _responsiveActionGroup(secondaryActions),
        ],
      ],
    );
  }

  Widget _responsiveActionGroup(List<Widget> actions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                SizedBox(width: double.infinity, child: actions[index]),
                if (index != actions.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              Expanded(child: actions[index]),
              if (index != actions.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}

class _DetailSection extends StatelessWidget {
  final HermesThemeColors colors;
  final String title;
  final Widget child;
  final Widget? action;
  final Widget? summary;
  final bool initiallyExpanded;

  const _DetailSection({
    required this.colors,
    required this.title,
    required this.child,
    this.action,
    this.summary,
    this.initiallyExpanded = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: title,
      child: Material(
        color: colors.surfaceVariant.withValues(alpha: 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.divider.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 13),
          childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          subtitle: summary,
          shape: const Border(),
          collapsedShape: const Border(),
          children: [child],
        ),
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  final HermesThemeColors colors;
  final KanbanDiagnostic diagnostic;

  const _DiagnosticTile({required this.colors, required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    final tone = switch (diagnostic.severity) {
      KanbanDiagnosticSeverity.warning => Colors.amber,
      KanbanDiagnosticSeverity.error ||
      KanbanDiagnosticSeverity.critical => colors.error,
      KanbanDiagnosticSeverity.unknown => colors.textSecondary,
    };
    return Container(
      key: ValueKey('kanban-diagnostic-${diagnostic.kind}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${diagnostic.title}${diagnostic.count > 1 ? ' ×${diagnostic.count}' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            diagnostic.detail,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final HermesThemeColors colors;
  final IconData icon;
  final String text;
  final bool error;

  const _Notice({
    required this.colors,
    required this.icon,
    required this.text,
    this.error = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tone = error ? colors.error : colors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.35, color: tone),
          ),
        ),
      ],
    );
  }
}

class _KanbanDetailCopy {
  final Strings s;

  const _KanbanDetailCopy(this.s);

  String get readOnly => s.kanban020ReadOnly;
  String get objective => s.kanban020Objective;
  String get result => s.kanban020Result;
  String get latestSummary => s.kanban020LatestSummary;
  String get diagnostics => s.kanban020Diagnostics;
  String get dependencies => s.kanban020Dependencies;
  String get parents => s.kanban020Parents;
  String get children => s.kanban020Children;
  String get blockedBy => s.kanban020BlockedBy;
  String get blocks => s.kanban020Blocks;
  String get childResults => s.kanban020ChildTasks;
  String get comments => s.kanban020Comments;
  String get noComments => s.kanban020NoComments;
  String get someone => s.kanban020Someone;
  String get addComment => s.kanban020AddComment;
  String get messageWorker => s.kanban020MessageWorker;
  String get send => s.kanban020Send;
  String get attachments => s.kanban020Attachments;
  String get noAttachments => s.kanban020NoAttachments;
  String get uploadAttachment => s.kanban020UploadAttachment;
  String get download => s.kanban020Download;
  String get deleteAttachment => s.kanban020DeleteAttachment;
  String get runs => s.kanban020Runs;
  String get run => s.kanban020Run;
  String get inspect => s.kanban020Inspect;
  String get terminate => s.kanban020Terminate;
  String get log => s.kanban020WorkerLog;
  String get activity => s.kanban020Activity;
  String get showAll => s.kanban020ShowAll;
  String get showLess => s.kanban020ShowLess;
  String get operations => s.kanban020Operations;
  String get model => s.kanban020TaskModel;
  String get inheritModel => s.kanban020InheritModel;
  String get reassign => s.kanban020Reassign;
  String get reclaim => s.kanban020Reclaim;
  String get specify => s.kanban020Specify;
  String get decompose => s.kanban020Decompose;
}
