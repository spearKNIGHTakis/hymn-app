import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/hymn.dart';
import '../repositories/hymn_repository.dart';
import '../services/audio_service.dart';
import '../services/download_manager.dart';
import '../services/user_store.dart';
import '../theme/app_theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final Future<List<Hymn>> _catalogue;
  int _tab = 0;
  HymnLanguage? _languageFilter;

  @override
  void initState() {
    super.initState();
    _catalogue = context.read<HymnRepository>().loadBundled();
    _languageFilter = context.read<UserStore>().defaultLanguage == 'twi'
        ? HymnLanguage.twi
        : HymnLanguage.english;
  }

  void _open(Hymn hymn) {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => HymnDetailScreen(hymn: hymn)));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Hymn>>(
        future: _catalogue,
        builder: (context, snapshot) {
          final hymns = snapshot.data ?? const <Hymn>[];
          final pages = [
            HomeScreen(
              hymns: hymns,
              openHymn: _open,
              openTab: (value) => setState(() => _tab = value),
              openLanguage: (language) => setState(() {
                _languageFilter = language;
                _tab = 1;
              }),
            ),
            HymnListScreen(
                hymns: hymns,
                openHymn: _open,
                initialLanguage: _languageFilter),
            HymnListScreen(hymns: hymns, favouritesOnly: true, openHymn: _open),
            DownloadsScreen(hymns: hymns),
            ProgressScreen(hymns: hymns),
          ];
          return Scaffold(
            appBar: AppBar(
              title: const Text('PCG Hymns',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen())),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            body: snapshot.hasError
                ? ErrorState(
                    message:
                        'The hymn catalogue could not be loaded: ${snapshot.error}')
                : snapshot.connectionState != ConnectionState.done
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          Expanded(
                              child:
                                  IndexedStack(index: _tab, children: pages)),
                          if (hymns.isNotEmpty)
                            MiniPlayer(hymns: hymns, openHymn: _open),
                        ],
                      ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (value) => setState(() => _tab = value),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home'),
                NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book),
                    label: 'Hymns'),
                NavigationDestination(
                    icon: Icon(Icons.favorite_border),
                    selectedIcon: Icon(Icons.favorite),
                    label: 'Favourites'),
                NavigationDestination(
                    icon: Icon(Icons.download_outlined),
                    selectedIcon: Icon(Icons.download),
                    label: 'Downloads'),
                NavigationDestination(
                    icon: Icon(Icons.insights_outlined),
                    selectedIcon: Icon(Icons.insights),
                    label: 'Progress'),
              ],
            ),
          );
        },
      );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen(
      {required this.hymns,
      required this.openHymn,
      required this.openTab,
      required this.openLanguage,
      super.key});
  final List<Hymn> hymns;
  final ValueChanged<Hymn> openHymn;
  final ValueChanged<int> openTab;
  final ValueChanged<HymnLanguage> openLanguage;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserStore>();
    final recent = store.recentIds
        .map((id) => hymns.where((hymn) => hymn.id == id).firstOrNull)
        .whereType<Hymn>()
        .take(3)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Sing in Faith',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('A place for the hymns we sing together.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 22),
        SearchField(hymns: hymns, openHymn: openHymn),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: LanguageTile(
                  title: 'English hymns',
                  language: HymnLanguage.english,
                  onTap: () => openLanguage(HymnLanguage.english))),
          const SizedBox(width: 12),
          Expanded(
              child: LanguageTile(
                  title: 'Twi hymns',
                  language: HymnLanguage.twi,
                  onTap: () => openLanguage(HymnLanguage.twi))),
        ]),
        const SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Recently played',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (recent.isNotEmpty)
            TextButton(
                onPressed: () => openTab(1), child: const Text('Browse')),
        ]),
        if (recent.isEmpty)
          const EmptyState(
              icon: Icons.history,
              title: 'Your recently played hymns will appear here',
              detail: 'Start a recording to keep it close at hand.')
        else
          ...recent
              .map((hymn) => HymnRow(hymn: hymn, onTap: () => openHymn(hymn))),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.favorite_outline, color: AppColors.red),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('Saved favourites',
                      style: TextStyle(fontWeight: FontWeight.w600))),
              TextButton(
                  onPressed: () => openTab(2), child: const Text('View')),
            ]),
          ),
        ),
      ],
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({required this.hymns, required this.openHymn, super.key});
  final List<Hymn> hymns;
  final ValueChanged<Hymn> openHymn;

  @override
  Widget build(BuildContext context) => TextField(
        decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search number, title or lyrics'),
        onSubmitted: (query) {
          final result =
              context.read<HymnRepository>().search(hymns, query: query);
          if (result.length == 1) {
            openHymn(result.single);
          } else {
            Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SearchResultsScreen(
                    hymns: result, openHymn: openHymn, query: query)));
          }
        },
      );
}

