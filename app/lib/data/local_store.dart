import 'models/json.dart';
import 'local_store_io.dart' if (dart.library.js_interop) 'local_store_web.dart' as platform;

/// Device storage for the two local files of contract §6:
///
/// * `state.json` — docs, rows, proposals, dirty sets and the sync cursor ([LocalData]);
/// * `active.json` — the workout in progress (never synced).
///
/// Implementations serialise their writes and write `state.json` atomically.
abstract interface class LocalStore {
  /// The store for this platform: files in the app documents dir, or `shared_preferences` on web.
  factory LocalStore.platform() => platform.createPlatformStore();

  Future<JsonMap?> readState();
  Future<void> writeState(JsonMap state);
  Future<JsonMap?> readActive();
  Future<void> writeActive(JsonMap active);
  Future<void> deleteActive();

  /// Deletes both files (sign-out, reset).
  Future<void> clear();
}

/// In-memory [LocalStore] for tests. [log] records every operation in order.
class MemoryLocalStore implements LocalStore {
  MemoryLocalStore({this.state, this.active});

  JsonMap? state;
  JsonMap? active;
  final List<String> log = [];

  @override
  Future<JsonMap?> readState() async => state == null ? null : deepCopyMap(state!);

  @override
  Future<void> writeState(JsonMap value) async {
    log.add('writeState');
    state = deepCopyMap(value);
  }

  @override
  Future<JsonMap?> readActive() async => active == null ? null : deepCopyMap(active!);

  @override
  Future<void> writeActive(JsonMap value) async {
    log.add('writeActive');
    active = deepCopyMap(value);
  }

  @override
  Future<void> deleteActive() async {
    log.add('deleteActive');
    active = null;
  }

  @override
  Future<void> clear() async {
    log.add('clear');
    state = null;
    active = null;
  }
}