class SearchResultsScreen extends StatelessWidget {
  const SearchResultsScreen(
      {required this.hymns,
      required this.openHymn,
      required this.query,
      super.key});
  final List<Hymn> hymns;
  final ValueChanged<Hymn> openHymn;
  final String query;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Search: $query')),
        body: hymns.isEmpty
            ? const EmptyState(
                icon: Icons.search_off,
                title: 'No matching hymns',
                detail: 'Try a different number, title or lyric.')
            : ListView(
                children: hymns
                    .map((hymn) =>
                        HymnRow(hymn: hymn, onTap: () => openHymn(hymn)))
                    .toList()),
      );
}

class LanguageTile extends StatelessWidget {
  const LanguageTile(
      {required this.title,
      required this.language,
      required this.onTap,
      super.key});
  final String title;
  final HymnLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Ink(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: language == HymnLanguage.english
                ? AppColors.blue
                : AppColors.green,
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
              language == HymnLanguage.english
                  ? Icons.menu_book_outlined
                  : Icons.library_books_outlined,
              color: Colors.white),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          const Text('Browse collection',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class HymnListScreen extends StatefulWidget {
  const HymnListScreen(
      {required this.hymns,
      required this.openHymn,
      this.favouritesOnly = false,
      this.initialLanguage,
      super.key});
  final List<Hymn> hymns;
  final ValueChanged<Hymn> openHymn;
  final bool favouritesOnly;
  final HymnLanguage? initialLanguage;

  @override
  State<HymnListScreen> createState() => _HymnListScreenState();
}

class _HymnListScreenState extends State<HymnListScreen> {
  String _query = '';
  HymnLanguage? _language;
  String _sortBy = 'number';

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
  }

  @override
  void didUpdateWidget(covariant HymnListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLanguage != widget.initialLanguage) {
      _language = widget.initialLanguage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final favourites = context.watch<UserStore>().favourites;
    final filtered = context.read<HymnRepository>().search(
          widget.hymns.where(
              (hymn) => !widget.favouritesOnly || favourites.contains(hymn.id)),
          query: _query,
          language: _language,
          sortBy: _sortBy,
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Number, title or lyrics'),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SegmentedButton<HymnLanguage?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('All')),
                  ButtonSegment(
                      value: HymnLanguage.english, label: Text('English')),
                  ButtonSegment(value: HymnLanguage.twi, label: Text('Twi')),
                ],
                selected: {_language},
                onSelectionChanged: (value) =>
                    setState(() => _language = value.first),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Sort hymns',
              initialValue: _sortBy,
              onSelected: (value) => setState(() => _sortBy = value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'number', child: Text('Hymn number')),
                PopupMenuItem(value: 'title', child: Text('Title'))
              ],
              icon: const Icon(Icons.sort),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: filtered.isEmpty
            ? EmptyState(
                icon: widget.favouritesOnly
                    ? Icons.favorite_border
                    : Icons.menu_book_outlined,
                title: widget.favouritesOnly
                    ? 'No saved favourites'
                    : (widget.hymns.isEmpty
                        ? 'Catalogue awaiting verified content'
                        : 'No matching hymns'),
                detail: widget.hymns.isEmpty
                    ? 'Verified hymn entries will appear here when added to the catalogue.'
                    : 'Try another search or language filter.',
              )
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, index) => HymnRow(
                    hymn: filtered[index],
                    onTap: () => widget.openHymn(filtered[index]))),
      ),
    ]);
  }
}

class HymnRow extends StatelessWidget {
  const HymnRow({required this.hymn, required this.onTap, super.key});
  final Hymn hymn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(hymn.number, style: const TextStyle(fontSize: 12))),
        title: Text(hymn.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            '${hymn.language.label} · ${hymn.recordings.length} recordings'),
        trailing: const Icon(Icons.chevron_right),
      );
}

class HymnDetailScreen extends StatefulWidget {
  const HymnDetailScreen({required this.hymn, super.key});
  final Hymn hymn;

  @override
  State<HymnDetailScreen> createState() => _HymnDetailScreenState();
}

class _HymnDetailScreenState extends State<HymnDetailScreen> {
  HymnRecording? _recording;
  bool _keepAwake = false;
  bool _busy = false;
  String? _playbackError;

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _play() async {
    final recording = _recording;
    if (recording == null) {
      return;
    }
    final audio = context.read<HymnAudioService>();
    final downloads = context.read<DownloadManager>();
    final store = context.read<UserStore>();
    setState(() {
      _busy = true;
      _playbackError = null;
    });
    try {
      await audio.play(widget.hymn, recording, downloads);
      await store.markPlayed(widget.hymn.id);
    } catch (error) {
      if (mounted) setState(() => _playbackError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserStore>();
    final player = context.watch<HymnAudioService>().player;
    final downloads = context.watch<DownloadManager>();
    final hymn = widget.hymn;
    _recording ??= hymn.recordings.firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text('Hymn ${hymn.number}'),
        actions: [
          IconButton(
            tooltip: store.favourites.contains(hymn.id)
                ? 'Remove favourite'
                : 'Add favourite',
            onPressed: () => store.toggleFavourite(hymn.id),
            icon: Icon(
                store.favourites.contains(hymn.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: AppColors.red),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
        children: [
          Text(hymn.language.label.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.green, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(hymn.title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (hymn.author != null || hymn.composer != null) ...[
            const SizedBox(height: 8),
            Text(
                [
                  if (hymn.author != null) 'Words: ${hymn.author}',
                  if (hymn.composer != null) 'Music: ${hymn.composer}'
                ].join(' · '),
                style: const TextStyle(color: AppColors.muted)),
          ],
          const SizedBox(height: 18),
          if (hymn.stanzas.isEmpty)
            const EmptyState(
                icon: Icons.menu_book,
                title: 'Lyrics not added yet',
                detail: 'Verified lyrics will appear here when supplied.')
          else
            ...hymn.stanzas.asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('STANZA ${entry.key + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.muted)),
                        const SizedBox(height: 8),
                        Text(entry.value,
                            style: TextStyle(
                                fontSize: 20 * store.lyricScale, height: 1.65)),
                      ]),
                )),
          if (hymn.chorus != null) ...[
            Text('CHORUS',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.muted)),
            const SizedBox(height: 8),
            Text(hymn.chorus!,
                style: TextStyle(
                    fontSize: 20 * store.lyricScale,
                    height: 1.65,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
          ],
          if (hymn.recordings.isEmpty)
            const ListTile(
                leading: Icon(Icons.music_off),
                title: Text('Recording not available yet'))
          else ...[
            DropdownButtonFormField<HymnRecording>(
              initialValue: _recording,
              decoration: const InputDecoration(labelText: 'Recording'),
              items: hymn.recordings
                  .map((recording) => DropdownMenuItem(
                      value: recording, child: Text(recording.type.label)))
                  .toList(),
              onChanged: (value) => setState(() {
                _recording = value;
                _playbackError = null;
              }),
            ),
            const SizedBox(height: 8),
            Row(children: [
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (context, snapshot) {
                  final isCurrent =
                      context.read<HymnAudioService>().currentHymnId == hymn.id;
                  final playing =
                      isCurrent && (snapshot.data?.playing ?? false);
                  final available = _recording?.url != null ||
                      downloads.forRecording(_recording?.id ?? '') != null;
                  return FilledButton.icon(
                    onPressed: _busy || !available
                        ? null
                        : () => playing ? player.pause() : unawaited(_play()),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(playing ? Icons.pause : Icons.play_arrow),
                    label: Text(playing ? 'Pause' : 'Listen'),
                  );
                },
              ),
              const SizedBox(width: 8),
              if (_recording?.url != null &&
                  downloads.forRecording(_recording!.id) == null)
                IconButton.filledTonal(
                  tooltip: 'Download recording',
                  onPressed: () async {
                    try {
                      await downloads.download(
                          recordingId: _recording!.id,
                          hymnId: hymn.id,
                          url: _recording!.url!);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Recording downloaded for offline playback.')));
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Download failed: $error')));
                      }
                    }
                  },
                  icon: const Icon(Icons.download),
                ),
              const Spacer(),
              IconButton(
                  tooltip: 'Repeat',
                  onPressed: () => player.setLoopMode(
                      player.loopMode == LoopMode.off
                          ? LoopMode.one
                          : LoopMode.off),
                  icon: const Icon(Icons.repeat)),
              PopupMenuButton<double>(
                tooltip: 'Playback speed',
                onSelected: player.setSpeed,
                itemBuilder: (_) => const [0.75, 1.0, 1.25, 1.5]
                    .map((speed) =>
                        PopupMenuItem(value: speed, child: Text('${speed}x')))
                    .toList(),
                icon: const Icon(Icons.speed),
              ),
            ]),
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snapshot) {
                final duration = player.duration ?? Duration.zero;
                final position = snapshot.data ?? Duration.zero;
                return Row(children: [
                  Text(_durationLabel(position)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: duration.inMilliseconds.clamp(1, 1 << 30).toDouble(),
                      value: position.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toDouble(),
                      onChanged: duration == Duration.zero
                          ? null
                          : (value) => player
                              .seek(Duration(milliseconds: value.round())),
                    ),
                  ),
                  Text(_durationLabel(duration)),
                ]);
              },
            ),
            if (_playbackError != null)
              Text(_playbackError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep screen awake while reading'),
            value: _keepAwake,
            onChanged: (value) {
              setState(() => _keepAwake = value);
              value ? WakelockPlus.enable() : WakelockPlus.disable();
            },
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _confirmSung(context, store, hymn),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('I sang this hymn'),
          ),
          if (hymn.copyright != null ||
              hymn.source != null ||
              hymn.permission != null) ...[
            const Divider(height: 32),
            Text(
                [
                  if (hymn.source != null) 'Source: ${hymn.source}',
                  if (hymn.copyright != null) hymn.copyright!,
                  if (hymn.permission != null) 'Permission: ${hymn.permission}'
                ].join('\n'),
                style: const TextStyle(color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmSung(
      BuildContext context, UserStore store, Hymn hymn) async {
    await store.markSung(hymn.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Added to your singing history.'),
        action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              final latest = store.singingEvents
                  .lastWhere((event) => event.hymnId == hymn.id);
              store.undoSingingEvent(latest);
            }),
      ));
    }
  }
}

String _durationLabel(Duration duration) =>
    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({required this.hymns, required this.openHymn, super.key});
  final List<Hymn> hymns;
  final ValueChanged<Hymn> openHymn;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<HymnAudioService>();
    return StreamBuilder<PlayerState>(
      stream: audio.player.playerStateStream,
      builder: (context, snapshot) {
        final hymn =
            hymns.where((item) => item.id == audio.currentHymnId).firstOrNull;
        if (hymn == null) return const SizedBox.shrink();
        final playing = snapshot.data?.playing ?? false;
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: ListTile(
            onTap: () => openHymn(hymn),
            leading: const Icon(Icons.graphic_eq, color: AppColors.blue),
            title:
                Text(hymn.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('Hymn ${hymn.number}'),
            trailing: IconButton(
              tooltip: playing ? 'Pause' : 'Resume',
              onPressed: () =>
                  playing ? audio.player.pause() : audio.player.play(),
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
          ),
        );
      },
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({required this.hymns, super.key});
  final List<Hymn> hymns;

  @override
  Widget build(BuildContext context) => Consumer<DownloadManager>(
        builder: (context, manager, _) {
          final entries = manager.entries;
          if (entries.isEmpty && manager.activeDownloads.isEmpty) {
            return const EmptyState(
                icon: Icons.download_outlined,
                title: 'No downloaded recordings',
                detail: 'Download a recording from a hymn to listen offline.');
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Storage used  ·  ${_bytesLabel(manager.storageBytes)}',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...manager.activeDownloads.entries.map((active) {
              final hymn =
                  hymns.where((item) => item.id == active.value).firstOrNull;
              final transfer = manager.progress[active.key] ?? 0;
              return Card(
                  child: ListTile(
                leading: const Icon(Icons.downloading, color: AppColors.blue),
                title: Text(hymn?.title ?? 'Downloading recording'),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${hymn?.number ?? ''} · Downloading · ${transfer > 0 ? '${(transfer * 100).round()}%' : 'Checking connection'}'),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                          value: transfer > 0 ? transfer : null),
                    ]),
              ));
            }),
            ...entries.map((entry) {
              final hymn =
                  hymns.where((item) => item.id == entry.hymnId).firstOrNull;
              final recording = hymn?.recordings
                  .where((item) => item.id == entry.recordingId)
                  .firstOrNull;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.offline_pin_outlined,
                      color: AppColors.green),
                  title: Text(hymn?.title ?? 'Unavailable catalogue item'),
                  subtitle: Text(
                      '${hymn?.number ?? ''} · ${recording?.type.label ?? 'Recording'} · ${_fileSizeLabel(entry.path)}'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Manage download',
                    onSelected: (value) async {
                      if (value != 'delete') return;
                      final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                                title: const Text('Delete recording?'),
                                content: const Text(
                                    'This removes the downloaded audio from this device.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('Delete'))
                                ],
                              ));
                      if (confirmed == true) {
                        await manager.delete(entry.recordingId);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'delete', child: Text('Delete download'))
                    ],
                  ),
                ),
              );
            }),
          ]);
        },
      );
}

String _fileSizeLabel(String path) {
  try {
    final bytes = File(path).lengthSync();
    return _bytes(bytes);
  } catch (_) {
    return 'Unknown size';
  }
}

String _bytesLabel(int bytes) => _bytes(bytes);
String _bytes(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(0)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({required this.hymns, super.key});
  final List<Hymn> hymns;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserStore>();
    final events = [...store.singingEvents]
      ..sort((a, b) => b.at.compareTo(a.at));
    final sungIds = events.map((event) => event.hymnId).toSet();
    final englishIds = hymns
        .where((hymn) => hymn.language == HymnLanguage.english)
        .map((hymn) => hymn.id)
        .toSet();
    final twiIds = hymns
        .where((hymn) => hymn.language == HymnLanguage.twi)
        .map((hymn) => hymn.id)
        .toSet();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Your singing',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: _ProgressMetric(
                label: 'Distinct hymns', value: '${sungIds.length}')),
        const SizedBox(width: 12),
        Expanded(
            child: _ProgressMetric(
                label: 'Singing events', value: '${events.length}')),
      ]),
      const SizedBox(height: 12),
      _LanguageProgress(
          label: 'English',
          count: sungIds.intersection(englishIds).length,
          total: englishIds.length,
          color: AppColors.blue),
      _LanguageProgress(
          label: 'Twi',
          count: sungIds.intersection(twiIds).length,
          total: twiIds.length,
          color: AppColors.green),
      const SizedBox(height: 22),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Singing history',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (events.isNotEmpty)
          IconButton(
              tooltip: 'Clear history',
              onPressed: () => _clearHistory(context, store),
              icon: const Icon(Icons.delete_outline)),
      ]),
      if (events.isEmpty)
        const EmptyState(
            icon: Icons.history,
            title: 'No singing history yet',
            detail: 'Use “I sang this hymn” to record a singing event.')
      else
        ...events.map((event) {
          final hymn =
              hymns.where((item) => item.id == event.hymnId).firstOrNull;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                const Icon(Icons.check_circle_outline, color: AppColors.green),
            title: Text(hymn?.title ?? 'Removed catalogue entry'),
            subtitle: Text(
                '${hymn?.number ?? ''} · ${MaterialLocalizations.of(context).formatMediumDate(event.at)}'),
            trailing: IconButton(
                tooltip: 'Undo this event',
                icon: const Icon(Icons.undo),
                onPressed: () => store.undoSingingEvent(event)),
          );
        }),
    ]);
  }

  Future<void> _clearHistory(BuildContext context, UserStore store) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Clear singing history?'),
              content: const Text(
                  'This removes all singing events stored on this device.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Clear history'))
              ],
            ));
    if (confirm == true) await store.clearSingingEvents();
  }
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(color: AppColors.muted))
          ])));
}

class _LanguageProgress extends StatelessWidget {
  const _LanguageProgress(
      {required this.label,
      required this.count,
      required this.total,
      required this.color});
  final String label;
  final int count;
  final int total;
  final Color color;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('$label  ·  $count of $total distinct hymns'),
        subtitle: LinearProgressIndicator(
            value: total == 0 ? 0 : count / total, color: color),
      );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserStore>();
    final downloads = context.watch<DownloadManager>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        DropdownButtonFormField<ThemeMode>(
          initialValue: store.themeMode,
          decoration: const InputDecoration(labelText: 'Theme'),
          items: const [
            DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
            DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark'))
          ],
          onChanged: (value) {
            if (value != null) store.setThemeMode(value);
          },
        ),
        const SizedBox(height: 18),
        Text('Reading', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
            title: const Text('Lyric text size'),
            subtitle: Slider(
                value: store.lyricScale,
                min: 0.8,
                max: 1.5,
                divisions: 7,
                label: '${(store.lyricScale * 100).round()}%',
                onChanged: store.setLyricScale)),
        DropdownButtonFormField<String>(
          initialValue: store.defaultLanguage,
          decoration: const InputDecoration(labelText: 'Default language'),
          items: const [
            DropdownMenuItem(value: 'english', child: Text('English')),
            DropdownMenuItem(value: 'twi', child: Text('Twi'))
          ],
          onChanged: (value) {
            if (value != null) store.setDefaultLanguage(value);
          },
        ),
        const SizedBox(height: 18),
        Text('Downloads', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Downloaded audio'),
            trailing: Text(_bytesLabel(downloads.storageBytes))),
        const Divider(height: 28),
        Text('Privacy', style: Theme.of(context).textTheme.titleMedium),
        const Text(
            'Favourites, preferences, downloads and singing history stay on this device. No account or analytics are used.'),
        const SizedBox(height: 20),
        const Text('PCG Hymns · 1.0.0',
            style: TextStyle(color: AppColors.muted)),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {required this.icon,
      required this.title,
      required this.detail,
      super.key});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 34, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted)),
        ])),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, super.key});
  final String message;
  @override
  Widget build(BuildContext context) => EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      detail: message);
}
